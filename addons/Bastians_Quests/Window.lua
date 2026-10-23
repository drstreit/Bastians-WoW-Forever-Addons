-- The Quests views and pages (quests.md, ADR 0012, ADR 0013): My quests (the log), All quests and
-- Attunements as views of the one window (the Browser hosts them, core-contracts §7b); the zone page
-- (Zone and Here of old) and the chain live on entity pages as detail sections (Registrations.lua);
-- the secure quest-item bar of the log view; and a fallback host (this addon's own window) that shows
-- the same views and pages in a game without the Browser. Views talk only to the host they are
-- given; rebuilds are coalesced by the host.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Widgets = B.UI.Widgets
local State, V, R = ns.State, ns.Views, ns.Rows

local W = {}
ns.Window = W

-- { key, title }: the view id is "quests." .. key
local VIEWS = {
  { "log", "My quests" },
  { "all", "All quests" },
  { "attune", "Attunements" },
}
W.VIEWS = VIEWS
W.REFRESH = "BASTIANS_QUESTS_VIEWS" -- Quests' own re-render message (bags, factions, Spoken)
local ITEM_BUTTONS = 8
local RENDER_DELAY = 0.05

local mod
local itemBar -- the secure quest-item bar of the log view
local barHost -- the host the bar sits next to, while the log view is shown

local function db()
  return mod.db.profile
end

local function data()
  return B:GetService("data")
end

local function viewID(key)
  return "quests." .. key
end

-- The player's map and position on it (map fractions); nil in instances without a map.
local function playerPlace()
  local _, _, _, map, x, y = B.Coords.Player()
  return map, x, y
end
W.PlayerPlace = playerPlace

-- The map a view shows: the one chosen in its args, else the player's.
local function currentMap(args)
  return (args and args.map) or (playerPlace())
end

-- The player's position on `map` (map fractions) when the player is on it, else nil.
local function playerOn(map)
  local pm, x, y = playerPlace()
  if map and map == pm then
    return x, y
  end
  return nil, nil
end
W.PlayerOn = playerOn

-- ---------------------------------------------------------------------------------------------
-- Quest text and quest item sources for the log view
-- ---------------------------------------------------------------------------------------------

local function questTextOf(qid)
  local d = data()
  local rec = d and d:Get("questText", qid)
  if rec then
    return rec.details, rec.objectives
  end
  return B.Compat.GetQuestText(qid)
end

local function questItemOf(entry)
  local item = B.Compat.GetQuestItem(entry.index)
  if item and item.inBags then
    return item
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- The secure quest-item bar (SecureActionButtonTemplate, type "item"). The host's tree must not
-- hold secure buttons (ADR 0012), so the log view shows the usable quest items of the log in a
-- strip of its own next to the host window. Created, filled, moved and hidden out of combat only
-- (CLAUDE.md golden rule 6): in combat the wish is kept and PLAYER_REGEN_ENABLED carries it out. It is
-- placed by screen coordinates, never anchored to the host, so the host stays free to move and hide.
-- ---------------------------------------------------------------------------------------------

local pendingItems, pendingHide

local function makeItemBar()
  if itemBar or InCombatLockdown() then
    return itemBar
  end
  itemBar = CreateFrame("Frame", "BastiansQuestsItemBar", UIParent)
  itemBar:SetSize(30, 30)
  itemBar:SetFrameStrata("FULLSCREEN_DIALOG")
  S.panel(itemBar, S.C.panel)
  itemBar:Hide()
  itemBar.buttons = {}
  local down = C_CVar.GetCVarBool("ActionButtonUseKeyDown")
  for i = 1, ITEM_BUTTONS do
    local b = CreateFrame("Button", "BastiansQuestsItem" .. i, itemBar, "SecureActionButtonTemplate")
    b:SetSize(26, 26)
    b:SetPoint("TOP", itemBar, "TOP", 0, -2 - (i - 1) * 28)
    b:RegisterForClicks(down and "AnyDown" or "AnyUp")
    b:SetAttribute("type", "item")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.edges = S.border(b, S.C.accent)
    b:SetScript("OnEnter", function(self)
      if not (GameTooltip and self.itemID) then
        return
      end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(self.itemID)
      end
      if self.title then
        S.TipLine(GameTooltip, self.title, "tipGold")
      end
      S.TipLine(GameTooltip, L["Click: use the quest item"], "tipDim")
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)
    b:Hide()
    itemBar.buttons[i] = b
  end
  W.itemBar = itemBar
  return itemBar
end

-- items = { { itemID, icon, title } } of the log view or the Here column; nil hides the bar.
-- `host` (C4) names the frame the bar sits next to from now on.
function W.SetItemBar(items, host)
  if host then
    barHost = host
  end
  pendingItems, pendingHide = items, items == nil
  if InCombatLockdown() then
    W.combatLocked = true
    return
  end
  W.combatLocked = false
  if items == nil then
    if itemBar then
      itemBar:Hide()
    end
    return
  end
  local bar = makeItemBar()
  if not bar then
    return
  end
  local n = 0
  for i, b in ipairs(bar.buttons) do
    local it = items[i]
    if it then
      n = i
      if b.itemID ~= it.itemID then
        b:SetAttribute("item", "item:" .. it.itemID)
        b.itemID = it.itemID
        b.icon:SetTexture(it.icon or C_Item.GetItemIconByID(it.itemID) or 134400)
      end
      b.title = it.title
      b:Show()
    else
      b.itemID = nil
      b:Hide()
    end
  end
  if n == 0 then
    bar:Hide()
    return
  end
  local frame = barHost and barHost.frame
  local right, top = frame and frame:GetRight(), frame and frame:GetTop()
  bar:SetHeight(4 + n * 28)
  bar:ClearAllPoints()
  if right and top then
    bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + 2, top - 60)
  else
    bar:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0) -- the host did not say where it is
  end
  bar:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The views: each renders into the host it is given (core-contracts §7b)
