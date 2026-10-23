-- The focus on the map (map.md, ADR 0013 D): the context strip at the bottom of the map with the
-- focused entity's name, its status words and the three actions Open, Route and Play (the registered
-- actions browser.open, route.to and quests.voice, whichever exist), the Follow toggle on the toolbar
-- (profile; on, the map flies to the Browser's page on every page change), and Esc clearing the
-- focus. The ring around the focused pin is drawn by Pins.lua. Nothing here runs while the map is
-- hidden.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map

local Focus = {}
ns.Focus = Focus

Focus.STRIP_H = 24
Focus.ACTIONS = { "browser.open", "route.to", "quests.voice" } -- in this order on the strip

local mod, strip, follow

local function db()
  return mod.db.profile
end

-- The strip's content for a ref: the card's name, status (or summary) and the three actions.
function Focus.StripData(ref)
  if not ref then
    return nil
  end
  local card = B.UI.Card(ref, { source = "map" })
  local actions = {}
  for _, id in ipairs(Focus.ACTIONS) do
    for _, a in ipairs(card.actions) do
      if a.id == id then
        actions[#actions + 1] = a
        break
      end
    end
  end
  return { ref = ref, name = card.name, words = card.status or card.summary, actions = actions }
end

local function placeButton(i, a, ref, x)
  local b = strip.buttons[i]
  if not b then
    b = S.button(strip, "", 60, Focus.STRIP_H - 4)
    b:SetScript("OnClick", function(self)
      if self.action then
        B:RunAction(self.action, self.ref, { source = "map", button = "LeftButton" })
      end
    end)
    strip.buttons[i] = b
  end
  b.action, b.ref = a.id, ref
  b.tipText = a.desc or a.label
  b:SetEnabledFlat(a.enabled ~= false) -- greyed when the action cannot run now (Core, 21.10.2026)
  b.label:SetText((a.icon and B.UI.InlineTexture(a.icon, 12) or "") .. a.label)
  local col = a.active and S.C.accent or S.C.text
  b.label:SetTextColor(col[1], col[2], col[3])
  local w = b.label:GetStringWidth() or 0
  if w == 0 then
    w = #a.label * 6 + 16
  end
  b:SetWidth(w + 14)
  b:ClearAllPoints()
  b:SetPoint("RIGHT", strip, "RIGHT", -x, 0)
  b:Show()
  return x + w + 18
end

-- Draws the strip for the focused entity, or hides it.
function Focus.Update()
  if not strip then
    return
  end
  local data = Focus.StripData(B:Focused())
  if not data then
    strip:Hide()
    strip.count = 0
    return
  end
  strip.name:SetText(data.name)
  strip.words:SetText(data.words or "")
  local x = 4
  for i, a in ipairs(data.actions) do
    x = placeButton(i, a, data.ref, x)
  end
  for i = #data.actions + 1, #strip.buttons do
    strip.buttons[i]:Hide()
  end
  strip.count = #data.actions
  strip.words:ClearAllPoints()
  strip.words:SetPoint("LEFT", strip.name, "RIGHT", 8, 0)
  strip.words:SetPoint("RIGHT", strip, "RIGHT", -x, 0)
  strip:Show()
end

-- Esc on the map: clears the focus when there is one (and the key stops there), else the window
-- closes as usual. Returns true when the key was used.
function Focus.Escape()
  if B:Focused() == nil then
    return false
  end
  B:Focus(nil, { source = "map" })
  return true
end

-- The Dock button shows the state (accent while docked).
function Focus.UpdateDock()
  local dock = Map.toolbar and Map.toolbar.dock
  if not dock then
    return
  end
  local on = B.UI.IsDocked()
  local c = on and S.C.accent or S.C.text
  dock.label:SetTextColor(c[1], c[2], c[3])
  S.setEdges(dock.edges, on and S.C.accent or S.C.line, on and 0.8 or nil)
end

function Focus.IsFollowing()
  return mod ~= nil and db().follow == true
end

function Focus.SetFollow(on)
  db().follow = on and true or false
  if follow then
    local c = db().follow and S.C.accent or S.C.text
    follow.label:SetTextColor(c[1], c[2], c[3])
    S.setEdges(follow.edges, db().follow and S.C.accent or S.C.line, db().follow and 0.8 or nil)
  end
end

-- The Browser shows a page: with Follow on and the map open, fly to its first place.
local function onPageShown(_, _, ref)
  if not (Focus.IsFollowing() and Map.IsShown()) then
    return
  end
  local continent, wx, wy, map, x, y = ns.Waypoints.FirstLocation(ref)
  if not continent then
    return
  end
  Map.Fly(continent, wx, wy, math.max(Map.Camera().level, ns.Waypoints.SHOW_LEVEL))
  ns.Waypoints.Set(continent, wx, wy, B:Entity(ref):Name(), map, x, y)
end

table.insert(Map.onBuild, function(clip)
  strip = CreateFrame("Frame", nil, clip:GetParent())
  strip:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, 0)
  strip:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
  strip:SetHeight(Focus.STRIP_H)
  strip:SetFrameLevel((clip:GetFrameLevel() or 1) + 20)
  S.panel(strip, S.C.panel)
  strip.name = S.text(strip, 13, S.C.accent)
  strip.name:SetPoint("LEFT", strip, "LEFT", 8, 0)
  strip.words = S.text(strip, 11, S.C.dim)
  strip.words:SetJustifyH("LEFT")
  strip.words:SetWordWrap(false)
  strip.buttons = {}
  strip.count = 0
  strip:Hide()
  Map.strip = strip

  follow = S.button(Map.toolbar, L["Follow"], 54, 22)
  follow.tip = function()
    return L["Follow"], L["While on, the map flies to what you open or focus in the other windows."]
  end
  follow:SetPoint("RIGHT", Map.toolbar.layers, "LEFT", -6, 0)
  follow:SetScript("OnClick", function()
    Focus.SetFollow(not db().follow)
  end)
  Map.toolbar.follow = follow
  local dock = S.button(Map.toolbar, L["Dock"], 46, 22) -- the Browser beside the map (ADR 0013 E)
  dock.tip = function()
    return L["Dock the Browser"],
      L["Opens the Browser beside the map at its height; both move together. Click again to undock."]
  end
  dock:SetPoint("RIGHT", follow, "LEFT", -6, 0)
  dock:SetScript("OnClick", function()
    B.UI.ToggleDock()
    Focus.UpdateDock()
  end)
  Map.toolbar.dock = dock
  Focus.UpdateDock()
  Focus.SetFollow(db().follow)
  Focus.Update()
end)

table.insert(Map.onFocus, Focus.Update)
table.insert(Map.onEnable, function(self)
  mod = self
  self:On("BASTIANS_ACTION_STATE", function()
    Focus.Update() -- Play turns into Stop and back
  end)
  self:On("BASTIANS_QUESTS_CHANGED", function(me)
    me:Coalesce("strip", 0.1, Focus.Update) -- the status words follow the log
  end)
  self:On("BASTIANS_PAGE_SHOWN", onPageShown)
end)
ns.mod.Focus = Focus
