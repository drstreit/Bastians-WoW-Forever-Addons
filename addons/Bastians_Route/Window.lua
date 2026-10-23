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

local mod, win, tree, summary, hint, clearButton, replanButton

local function db()
  return mod.db.profile
end

local function stepRows(route)
  local rows = {}
  local approx = false
  for i, step in ipairs(route.steps) do
    approx = approx or step.approx
    local text = string.format("%d. %s", i, Graph.StepText(step, L))
    if step.wait and step.wait > 0 then
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

function W.Render()
  if not (win and win:IsShown()) then
    return
  end
  local route = ns.Route.Active()
  if not route then
    summary:SetText(L["No route. Right click anything with a place and choose Route to."])
    tree:SetRows({})
    clearButton:Hide()
    replanButton:Hide()
    return
  end
  local goal = route.goal and route.goal.name or L["the target"]
  summary:SetText(
    string.format(L["To %s: %s, %d steps"], goal, Graph.FormatSeconds(route.seconds), #route.steps)
  )
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
  hint = S.text(content, 10, S.C.dim)
  hint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 8, 6)
  hint:SetText(L["Click a step to see its end on the map."])
  tree = B.UI.Tree(content, { db = db().tree, ctx = { source = "route" } })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -26)
  tree.chips:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, -26)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
  tree.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 28)
  W.win, W.tree, W.summary = win, tree, summary
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
