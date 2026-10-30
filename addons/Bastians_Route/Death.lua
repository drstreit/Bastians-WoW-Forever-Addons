-- Bastian's Route: the place of death (route.md "The place of death", R26.8): remembers where the
-- character died, plans the way back to the corpse once released as a ghost, and shows the corpse
-- and the earlier deaths as the map layer `route.deaths`.
local _, ns = ...
local B = Bastians
local L = ns.L

local Death = {}
ns.Death = Death

Death.MAX = 10 -- earlier deaths kept per character
Death.SETTLE = 1 -- seconds after the release before planning (the graveyard's position settles)
Death.SAME_YARDS = 5 -- a route whose goal lies this close to the corpse is the way back

local mod

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
-- The client's corpse position when it answers (exact), else the remembered place.
function Death.Corpse()
  local d = char().corpse
  if not d then
    return nil
  end
  local map, x, y = B.Compat.GetCorpsePosition()
  if map then
    local c, wx, wy = B.Coords.ToWorld(map, x, y)
    if c then
      return { continent = c, wx = wx, wy = wy, at = d.at, exact = true }
    end
  end
  return d
end

local function layerChanged()
  B:Fire("BASTIANS_LAYER_CHANGED", "route.deaths")
end

-- PLAYER_DEAD: the place, unless in an instance (no map position there).
function Death.OnDead()
  local c, wx, wy = B.Coords.Player()
  if not c then
    return nil
  end
  local d = { continent = c, wx = wx, wy = wy, at = time() }
  char().corpse = d
  local list = Death.List()
  table.insert(list, 1, d)
  for i = #list, Death.MAX + 1, -1 do
    list[i] = nil
  end
  layerChanged()
  return d
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

-- Alive again: the corpse is gone, and so is a route to it.
function Death.Back()
  local corpse = char().corpse
  if not corpse then
    return
  end
  if routingBack(corpse) or routingBack(Death.Corpse()) then
    ns.Route.Clear()
  end
  char().corpse = nil
  layerChanged()
end

-- Plans the way to the corpse; false when there is none.
function Death.RouteBack()
  local d = Death.Corpse()
  if not d then
    B:Say(L["No corpse to go back to."])
    return false
  end
  return ns.Route.ToPoint(d.continent, d.wx, d.wy, L["your corpse"])
end

-- PLAYER_ALIVE: released (a ghost: the way back, unless switched off) or brought back to life.
function Death.OnAlive()
  local state = B.Compat.GetDeathState()
  if state == "ghost" then
    if char().corpse and mod.db.profile.corpseRoute ~= false then
      C_Timer.After(Death.SETTLE, function()
        if mod:IsEnabled() and B.Compat.GetDeathState() == "ghost" then
          Death.RouteBack()
        end
      end)
    end
  elseif state == "alive" then
    Death.Back()
  end
end

-- A login or loading screen: alive means the corpse of an earlier session is gone.
function Death.OnEnteringWorld()
  if char().corpse and B.Compat.GetDeathState() == "alive" then
    Death.Back()
  end
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
      size = isCorpse and 26 or 14,
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
  end)
  pcall(mod.RegisterEvent, mod, "PLAYER_ALIVE", function()
    Death.OnAlive()
  end)
  pcall(mod.RegisterEvent, mod, "PLAYER_UNGHOST", function()
    Death.Back()
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
end

ns.mod.Death = Death -- for the tests and /bastians debug, as mod.Arrow