-- ---------------------------------------------------------------------------------------------

-- The usable quest items of the log view's rows, for the item bar.
local function itemsOf(rows)
  local out, seen = {}, {}
  local function walk(list)
    for _, row in ipairs(list or {}) do
      if row.useItem and not seen[row.useItem] then
        seen[row.useItem] = true
        out[#out + 1] = { itemID = row.useItem, icon = row.itemIcon, title = row.itemTitle or row.title }
      end
      walk(row.children)
    end
  end
  walk(rows)
  return out
end

W.ItemsOf = itemsOf -- the Here column's "My quests here" section feeds the bar the same way (C4)
W.QuestItemOf = questItemOf

-- The tracker's filters: profile flags the log view's toolbar and the
-- settings hub toggle; "My quests here" in the Here column honours them too. Returns an opts
-- table for Views.active with the filters set.
function W.LogFilters()
  local p = db()
  return { hideDone = p.logHideDone == true, trackedOnly = p.logTrackedOnly == true }
end

-- A toolbar toggle of the log view: accented while on, a click flips the profile flag.
local function logToggle(host, key, label, width, tip)
  local p = db()
  local on = p[key] == true
  return {
    id = key,
    kind = "button",
    align = "right",
    width = width,
    label = (on and R.accent() or R.COLOR.grey) .. label .. "|r",
    tooltip = tip,
    onClick = function()
      p[key] = p[key] ~= true
      host:Render()
    end,
  }
end

-- My quests: the log sorted by what to do on the player's map, with the item bar.
local function renderLog(host, args)
  local map = currentMap(args)
  local name = map and R.zoneName(map) or L["Unknown zone"]
  host:SetControls({
    { id = "zone", kind = "label", text = name },
    logToggle(host, "logHideDone", L["Hide done"], 66, L["Hide the complete quests (ready to hand in)."]),
    logToggle(host, "logTrackedOnly", L["Tracked"], 56, L["Show only the quests on the objective tracker."]),
  })
  local px, py = playerOn(map)
  local opts = W.LogFilters()
  opts.questText, opts.questItem = questTextOf, questItemOf
  local rows, s = V.active(map, px, py, opts)
  host:SetRows(rows)
  host:SetSummary(V.activeSummary(s))
  W.SetItemBar(itemsOf(rows))
end

local function renderAll(host)
  local kinds, bands = {}, {}
  for _, k in ipairs(V.KINDS) do
    kinds[#kinds + 1] = { key = k, label = k == "any" and L["Any type"] or L[k] }
  end
  for _, b in ipairs(V.BANDS) do
    bands[#bands + 1] = { key = b, label = b == "any" and L["Any level"] or b }
  end
  host:SetControls({
    {
      id = "kind",
      kind = "select",
      value = db().allKind or "any",
      options = kinds,
      onChange = function(key)
        db().allKind = key
        host:Render()
      end,
    },
    {
      id = "band",
      kind = "select",
      value = db().allBand or "any",
      options = bands,
      onChange = function(key)
        db().allBand = key
        host:Render()
      end,
    },
    {
      id = "texts",
      kind = "button",
      align = "right",
      label = L["load texts"],
      onClick = function()
        local d = data()
        if d then
          d:LoadPack("text")
        end
      end,
    },
  })
  local state = State.ForLogic()
  local filter = { status = db().allStatus, kind = db().allKind, band = db().allBand }
  local d = data()
  local textOf
  if d and d:PackLoaded("text") then
    textOf = function(qid)
      local rec = d:Get("questText", qid)
      return rec and rec.details or nil
    end
  end
  host:SetSummary(L["Building the list ..."])
  host:SetChips({}, nil, nil)
  host:SetRows({ R.note("note:building", L["Building the list ..."]) })
  local rows, counts
  host:Job("quests-all", function(yield)
    local shown
    rows, counts, shown = V.all(state, filter, yield, textOf)
    counts.shown = shown
  end, function()
    W.allRows, W.allCounts = rows, counts
    local text = tostring(counts.shown or 0) .. " " .. L["quests shown"]
    if not (d and d:PackLoaded("text")) then
      text = text .. "  " .. R.COLOR.grey .. L["(titles only; load the quest texts to search them)"] .. "|r"
    end
    host:SetSummary(text)
    host:SetChips(V.statusChips(counts), db().allStatus, function(key)
      db().allStatus = key
      host:Render()
    end, L["Status"]) -- one pill of the filter bar (ADR 0016)
    host:SetRows(rows)
  end)
end

-- Straight-line yards between two map points through the world transforms; nil when unknown.
local function distanceYards(m1, x1, y1, m2, x2, y2)
  local c1, wx1, wy1 = B.Coords.ToWorld(m1, x1, y1)
  local c2, wx2, wy2 = B.Coords.ToWorld(m2, x2, y2)
  if not (c1 and c2) or c1 ~= c2 then
    return nil
  end
  return math.sqrt((wx1 - wx2) ^ 2 + (wy1 - wy2) ^ 2)
end

-- Seconds through the travel service (Route) when it is enabled; nil otherwise.
local function travelSeconds(m1, x1, y1, m2, x2, y2)
  local travel = B:GetService("travel")
  if not travel then
    return nil
  end
  local c1, wx1, wy1 = B.Coords.ToWorld(m1, x1, y1)
  local c2, wx2, wy2 = B.Coords.ToWorld(m2, x2, y2)
  if not (c1 and c2) then
    return nil
  end
  return (travel:Estimate({ c1, wx1, wy1 }, { c2, wx2, wy2 }))
end

local function priceOf(itemID)
  local prices = B:GetService("prices")
  local p = prices and prices:Price(itemID) or nil
  return p and p.median or nil
end

-- The scoring context from the settings and the services (Recommend.rank).
function W.RecommendContext(map)
  local px, py = playerOn(map)
  local p = db()
  return {
    px = px,
    py = py,
    log = State.log,
    hidden = State.hidden, -- the quests hidden from Do here (R3): left out of the ranking rows
    grouped = B.Compat.IsInGroup(),
    weights = { gold = p.weightGold, unlock = p.weightUnlock, next = p.weightNext },
    objectiveTime = {
      slay = p.timeSlay,
      loot = p.timeLoot,
      object = p.timeObject,
      event = p.timeEvent,
      delivery = p.timeDelivery,
    },
    distance = distanceYards,
    travel = travelSeconds,
    price = priceOf,
  }
end

local function renderAttune(host)
  host:SetControls({})
  local state = State.ForLogic()
  local rows, s = V.attunements(state, State.facts.faction, {
    hasItem = function(id)
      return B.Compat.GetItemCount(id) > 0
    end,
    rep = B.Compat.GetReputation,
  })
  host:SetRows(rows)
  host:SetSummary(V.attunementSummary(s))
end

local RENDER = {
  log = renderLog,
  all = renderAll,
  attune = renderAttune,
}

-- ---------------------------------------------------------------------------------------------
-- The fallback host: this addon's own window, used when no other host (the Browser) provides the
-- `views` service. It shows the Quests views and, as plain rows, any entity page (ADR 0013: the
-- zone page and the quest page are the player's way in).
-- ---------------------------------------------------------------------------------------------

local win, tree, bar, search, summary
local dossier -- the page renderer (Bastians.UI.Dossier, C2), in the tree's place while a page shows
local shown -- { id, args } of the view, or { page = ref } of the page, in the fallback window
local fallbackJob

local function fallbackHost(entry)
  local def = B:GetView(entry.id)
  local host = { args = entry.args, frame = win and win.frame, id = entry.id }
  function host.SetRows(_, rows)
    tree:SetRows(rows or {})
  end
  function host.SetSummary(_, text)
    summary:SetText(text or "")
  end
  function host.SetChips(_, chips, active, onChip, title)
    tree:SetChips(chips or {}, active, onChip, nil, title)
  end
  function host.SetControls(_, controls)
    bar:SetControls(controls)
  end
  function host.Job(_, name, fn, onDone)
    if fallbackJob then
      fallbackJob:Cancel()
    end
    fallbackJob = B.Jobs:Run(def and def.owner or mod, name, fn, {
      onDone = function(job)
        if job.cancelled or shown ~= entry then
          return
        end
        fallbackJob = nil
        if onDone then
          onDone()
        end
      end,
    })
    return fallbackJob
  end
  function host.Render()
    W.Render() -- a click (a chip, a zone, a filter) shows at once; events coalesce through W.Schedule
  end
  function host.IsShown()
    return win ~= nil and win:IsShown() and shown == entry
  end
  return host
end

local function leaveFallback()
  if fallbackJob then
    fallbackJob:Cancel()
    fallbackJob = nil
  end
  if W.shownView then
    local id = W.shownView
    W.shownView = nil
    B:ViewEvent(id, "hide")
  end
end

local function build()
  win = B.UI.Window("BastiansQuestsFrame", {
    title = L["Quests"],
    width = 560,
    height = 580,
    minWidth = 550,
    db = db().window,
    onShow = function()
      W.Render()
    end,
    onHide = function()
      leaveFallback()
    end,
    onResize = function()
      if tree then
        tree:Refresh()
      end
      if dossier then
        dossier:Refresh()
      end
    end,
  })
  local content = win.content
  bar = Widgets.ControlBar(content)
  bar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
  bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -6)

  search = S.search(content, L["Search quests ..."])
  search:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -32)
  search:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -32)
  search:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    if text == "" then
      self.hint:Show()
      self.clear:Hide()
    else
      self.hint:Hide()
      self.clear:Show()
    end
    if shown and shown.page and dossier then
      dossier:SetQuery(text)
    elseif tree then
      tree:SetQuery(text)
    end
  end)

  summary = S.text(content, 11, S.C.dim)
  summary:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -58)
  summary:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -58)
  summary:SetHeight(14)

  tree = B.UI.Tree(content, {
    db = db().tree,
    ctx = { source = "quests" },
    onClick = function(row, button)
      if row.onClick and button ~= "RightButton" then
        row.onClick(row, button)
      elseif row.ref and button == "RightButton" then
        B.UI.EntityMenu(row.ref, nil, { source = "quests" })
      elseif row.group and row.hasChildren then
        tree:ToggleFold(row) -- a zone group folds on click
      elseif row.ref then
        B:ShowPage(row.ref) -- every ref in a row leads to its page, as in the Browser
      elseif row.hasChildren then
        tree:ToggleFold(row)
      end
    end,
  })
  tree.chips:ClearAllPoints()
  tree.chips:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -76)
  tree.chips:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, -76)
  tree.scroll:ClearAllPoints()
  tree.scroll:SetPoint("TOPLEFT", tree.chips, "BOTTOMLEFT", 0, -2)
  tree.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 6)

  -- the page renderer (C2): the same dossier the Browser draws, in the tree's place on a page
  dossier = B.UI.Dossier(content, {
    ctx = { source = "quests" },
    onClick = function(row, button)
      if row.onClick and button ~= "RightButton" then
        row.onClick(row, button)
      elseif row.ref and button == "RightButton" then
        B.UI.EntityMenu(row.ref, nil, { source = "quests" })
      elseif row.ref then
        B:ShowPage(row.ref)
      end
    end,
  })
  dossier.frame:ClearAllPoints()
  dossier.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -76)
  dossier.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 6)
  dossier:Hide()
  W.win, W.tree, W.bar, W.search, W.summary, W.dossier = win, tree, bar, search, summary, dossier
