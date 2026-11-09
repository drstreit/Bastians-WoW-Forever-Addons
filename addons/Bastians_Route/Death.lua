-- Bastian's Route: the place of death (route.md "The place of death", R26.8): remembers where the
-- character died, plans the way back to the corpse once released as a ghost, and shows the corpse
-- and the earlier deaths as the map layer `route.deaths`.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Death = {}
ns.Death = Death

Death.CORPSE_SIZE = 40 -- the corpse on the map: larger than a route's goal

Death.MAX = 10 -- earlier deaths kept per character
Death.SETTLE = 1 -- seconds after the release before planning (the graveyard's position settles)
Death.SAME_YARDS = 5 -- a route whose goal lies this close to the corpse is the way back
Death.WATCH = 1 -- seconds between looks at the character's state while dead (see Death.Sync)
Death.PLAN_WAIT = 5 -- seconds a planned way back may take to arrive before it is planned again
Death.ATTEMPTS = 5 -- plans of the way back per death before Route stops trying by itself

local mod
local watch -- the ticker of Death.Sync, only while the character is dead
local planned -- { at, tries }: the way back was asked for (it arrives later over the graph)
local released -- when the ghost was first seen: the graveyard's position settles after it

local function char()
  return mod.db.char
end

function Death.List()
  local c = char()
  if type(c.deaths) ~= "table" then
    c.deaths = {}
  end
  return c.deaths
end

-- The corpse { continent, wx, wy, at, exact } while the character is dead or a ghost, else nil.
-- The client's corpse position when it answers (exact), else the remembered place. The client's
-- answer counts without a remembered place too: PLAYER_DEAD may have been missed.
function Death.Corpse()
  local d = char().corpse
  if not d and B.Compat.GetDeathState() == "alive" then
    return nil
  end
  local map, x, y = B.Compat.GetCorpsePosition()
  if map then
    local c, wx, wy = B.Coords.ToWorld(map, x, y)
    if c then
      return { continent = c, wx = wx, wy = wy, at = d and d.at, exact = true }
    end
  end
  return d
end

-- "show": the layer comes on when the player had it off; a corpse must not hide (owner,
-- Forever 08.11.2026: "a clear marker on the map").
local function layerChanged(show)
  B:Fire("BASTIANS_LAYER_CHANGED", "route.deaths", show and "show" or nil)
end

local function remember(d)
  char().corpse = d
  local list = Death.List()
  table.insert(list, 1, d)
  for i = #list, Death.MAX + 1, -1 do
    list[i] = nil
  end
  layerChanged(true)
  return d
end

-- PLAYER_DEAD: the place, unless in an instance (no map position there).
function Death.OnDead()
  local c, wx, wy = B.Coords.Player()
  planned, released = nil, nil
  if not c then
    return nil
  end
  return remember({ continent = c, wx = wx, wy = wy, at = time() })
end

-- Whether the active route leads to the corpse.
local function routingBack(corpse)
  local r = ns.Route.Active()
  local g = r and r.goal
  if not (g and corpse and g.continent == corpse.continent) then
    return false
  end
  local dx, dy = g.wx - corpse.wx, g.wy - corpse.wy
  return dx * dx + dy * dy <= Death.SAME_YARDS * Death.SAME_YARDS
end

local function stopWatch()
  if watch then
    watch:Cancel()
    watch = nil
  end
end

-- Alive again: the corpse is gone, and so is a route to it.
function Death.Back()
  stopWatch()
  planned, released = nil, nil
  local corpse = char().corpse
  if not corpse then
    ns.Arrow.Update()
    return
  end
  if routingBack(corpse) or routingBack(Death.Corpse()) then
    ns.Route.Clear()
  end
  char().corpse = nil
  layerChanged()
  ns.Arrow.Update() -- a route the death had silenced points again
end

-- Plans the way to the corpse, on foot (a ghost cannot fly or hearth); false when there is none.
function Death.RouteBack()
  local d = Death.Corpse()
  if not d then
    B:Say(L["No corpse to go back to."])
    return false
  end
  return ns.Route.ToPoint(d.continent, d.wx, d.wy, L["your corpse"], { onFoot = true })
end

-- Whether the active route is one the death made wrong (the arrow kept
-- the last route and the ghost ran the wrong way): dead or a ghost, the way back wanted and not
-- set yet. Once it was set, a route the ghost chooses afterwards is the ghost's own.
function Death.Silenced()
  if not mod or mod.db.profile.corpseRoute == false or B.Compat.GetDeathState() == "alive" then
    return false
  end
  local d = char().corpse
  return not (d and d.routed) and not routingBack(Death.Corpse())
end

-- The one place that decides, from what the character is now, not from which event came: the
-- order of PLAYER_DEAD, PLAYER_ALIVE and the ghost flag is not measured on Forever, and the tests'
-- tidy order hid the failure. Called by those events, a loading screen, the route's ticker and,
-- while dead, the watch.
function Death.Sync()
  if not (mod and mod:IsEnabled()) then
    return
  end
  local state = B.Compat.GetDeathState()
  if state == "alive" then
    if char().corpse or watch then
      Death.Back()
    end
    return
  end
  if not watch then -- no event says "released" for certain: a look a second, only while dead
    watch = C_Timer.NewTicker(Death.WATCH, Death.Sync)
  end
  local corpse = Death.Corpse()
  if corpse and not char().corpse then -- PLAYER_DEAD was missed, the client knows the place
    remember({ continent = corpse.continent, wx = corpse.wx, wy = corpse.wy, at = time() })
  end
  ns.Arrow.Update()
  local d = char().corpse
  if state ~= "ghost" or not d or mod.db.profile.corpseRoute == false then
    return
  end
  if d.routed then
    stopWatch() -- the way back stood once; what the ghost does now is the ghost's
    return
  end
  if routingBack(corpse) or routingBack(d) then
    d.routed = true
    stopWatch()
    ns.Arrow.Update()
    return
  end
  local now = GetTime()
  released = released or now
  if now - released < Death.SETTLE * 0.9 then -- the watch's tick lands on the second, give or take
    return
  end
  if planned and (now - planned.at < Death.PLAN_WAIT or planned.tries >= Death.ATTEMPTS) then
    if planned.tries >= Death.ATTEMPTS and now - planned.at >= Death.PLAN_WAIT then
      stopWatch() -- no way found: the arrow stays silent, /broute corpse tries again
    end
    return
  end
  planned = { at = now, tries = (planned and planned.tries or 0) + 1 }
  Death.RouteBack()
end

-- PLAYER_ALIVE: released, or brought back to life.
function Death.OnAlive()
  Death.Sync()
end

-- A login or loading screen: alive, the corpse of an earlier session is gone; a ghost still has
-- the way back to go.
function Death.OnEnteringWorld()
  Death.Sync()
end

-- /broute death: what the suite sees, for a report from the game.
function Death.Report()
  local d = char().corpse
  local c = Death.Corpse()
  B:Say(
    "death: state %s, remembered %s, client %s, way back set %s, plans %d, watching %s",
    B.Compat.GetDeathState(),
    d and "yes" or "no",
    c and c.exact and "yes" or "no",
    d and d.routed and "yes" or "no",
    planned and planned.tries or 0,
    watch and "yes" or "no"
  )
end

-- "12 min ago" from UTC seconds.
function Death.Ago(at)
  local s = math.max(0, time() - (at or time()))
  if s < 3600 then
    return string.format(L["%d min ago"], math.floor(s / 60))
  elseif s < 86400 then
    return string.format(L["%d h ago"], math.floor(s / 3600))
  end
  return string.format(L["%d days ago"], math.floor(s / 86400))
end

-- The layer: the corpse large, the earlier deaths small, on the view's continent.
function Death.Pins(view)
  local pins = {}
  local corpse = Death.Corpse()
  local icon = B.UI.IconTexture("grave")
  local function pin(d, isCorpse)
    local map = B.Coords.BestMap(d.continent, d.wx, d.wy)
    local label = isCorpse and L["Your corpse"] or L["Died here"]
    pins[#pins + 1] = {
      ref = map and ("zone:" .. map) or nil, -- the card's subject: the zone it lies in
      wx = d.wx,
      wy = d.wy,
      icon = icon,
      label = label,
      priority = isCorpse and 96 or 30,
      size = isCorpse and Death.CORPSE_SIZE or 14,
      color = isCorpse and S.C.waypointLoud or nil, -- the map's loudest mark
      cluster = not isCorpse,
      card = function()
        return {
          title = label,
          lines = { { text = string.format(L["Died %s"], Death.Ago(d.at)), color = "text" } },
          hint = isCorpse and L["Click for the way back"] or L["Click for a route there"],
        }
      end,
      onClick = function()
        if isCorpse then
          Death.RouteBack()
        else
          ns.Route.ToPoint(d.continent, d.wx, d.wy, L["the place of death"])
        end
      end,
    }
  end
  if corpse and corpse.continent == view.continent then
    pin(corpse, true)
  end
  -- the corpse is also the list's first entry (compared by value: saved copies are other tables)
  local current = char().corpse
  for _, d in ipairs(Death.List()) do
    local same = current and d.at == current.at and d.wx == current.wx and d.wy == current.wy
    if not same and d.continent == view.continent then
      pin(d, false)
    end
  end
  return pins
end

-- From Route's OnEnable: the events (under pcall: a client without them loses the feature only),
-- the layer.
function Death.Register(module)
  mod = module
  pcall(mod.RegisterEvent, mod, "PLAYER_DEAD", function()
    Death.OnDead()
    Death.Sync() -- the old route's arrow goes now, not at the release
  end)
  pcall(mod.RegisterEvent, mod, "PLAYER_ALIVE", function()
    Death.OnAlive()
  end)
  pcall(mod.RegisterEvent, mod, "PLAYER_UNGHOST", function()
    Death.Sync()
  end)
  B:RegisterMapLayer(mod, {
    id = "route.deaths",
    icon = "grave", -- the layer bar shows its icon (R27.8)
    label = L["Deaths"],
    tip = L["Where you died: your corpse, and the earlier deaths of this character."],
    defaultOn = true,
    minLevel = 0,
    query = Death.Pins,
  })
  Death.Sync() -- enabled while dead: a /reload as a ghost
end

function Death.Unregister()
  stopWatch()
  planned, released = nil, nil
end

ns.mod.Death = Death -- for the tests and /bastians debug, as mod.Arrow
