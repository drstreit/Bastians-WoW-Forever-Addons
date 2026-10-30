-- The Route window (route.md "Step list"): the active route as numbered steps with per-step and total
-- time, a line per step to click (the step's end as an entity), Clear and Replan buttons, and the
-- notes (approx legs, hearth state). One window over the shared tree; rebuilds are coalesced.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Graph = ns.Graph

local W = {}
ns.Window = W

local RENDER_DELAY = 0.05

local mod, win, tree, summary, hint, clearButton, replanButton, homeButton
local kindButtons = {} -- kind -> button (R26.5)
local KIND_LABELS = { fastest = "Fastest", safe = "Safest", nocost = "No flights" }

local function db()
  return mod.db.profile
end

local function stepRows(route)
  local rows = {}
  local approx = false
  for i, step in ipairs(route.steps) do
    approx = approx or step.approx
    local text = string.format("%d. %s", i, Graph.StepText(step, L))
    -- creatures well above the character along a walk (R26.5)
    local facts = B.Compat.GetPlayerFacts() or {}
    if step.danger and facts.level and step.danger >= facts.level + ns.Route.CAREFUL_LEVELS then
      local words = string.format(L["Careful: level %d creatures"], step.danger)
      if step.elite then
        words = words .. ", " .. L["elite"]
      end
      text = text .. "  " .. S.H.warn .. words .. "|r"
    end
    local leaves = step.from and ns.Ferries.NextDeparture(step.from.transport, step.from.stop)
    if leaves and i >= (route.index or 1) then -- the loop is known (R26.6): when it leaves, live
      text = text
        .. "  "
        .. S.H.accent
        .. string.format(L["leaves in %s"], Graph.FormatSeconds(leaves))
        .. "|r"
    elseif step.wait and step.wait > 0 then
      text = text
        .. "  "
        .. S.H.muted
        .. string.format(L["wait up to %s"], Graph.FormatSeconds(step.wait * 2))
        .. "|r"
    end
    rows[#rows + 1] = {
      id = "step:" .. i,
      ref = step.to.ref,
      text = (i < (route.index or 1)) and (S.H.muted .. text .. "|r") or text,
      value = Graph.FormatSeconds(step.seconds),
      -- a click shows the step's end, that point (a boat's two ends fitted
      -- the map to the world); the entity's own places stay for the menu
      onClick = function(_, button)
        if button == "RightButton" then
          B.UI.EntityMenu(step.to.ref, nil, { source = "route" })
        elseif step.to.continent and step.to.wx then
          B:RunAction("map.show", step.to.ref, {
            source = "route",
            point = { step.to.continent, step.to.wx, step.to.wy, Graph.StepText(step, L) },
          })
        end
      end,
      tooltip = function(tt)
        tt:AddLine(Graph.StepText(step, L), 1, 1, 1)
        tt:AddLine(string.format("%s %s", L["Time"], Graph.FormatSeconds(step.seconds)), 0.8, 0.8, 0.8)
        if step.yards then
          tt:AddLine(
            string.format("%s %d %s", L["Distance"], math.floor(step.yards + 0.5), L["yd"]),
            0.8,
            0.8,
            0.8
          )
        end
        if step.approx then
          S.TipLine(tt, L["Estimate: a straight line or an unmeasured ride."], "tipDim", true)
        end
      end,
    }
  end
  if approx then
    rows[#rows + 1] = {
      kind = "para",
      text = S.H.muted
        .. L["Legs marked approx are straight lines or unmeasured rides; the time is an estimate."]
        .. " "
        .. L["The map draws them dashed: they may cross water until the route graph knows the terrain."]
        .. "|r",
    }
  end
  for _, note in ipairs(route.notes or {}) do
    rows[#rows + 1] = { kind = "para", text = S.H.muted .. note .. "|r" }
  end
  return rows
end

-- The kinds row (R26.5): "Fastest 4 min | Safest 5 min | No flights 9 min", the kind in use
-- accented; a kind still being planned reads "..."; a kind equal to one before it is left out.
function W.RenderKinds(route)
  local alts = route and route.alternatives
  local x = 0
  local shown = {}
  for _, kind in ipairs(ns.Route.KINDS) do
    local b = kindButtons[kind]
    local alt = alts and alts[kind]
    local same = false
    for _, other in ipairs(shown) do
      if alt and math.abs(other.seconds - alt.seconds) < 0.5 and #other.steps == #alt.steps then
        same = true
      end
    end
    if not alts or same then
      b:Hide()
    else
      local time = alt and Graph.FormatSeconds(alt.seconds) or "..."
      b:SetLabel(L[KIND_LABELS[kind]] .. " " .. time)
      local col = route.kind == kind and S.C.accent or S.C.text
      b.label:SetTextColor(col[1], col[2], col[3])
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", win.content, "TOPLEFT", 8 + x, -24)
      b:Show()
      x = x + b:GetWidth() + 4
      if alt then
        shown[#shown + 1] = alt
      end
    end
  end
end

function W.Render()
  if not (win and win:IsShown()) then
    return
  end
  local route = ns.Route.Active()
  W.RenderKinds(route)
  if not route then
    summary:SetText(L["No route. Right click anything with a place and choose Route to."])
    tree:SetRows({})
    clearButton:Hide()
    replanButton:Hide()
    return
  end
  local goal = route.goal and route.goal.name or L["the target"]
  local left = Graph.FormatSeconds(Graph.Remaining(route))
  if route.tour then -- several stops (R26.4)
    summary:SetText(string.format(L["%s: %d stops, %s"], route.tour.name, #route.tour.stops, left))
  else
    summary:SetText(string.format(L["To %s: %s, %d steps"], goal, left, #route.steps))
  end
  tree:SetRows(stepRows(route))
  clearButton:Show()
  replanButton:Show()
end

function W.Schedule()
  if mod and win and win:IsShown() then
    mod:Coalesce("render", RENDER_DELAY, W.Render)
  end
end

local function build()
  win = B.UI.Window("BastiansRouteFrame", {
    module = "Route", -- the options button opens this page (R27.1)
    title = L["Route"],
    width = 440,
    height = 360,
    db = db().window,
    onShow = function()
      W.Render()
    end,
    onResize = function()
      if tree then
        tree:Refresh()
      end
    end,
  })
  local content = win.content
  summary = S.text(content, 11, S.C.text)
  summary:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
  summary:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -8)
  summary:SetHeight(14)
  summary:SetJustifyH("LEFT")
  clearButton = S.button(content, L["Clear"], 70, 20)
  clearButton.tip = L["Clear the route."]
  clearButton:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -8, 4)
  clearButton:SetScript("OnClick", function()
    ns.Route.Clear()
  end)
  replanButton = S.button(content, L["Replan"], 70, 20)
  replanButton.tip = L["Plan the route again from where you stand."]
  replanButton:SetPoint("RIGHT", clearButton, "LEFT", -4, 0)
  replanButton:SetScript("OnClick", function()
    ns.Route.Replan("button")
  end)
  -- Home (R26.7): the way to the inn, with the hearth and every ready teleport
  homeButton = S.button(content, L["Home"], 70, 20)
  homeButton.tip = L["The way to your inn, with the hearthstone and every teleport you have ready."]
  homeButton:SetPoint("RIGHT", replanButton, "LEFT", -4, 0)
  homeButton:SetScript("OnClick", function()
    ns.Route.Home()
  end)
  hint = S.text(content, 10, S.C.dim)
  hint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 8, 6)
  hint:SetText(L["Click a step to see its end on the map."])
  for _, kind in ipairs(ns.Route.KINDS) do
    local b = S.button(content, L[KIND_LABELS[kind]], 112, 18)
    b.tip = L["Switch to this kind of route; it stays the default."]
    b:SetScript("OnClick", function()
      ns.Route.UseKind(kind)
      W.Render()
    end)
    b:Hide()
    kindButtons[kind] = b
  end
  tree = B.UI.Tree(content, { db = db().tree, ctx = { source = "route" } })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -46)
  tree.chips:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, -46)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
  tree.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 28)
  W.win, W.tree, W.summary, W.homeButton, W.kindButtons = win, tree, summary, homeButton, kindButtons
end

function W.Open()
  if not (mod and mod:IsEnabled()) then
    return false
  end
  if not win then
    build()
  end
  if win:IsShown() then
    W.Render()
  else
    win:Show()
  end
  return true
end

function W.Toggle()
  if win and win:IsShown() then
    win:Hide()
  else
    W.Open()
  end
end

function W.Hide()
  if win then
    win:Hide()
  end
end

function W.IsShown()
  return win ~= nil and win:IsShown()
end

function W.Register(self)
  mod = self
  self:On("BASTIANS_ROUTE_CHANGED", function(me, ...)
    ns.Arrow.Update() -- one bus handler per message and module: the arrow follows from here (S6)
    W.Schedule(me, ...)
  end)
  self:On("BASTIANS_THEME_CHANGED", function() -- the arrow's and the steps' colours (ST3)
    ns.Arrow.Update()
    W.Schedule()
  end)
end