end

-- The tree (views) and the dossier (pages) share the space under the search box; one shows.
local function showTree(on)
  if on then
    dossier:Hide()
    tree.chips:Show()
    tree.scroll:Show()
    tree.bar:Show()
  else
    tree.chips:Hide()
    tree.scroll:Hide()
    tree.bar:Hide()
    dossier:Show()
  end
end

-- Render what the fallback window shows now (the hot path is the coalesced W.Schedule).
function W.Render()
  if not (win and win:IsShown() and shown) then
    return
  end
  if shown.page then
    leaveFallback()
    local e = B:Entity(shown.page)
    win:SetTitle(e:Name() or shown.page)
    bar:SetControls({})
    showTree(false)
    local sections = B:GetDetailSections(shown.page)
    dossier:SetSubject(shown.page, sections, { source = "quests" })
    if e:Name() == nil and #sections == 0 then
      summary:SetText(L["No data for this entity. Is Bastian's Data installed and loaded?"])
    else
      summary:SetText("")
    end
    return
  end
  showTree(true)
  local def = B:GetView(shown.id)
  win:SetTitle(def and tostring(def.title) or L["Quests"])
  local host = fallbackHost(shown)
  if W.shownView ~= shown.id then
    leaveFallback()
    W.shownView = shown.id
    B:ViewEvent(shown.id, "show", host)
  end
  tree:SetChips({}, nil, nil)
  B:RenderView(shown.id, host)
