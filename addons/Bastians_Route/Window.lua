-- The Route window (route.md "Step list"): the active route as numbered steps with per-step and total
-- time, a line per step to click (the step's end as an entity), Clear and Replan buttons, and the
-- notes (approx legs, hearth state). One window over the shared tree; rebuilds are coalesced.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets
local Graph = ns.Graph

local W = {}
ns.Window = W

local RENDER_DELAY = 0.05

-- The one look (ADR 0084, W9; route.md "The one look"): the line of what the route is, the
-- kinds as chips in a band, the steps, the row of /way, and a foot with the hint and the tools.
local SIDE, SUM_TOP, SUM_H, SUM_FOOT = 15, 8, 14, 6
local TREE_LEFT, TREE_RIGHT = 6, 20 -- the rows' room beside the fold marks and the scroll bar
local WAY_H, WAY_GAP = 18, 4 -- the row of /way over the foot

local mod, win, tree, summary, hint, clearButton, replanButton, homeButton, band
local wayOwnerButton, wayModeButton -- who answers /way, and what it does (ADR 0062)
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

-- The kinds (R26.5) as chips in a band under the line: "Fastest 4 min", "Safest 5 min", "No
-- flights 9 min", the kind in use filled; a kind still being planned reads "..."; a kind equal to
-- one before it is left out. Without a route there is no band.
function W.RenderKinds(route)
  local alts = route and route.alternatives
  local shown = {}
  band:Begin(win.content:GetWidth())
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
      b.spec.label = L[KIND_LABELS[kind]] .. " " .. time
      b:SetOn(route.kind == kind) -- the look draws the kind in use (ADR 0046)
      band:Place(b, b:GetWidth() or 0, b:GetHeight() or 0)
      b:Show()
      if alt then
        shown[#shown + 1] = alt
      end
    end
  end
  local any = alts ~= nil
  band:End()
  if not any then
    band.frame:SetHeight(1)
  end
  band.ground:SetShown(any)
  band.rule:SetShown(any)
end

-- The row of /way (ADR 0062): "/way: TomTom" only where another addon has the command; what /way
-- does only while Route is the one answering.
function W.RenderWay()
  local Way, x = ns.Way, SIDE
  local name = Way.OwnerName()
  local ours = not name or Way.OverOwner()
  local function place(button)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", win.content, "BOTTOMLEFT", x, Widgets.FOOT_H + WAY_GAP)
    button:Show()
    x = x + button:GetWidth() + 4
  end
  if name then
    wayOwnerButton:SetLabel(string.format(L["/way: %s"], ours and L["Route"] or name))
    place(wayOwnerButton)
  else
    wayOwnerButton:Hide()
  end
  if ours then
    wayModeButton:SetLabel(string.format(L["/way: %s"], db().wayAdd and L["Add to route"] or L["New route"]))
    place(wayModeButton)
  else
    wayModeButton:Hide()
  end
end

function W.Render()
  if not (win and win:IsShown()) then
    return
  end
  local route = ns.Route.Active()
  W.RenderKinds(route)
  W.RenderWay()
  if not route then
    -- two lines: the hint needed 402 units of the window's 398 and was cut (the windows probe,
    -- 24.11.2026); nothing stands under it without a route
    summary:SetWordWrap(true)
    summary:SetHeight(2 * SUM_H + 2)
    summary:SetText(L["No route. Right click anything with a place and choose Route to."])
    tree:SetRows({})
    clearButton:Hide()
    replanButton:Hide()
    hint:SetText("") -- nothing to click: the foot keeps Home alone
    hint:Layout()
    return
  end
  local goal = route.goal and route.goal.name or L["the target"]
  local left = Graph.FormatSeconds(Graph.Remaining(route))
  local text
  if route.tour then -- several stops (R26.4)
    text = string.format(L["%s: %d stops, %s"], route.tour.name, #route.tour.stops, left)
  else
    text = string.format(L["To %s: %s, %d steps"], goal, left, #route.steps)
  end
  -- the verdict (A4.3): one word on the creatures along the way, in its colour
  local words, verdict = Graph.VerdictText(route, (B.Compat.GetPlayerFacts() or {}).level, L)
  if verdict then
    text = text .. "  " .. S.H[Graph.VERDICT_TOKENS[verdict]] .. words .. "|r"
  end
  summary:SetWordWrap(false) -- one line over the kinds' chips
  summary:SetHeight(SUM_H)
  summary:SetText(text)
  tree:SetRows(stepRows(route))
  clearButton:Show()
  replanButton:Show()
  hint:SetText(L["Click a step to see its end on the map."])
  hint:Layout()
end

function W.Schedule()
  if mod and win and win:IsShown() then
    mod:Coalesce("render", RENDER_DELAY, W.Render)
  end
end

local function build()
  win = B.UI.Window("BastiansRouteFrame", {
    bareHead = true, -- a low head that carries nothing (ADR 0084 decision 4)
    module = "Route", -- the options button opens this page (R27.1)
    title = L["Route"],
    width = 440,
    height = 360,
    db = db().window,
    onTop = true, -- over every other window
    onShow = function()
      W.Render()
    end,
    onResize = function()
      if tree then
        W.RenderKinds(ns.Route.Active()) -- the chips wrap at the window's width
        tree:Refresh()
      end
    end,
  })
  local content = win.content
  summary = S.text(content, 13, S.C.text) -- what the route is, in the text size (the board)
  summary:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE, -SUM_TOP)
  summary:SetPoint("TOPRIGHT", content, "TOPRIGHT", -SIDE, -SUM_TOP)
  summary:SetHeight(SUM_H)
  summary:SetJustifyH("LEFT")
  -- the kinds as chips in a band under the line
  band = B.UI.Band(content, { labels = false })
  band.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(SUM_TOP + SUM_H + SUM_FOOT))
  band.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(SUM_TOP + SUM_H + SUM_FOOT))
  for _, kind in ipairs(ns.Route.KINDS) do
    local b = S.pill(band.frame, {
      small = true,
      label = L[KIND_LABELS[kind]],
      tip = L["Switch to this kind of route; it stays the default."],
      onClick = function()
        ns.Route.UseKind(kind)
        W.Render()
      end,
    })
    b:Hide()
    kindButtons[kind] = b
  end
  -- the foot: the hint, and Home, Replan and Clear as tools at its end (the board)
  hint = Widgets.Foot(content)
  -- Home (R26.7): the way to the inn, with the hearth and every ready teleport
  homeButton = hint:Tool({
    label = L["Home"],
    tip = L["The way to your inn, with the hearthstone and every teleport you have ready."],
    onClick = function()
      ns.Route.Home()
    end,
  })
  replanButton = hint:Tool({
    label = L["Replan"],
    tip = L["Plan the route again from where you stand."],
    onClick = function()
      ns.Route.Replan("button")
    end,
  })
  clearButton = hint:Tool({
    label = L["Clear"],
    tip = L["Clear the route."],
    onClick = function()
      ns.Route.Clear()
    end,
  })
  wayOwnerButton = S.action(content, { icon = "arrow", label = "/way", row = true, boxed = true })
  wayOwnerButton.tip = L["Which addon answers /way: Bastian's Route, or the one that had it first."]
  wayOwnerButton:SetScript("OnClick", function()
    ns.Way.SetOverOwner(not ns.Way.OverOwner())
    W.RenderWay()
  end)
  wayModeButton = S.action(content, { icon = "route", label = "/way", row = true, boxed = true })
  wayModeButton.tip =
    L["What /way does while a route runs: start a new route, or add the place to the route."]
  wayModeButton:SetScript("OnClick", function()
    db().wayAdd = not db().wayAdd
    W.RenderWay()
  end)
  tree = B.UI.Tree(content, { db = db().tree, ctx = { source = "route" } })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", band.frame, "BOTTOMLEFT", TREE_LEFT, 0)
  tree.chips:SetPoint("TOPRIGHT", band.frame, "BOTTOMRIGHT", -TREE_RIGHT, 0)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -4)
  -- above the row of /way, which stands over the foot
  tree.scroll:SetPoint("BOTTOMRIGHT", hint, "TOPRIGHT", -TREE_RIGHT, WAY_H + 2 * WAY_GAP)
  W.win, W.tree, W.summary, W.homeButton, W.kindButtons = win, tree, summary, homeButton, kindButtons
  W.band, W.hint, W.clearButton, W.replanButton = band, hint, clearButton, replanButton
  W.wayOwnerButton, W.wayModeButton = wayOwnerButton, wayModeButton
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