end

local function fallbackOpen(entry)
  if not win then
    build()
  end
  shown = entry
  if win:IsShown() then
    W.Render()
  else
    win:Show() -- onShow renders
  end
  return true
end

-- Shows a view in the fallback window (the `views` service at priority 10).
local function fallbackShow(id, args)
  if not (mod and mod:IsEnabled() and B:GetView(id)) then
    return false
  end
  return fallbackOpen({ id = id, args = args or {} })
end

-- Shows an entity page in the fallback window.
local function fallbackPage(ref)
  if not (mod and mod:IsEnabled() and B.Entity.Parse(ref)) then
    return false
  end
  return fallbackOpen({ page = ref })
end

-- ---------------------------------------------------------------------------------------------
-- The facade the rest of the addon uses
-- ---------------------------------------------------------------------------------------------

-- The zone page of a map (the player's without one): the way in since ADR 0013. Since C4 a host
-- with a Here column (the Browser: `Open`) is opened as it is, the Here column is the zone.
function W.OpenZone(map, page)
  local host = B:GetService("views")
  if map == nil and not page and host and host.Open then
    return host:Open()
  end
  map = map or playerPlace()
  if not map then
    B:Say(L["No zone: the map position is unknown here."])
    return false
  end
  return B:ShowPage("zone:" .. map)
end

-- Open: "zone" | "here" (arg = map or nil: the zone page), "log" (the view), "all", "attune", a
-- quest id (its page); nil opens the player's zone page. Goes to the active host: the Browser,
-- else the fallback window.
function W.Open(which, arg)
  if not (mod and mod:IsEnabled()) then
    return false
  end
  if which == nil then
    return W.OpenZone(arg) -- the window with the Here column (C4), the zone page without one
  elseif which == "slim" then -- the Here column alone as the tracker (C8), where the host has it
    local host = B:GetService("views")
    if host and host.Slim then
      return host:Slim(arg)
    end
    B:Say(L["Slim mode needs Bastian's Browser."])
    return false
  elseif which == "zone" or which == "here" then
    return W.OpenZone(arg, true) -- the zone page as the subject, said so
  elseif which == "active" then
    which = "log"
  end
  if tonumber(which) then
    return B:ShowPage("quest:" .. tonumber(which))
  end
  if not B:GetView(viewID(which)) then
    return false
  end
  return B:ShowView(viewID(which), {})
end

-- The Quests view shown by the active host, or nil.
local function shownQuestsView()
  local host = B:GetService("views")
  local id = host and host.Current and host:Current() or nil
  if id and string.sub(id, 1, 7) == "quests." then
    return id
  end
  return nil
end

-- True while the active host shows a Quests view or a zone page (what /bq toggles); a host with
-- a Here column (C4) counts as shown whenever its window is.
function W.IsShown()
  if shownQuestsView() then
    return true
  end
  local host = B:GetService("views")
  if host and host.Open then
    return host:IsShown() and true or false
  end
  local page = host and host.CurrentPage and host:CurrentPage() or nil
  return page ~= nil and B.Entity.Parse(page) == "zone"
end

-- The map the log view shows: the player's (args given: that view's).
function W.CurrentMap(args)
  return currentMap(args)
end

function W.Toggle()
  if W.IsShown() then
    W.Hide()
  else
    W.Open()
  end
end

function W.Hide()
  local host = B:GetService("views")
  if W.IsShown() and host and host.Hide then
    host:Hide()
  end
  if win then
    win:Hide()
  end
end

-- The module is switched off: its own window and the item bar go; another host (the Browser) stays
-- open and says the view is not available (ADR 0012: one shared window).
function W.HideOwn()
  if win then
    win:Hide()
  end
  barHost = nil
  W.SetItemBar(nil)
end

-- Coalesced rebuild, used by every event that may change a row: the zone sections forget their
-- rows, the fallback window renders, any other host hears W.REFRESH (every Quests view lists it in
-- invalidateOn, and so do the zone sections).
function W.Schedule()
  if not mod then
    return
  end
  if ns.Registrations and ns.Registrations.InvalidateZone then
    ns.Registrations.InvalidateZone()
  end
  if ns.Tracker then
    ns.Tracker.Schedule() -- the tracker frame follows the same changes (R6)
  end
  if win and win:IsShown() then
    mod:Coalesce("render", RENDER_DELAY, W.Render)
  end
  if not (win and win:IsShown()) then
    mod:Coalesce("views", RENDER_DELAY, function() -- not "refresh": that key is the log refresh
      mod:Fire(W.REFRESH)
    end)
  end
end

-- Wiring done once per enable: the views, the fallback host, events.
function W.Register(self)
  mod = self -- BASTIANS_QUESTS_CHANGED reaches the host through each view's invalidateOn
  B:DeclareMessage(W.REFRESH)
  for i, t in ipairs(VIEWS) do
    local key = t[1]
    B:RegisterView(self, {
      id = viewID(key),
      title = L[t[2]],
      group = L["Quests"],
      order = i * 10,
      pinned = key == "log" or nil, -- "My quests" is a toolbar button of the host
      render = function(host, args)
        RENDER[key](host, args)
      end,
      summary = key == "log" and function()
        return tostring(State.count or 0) .. " " .. L["in the log"]
      end or nil,
      invalidateOn = {
        "BASTIANS_QUESTS_CHANGED",
        "BASTIANS_TRACKED_CHANGED", -- the "Tracked" filter and the tracked tag of a row
        "BASTIANS_ENTITY_CHANGED",
        "BASTIANS_PLAYER_MOVED_ZONE",
        W.REFRESH,
      },
      onShow = key == "log" and function(host)
        barHost = host
      end or nil,
      onHide = key == "log" and function()
        barHost = nil
        W.SetItemBar(nil)
      end or nil,
    })
  end
  B:ProvideService(self, "views", {
    Show = function(_, id, args)
      return fallbackShow(id, args)
    end,
    ShowPage = function(_, ref)
      return fallbackPage(ref)
    end,
    IsShown = function(_, id)
      return win ~= nil and win:IsShown() and shown ~= nil and shown.id == id
    end,
    Current = function()
      if win and win:IsShown() and shown and shown.id then
        return shown.id, shown.args
      end
      return nil
    end,
    CurrentPage = function()
      if win and win:IsShown() and shown then
        return shown.page
      end
      return nil
    end,
    Hide = function()
      if win then
        win:Hide()
      end
    end,
  }, { priority = 10 })
  -- the fallback window follows the world like the Browser does through each view's invalidateOn
  self:On("BASTIANS_ENTITY_CHANGED", W.Schedule)
  self:On("BASTIANS_REWARD_INFO_CHANGED", W.Schedule) -- a reward item loaded, gear changed (S7)
  self:On("BASTIANS_PLAYER_MOVED_ZONE", W.Schedule)
  self:On("BASTIANS_TRACKED_CHANGED", W.Schedule)
  self:On("BASTIANS_THEME_CHANGED", function() -- the colour codes of the rows (ST3)
    W.Schedule()
    if ns.Tracker then
      ns.Tracker.Render()
    end
  end)
  self:On("BASTIANS_SETTING_CHANGED", function(_, _, name) -- the hub's tracker toggles
    if name == self.name then
      if ns.Tracker then
        ns.Tracker.Apply() -- the frame, its lock and the game-tracker claim follow the settings
      end
      W.Schedule()
    end
  end)
  self:RegisterEvent("BAG_UPDATE_DELAYED", function()
    W.Schedule() -- quest items appear and vanish with the bags, not with the log
  end)
  self:RegisterEvent("UPDATE_FACTION", W.Schedule)
  self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if W.combatLocked then
      if pendingHide then
        W.SetItemBar(nil)
      else
        W.SetItemBar(pendingItems)
      end
    end
  end)
end

-- Key binding name (the binding system reads this global; see Bindings.xml)
BINDING_NAME_BASTIANS_QUESTS = L["Open Bastian's Quests"]

SLASH_BASTIANSQUESTS1 = "/bq"
SlashCmdList.BASTIANSQUESTS = function(msg)
  msg = string.lower(strtrim(msg or ""))
  if msg == "" then
    W.Toggle()
  elseif msg == "tracker" then
    ns.Tracker.Toggle() -- the log view in its own frame, on or off (R6)
  elseif msg == "journey" then
    ns.Journey.Print() -- this session's XP, gold, kills and quests per zone (S3)
  elseif
    msg == "here"
    or msg == "zone"
    or msg == "log"
    or msg == "active"
    or msg == "all"
    or msg == "attune"
    or msg == "slim"
  then
    W.Open(msg)
  elseif tonumber(msg) then
    W.Open(tonumber(msg))
  else
    B:Say(L["Usage: /bq [here | log | all | attune | slim | tracker | journey | <questID>]"])
  end
end
