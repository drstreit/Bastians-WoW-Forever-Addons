-- The layer bar: a panel sliding over the top of
-- the map with one toggle icon per registered layer, grouped by app, the map style and the bookmarks
-- each one icon with a menu;
-- a tab with the suite's arrow under it slides it open and shut. A layer whose zoom range the view
-- is outside of shows its pill dimmed. Bookmarks are named when kept and renamed or removed from a
-- right click.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map

local Bar = {}
ns.LayerBar = Bar

Bar.PILL_H, Bar.GAP, Bar.LINE_GAP, Bar.PAD, Bar.EDGE = 24, 4, 4, 8, 6
Bar.ICON = 18 -- the icon inside its square pill
Bar.GROUP_GAP = 12 -- the space between two apps' icons
Bar.BOOKMARKS_MAX = 30
Bar.SLIDE = 0.18 -- seconds the panel takes to slide open or shut

local mod, panel, tab, nameBox, menu
local pills = {} -- pooled pill buttons
local target = 0 -- the panel's full height
local slide -- { from, to, t } while sliding (t: seconds of the slide drawn so far)

local function db()
  return mod.db
end

-- --- bookmarks --------------------------------------------------------------------------------
-- With Bastian's Notes the bookmarks live in its lists (the `notes` service, notes.md N2: the
-- lists the player shows); without it in the map's own saved table, as before.

local function notes()
  return B:GetService("notes")
end

-- The map's own bookmarks (the saved table); handed over to the notes service once it is there.
local function own()
  local g = db().global
  if type(g.bookmarks) ~= "table" then
    g.bookmarks = {}
  end
  return g.bookmarks
end

function Bar.Bookmarks()
  local service = notes()
  if not service then
    return own()
  end
  local mine = own()
  if #mine > 0 then -- the map's own bookmarks move into the lists, once
    service:Import(mine)
    db().global.bookmarks = {}
  end
  return service:Bookmarks()
end

-- The name a bookmark of the current view gets unless the player gives one: "Elwynn Forest 42, 65".
function Bar.SuggestedName()
  local cam = Map.Camera()
  if not cam then
    return "?"
  end
  local name = Map.Describe(cam.continent, cam.wx, cam.wy)
  return (string.gsub(name or "?", "(%d+)%.%d", "%1"))
end

-- Keeps the current view: { name, continent, wx, wy, level }; nil when the list is full.
function Bar.AddBookmark(name)
  local cam = Map.Camera()
  if not cam or #Bar.Bookmarks() >= Bar.BOOKMARKS_MAX then
    B:Say(L["The bookmarks are full (%d); a right click removes one."], Bar.BOOKMARKS_MAX)
    return nil
  end
  name = name and strtrim(name) or ""
  if name == "" then
    name = Bar.SuggestedName()
  end
  local mark = { name = name, continent = cam.continent, wx = cam.wx, wy = cam.wy, level = cam.level }
  local service = notes()
  if service then
    mark = service:AddBookmark(mark)
  else
    local list = own()
    list[#list + 1] = mark
  end
  Bar.Refresh()
  return mark
end

function Bar.RenameBookmark(i, name)
  local mark = Bar.Bookmarks()[i]
  name = name and strtrim(name) or ""
  if mark and name ~= "" then
    local service = notes()
    if service and mark.id then
      service:RenameBookmark(mark.id, name)
    else
      mark.name = name
    end
    Bar.Refresh()
  end
end

function Bar.GoTo(i)
  local mark = Bar.Bookmarks()[i]
  if mark then
    Map.Fly(mark.continent, mark.wx, mark.wy, mark.level)
  end
end

function Bar.RemoveBookmark(i)
  local mark = Bar.Bookmarks()[i]
  if not mark then
    return
  end
  local service = notes()
  if service and mark.id then
    service:RemoveBookmark(mark.id)
  else
    table.remove(own(), i)
  end
  B:Say(L["Bookmark removed: %s"], mark.name)
  Bar.Refresh()
end

-- The name box under a pill: Enter keeps the text, Esc cancels. onDone(text) on Enter.
function Bar.AskName(anchor, text, onDone)
  if not nameBox then
    nameBox = CreateFrame("Frame", nil, panel:GetParent())
    nameBox:SetSize(240, 30)
    nameBox:SetFrameLevel(panel:GetFrameLevel() + 5)
    S.panel(nameBox, S.C.panel)
    nameBox.edit = B.UI.Widgets.Edit(nameBox, L["Bookmark name"], function(value)
      nameBox:Hide()
      if nameBox.onDone then
        nameBox.onDone(value)
      end
    end)
    nameBox.edit:SetPoint("TOPLEFT", 4, -4)
    nameBox.edit:SetPoint("BOTTOMRIGHT", -4, 4)
    nameBox.edit:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
      nameBox:Hide()
    end)
  end
  nameBox.onDone = onDone
  nameBox:ClearAllPoints()
  nameBox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  nameBox.edit:SetText(text or "")
  nameBox:Show()
  nameBox.edit:SetFocus()
  return nameBox
end

-- The right click menu of a bookmark: Rename, Remove.
local function bookmarkMenu(anchor, i)
  if not menu then
    menu = CreateFrame("Frame", nil, panel:GetParent())
    menu:SetSize(120, 48)
    menu:SetFrameLevel(panel:GetFrameLevel() + 5)
    S.panel(menu, S.C.panel)
    menu.rename = S.action(menu, { icon = "rename", label = L["Rename"], boxed = true })
    menu.rename:SetPoint("TOP", 0, -4)
    menu.remove = S.action(menu, { icon = "remove", label = L["Remove"], boxed = true })
    menu.remove:SetPoint("TOP", menu.rename, "BOTTOM", 0, -2)
    menu:SetScript("OnLeave", function(self)
      if not self:IsMouseOver() then
        self:Hide()
      end
    end)
  end
  menu.rename:SetScript("OnClick", function()
    menu:Hide()
    local mark = Bar.Bookmarks()[i]
    Bar.AskName(anchor, mark and mark.name, function(value)
      Bar.RenameBookmark(i, value)
    end)
  end)
  menu.remove:SetScript("OnClick", function()
    menu:Hide()
    Bar.RemoveBookmark(i)
  end)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu:Show()
  return menu
end
Bar.BookmarkMenu = bookmarkMenu

-- --- the pills ---------------------------------------------------------------------------------

local function pill(i)
  local p = pills[i]
  if p then
    return p
  end
  p = CreateFrame("Button", nil, panel)
  p:SetSize(Bar.PILL_H, Bar.PILL_H)
  p.face = S.roundFill(p, S.C.panel, "pill")
  p.edges = S.roundEdges(p, S.C.line, "pill")
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetSize(Bar.ICON, Bar.ICON)
  p.icon:SetPoint("CENTER")
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p.tipNow = true -- an icon only: its name at once, not after the tip delay (S.TipEnter)
  p:SetScript("OnClick", function(self, button)
    if self.onClick then
      self.onClick(button, self)
    end
  end)
  p:SetScript("OnEnter", function(self)
    S.TipEnter(self)
  end)
  p:SetScript("OnLeave", function(self)
    S.TipLeave(self)
  end)
  pills[i] = p
  return p
end

-- Whether the view's zoom is outside a layer's levels (its pins do not show here).
local function outOfRange(def)
  local cam = Map.Camera()
  if not cam then
    return false
  end
  local level = math.floor(cam.level + 0.5)
  return level < (def.minLevel or 0) or level > (def.maxLevel or math.huge)
end

local STYLE_TIPS = {
  physical = "The ground as it is: the game's minimap tiles and Bastian's Map Art.",
  blizzard = "Blizzard's painted maps as one seamless map, every zone explored.",
  modern = "Bastian's modern map: clear colours, woods, white roads, every house.",
  pencil = "Bastian's coloured pencil map, drawn stroke by stroke.",
  parchment = "Bastian's parchment map in ink, every tree and every house.",
}

-- Every style's icon in its menu.
local STYLE_ICONS = {
  physical = "herb",
  blizzard = "zone",
  modern = "route",
  pencil = "note",
  parchment = "ledger",
}

-- The styles for the style menu: { id = "style:<key>", text, icon, on, tip, onClick }.
function Bar.StyleItems()
  local out = {}
  for _, style in ipairs(Map.StyleList()) do
    out[#out + 1] = {
      id = "style:" .. style,
      text = Map.StyleTitle(style),
      icon = STYLE_ICONS[style] or "zone",
      on = Map.Style() == style,
      tip = L[STYLE_TIPS[style] or "One of Bastian's map styles."],
      onClick = function()
        Map.SetStyle(style)
      end,
    }
  end
  return out
end

function Bar.StyleMenu(anchor)
  local entries = {}
  for _, e in ipairs(Bar.StyleItems()) do
    entries[#entries + 1] = {
      label = e.text,
      icon = B.UI.IconTexture(e.icon),
      on = e.on, -- the chosen style: a lit row
      onClick = e.onClick,
    }
  end
  return B.UI.Menu(anchor, L["Map style"], entries, mod)
end

-- The bookmarks for the bookmark menu: one per bookmark (a click flies there), then keeping this
-- view and the way to rename or remove one: { id, text, onClick(frame) }.
function Bar.BookmarkItems()
  local out = {}
  for i, mark in ipairs(Bar.Bookmarks()) do
    out[#out + 1] = {
      id = "bookmark:" .. i,
      text = tostring(mark.name),
      onClick = function()
        Bar.GoTo(i)
      end,
    }
  end
  out[#out + 1] = {
    id = "bookmark:add",
    text = L["Keep this view as a bookmark"],
    onClick = function(frame)
      Bar.AskName(frame, Bar.SuggestedName(), function(value)
        Bar.AddBookmark(value)
      end)
    end,
  }
  if #out > 1 then
    out[#out + 1] = {
      id = "bookmark:edit",
      text = L["Rename or remove a bookmark"],
      onClick = function(frame)
        local entries = {}
        for i, mark in ipairs(Bar.Bookmarks()) do
          entries[#entries + 1] = {
            label = tostring(mark.name),
            onClick = function()
              bookmarkMenu(frame, i)
            end,
          }
        end
        B.UI.Menu(frame, L["Rename or remove a bookmark"], entries, mod)
      end,
    }
  end
  return out
end

function Bar.BookmarksMenu(anchor)
  local entries = {}
  for _, e in ipairs(Bar.BookmarkItems()) do
    entries[#entries + 1] = {
      label = e.text,
      icon = e.id:find("^bookmark:%d") and B.UI.IconTexture("spot") or nil, -- a path, not a kind
      onClick = function()
        e.onClick(anchor)
      end,
    }
  end
  return B.UI.Menu(anchor, L["Bookmarks"], entries, mod)
end

-- The items of the bar in order: { kind = "gap", text } between two apps (the app's name, not
-- drawn) | { kind = "pill", id, icon, text (the tooltip's title), on, dim, tip, onClick }.
function Bar.Items()
  local items = {
    {
      kind = "pill",
      id = "style",
      icon = "zone",
      text = L["Map style"] .. ": " .. Map.StyleTitle(Map.Style()),
      on = true,
      tip = L["Click to choose how the map is drawn."],
      onClick = function(_, frame)
        Bar.StyleMenu(frame)
      end,
    },
  }
  local lastOwner
  for _, def in ipairs(B:GetMapLayers()) do
    local owner = def.owner and (def.owner.title or def.owner.name) or "?"
    if owner ~= lastOwner then
      items[#items + 1] = { kind = "gap", text = tostring(owner) }
      lastOwner = owner
    end
    local id = def.id
    local dim = outOfRange(def)
    local tip = (def.tip or L["Click to show or hide this layer."]) .. " (" .. tostring(owner) .. ")"
    if dim then
      tip = tip .. " " .. L["(Not at this zoom: zoom in or out to see it.)"]
    end
    items[#items + 1] = {
      kind = "pill",
      id = id,
      icon = def.icon or "other",
      text = tostring(def.label or id),
      on = ns.Pins.IsLayerOn(def),
      dim = dim,
      tip = tip,
      onClick = function()
        ns.Pins.SetLayerOn(id, not ns.Pins.IsLayerOn(B:GetMapLayer(id)))
        Bar.Refresh()
      end,
    }
  end
  items[#items + 1] = { kind = "gap", text = L["Bookmarks"] }
  items[#items + 1] = {
    kind = "pill",
    id = "bookmarks",
    icon = "spot",
    text = L["Bookmarks"],
    on = true,
    tip = L["Fly to a bookmark, keep this view, rename or remove one."],
    onClick = function(_, frame)
      Bar.BookmarksMenu(frame)
    end,
  }
  return items
end

-- Lays the items out left to right, wrapping at the panel's width; returns the height used.
function Bar.Refresh()
  if not panel then
    return 0
  end
  local width = (panel:GetWidth() or 0)
  if width <= 0 then
    width = 600
  end
  width = width - 2 * Bar.EDGE
  local x, y = 0, 0
  local np = 0
  for _, item in ipairs(Bar.Items()) do
    local frame, w
    if item.kind == "gap" then
      if x > 0 then
        x = x + Bar.GROUP_GAP - Bar.GAP
      end
    else
      np = np + 1
      frame = pill(np)
      frame.id, frame.onClick = item.id, item.onClick
      frame.tip = function()
        return item.text, item.tip
      end
      B.UI.PaintIcon(frame.icon, B.UI.IconTexture(item.icon) or B.UI.IconTexture("other"))
      frame.icon:SetAlpha(item.on and (item.dim and 0.55 or 1) or 0.35)
      S.tint(frame.face, item.on and S.C.accent or S.C.panel, item.on and (item.dim and 0.1 or 0.25) or nil)
      S.setEdges(
        frame.edges,
        item.on and S.C.accent or S.C.line,
        item.on and (item.dim and 0.4 or 0.8) or nil
      )
      w = Bar.PILL_H
      frame:SetSize(w, Bar.PILL_H)
      frame.face:Layout()
      frame.edges:Layout()
      if x > 0 and x + w > width then
        x, y = 0, y + Bar.PILL_H + Bar.LINE_GAP
      end
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", panel, "TOPLEFT", Bar.EDGE + x, -(Bar.EDGE + y))
      frame:Show()
      x = x + w + Bar.GAP
    end
  end
  for i = np + 1, #pills do
    pills[i]:Hide()
  end
  target = y + Bar.PILL_H + 2 * Bar.EDGE
  if not slide then
    panel:SetHeight(target)
  end
  return target
end

-- --- open and shut: the panel slides ----------------------------------------------------------

function Bar.IsOpen()
  return db().profile.barOpen ~= false
end

local function setTab(open)
  tab.arrow:SetRotation(open and math.pi / 2 or -math.pi / 2) -- the suite's arrow: up shuts, down opens
  tab.label:SetText(open and "" or L["Layers"])
  tab.tip = open and L["Hide the layers and bookmarks."] or L["Show the layers and bookmarks."]
  tab:SetWidth(open and 40 or 90)
  tab.arrow:ClearAllPoints()
  if open then
    tab.arrow:SetPoint("CENTER")
  else
    tab.arrow:SetPoint("LEFT", 8, 0)
  end
end

local function anchorTab(open)
  tab:ClearAllPoints()
  if open then
    tab:SetPoint("TOP", panel, "BOTTOM", 0, 0)
  else
    tab:SetPoint("TOP", Map.clip, "TOP", 0, 0)
  end
end

local function finishSlide()
  local open = slide.to > 0
  slide = nil
  panel:SetScript("OnUpdate", nil) -- no work while nothing moves (CLAUDE.md golden rule 7)
  if open then
    panel:SetHeight(target)
  else
    panel:Hide()
  end
  setTab(open) -- shutting, the tab keeps its look until the panel is gone
  anchorTab(open)
end

-- The slide's time is summed from the frames, each step at most a sixth of the slide: the frame of
-- the click is often a long one and had swallowed most of the shut, which then looked like a jump
--. The same smooth curve both ways.
local function onSlide(_, elapsed)
  slide.t = slide.t + math.min(elapsed or 0, Bar.SLIDE / 6)
  local t = slide.t / Bar.SLIDE
  if t >= 1 then
    finishSlide()
    return
  end
  local eased = t * t * (3 - 2 * t)
  panel:SetHeight(math.max(slide.from + (slide.to - slide.from) * eased, 1))
end

local function place(animate)
  if not (panel and tab) then
    return
  end
  local open = Bar.IsOpen()
  if open or not animate then
    setTab(open)
  end
  if open then
    panel:Show()
    Bar.Refresh()
  end
  if not animate then
    slide = nil
    panel:SetScript("OnUpdate", nil)
    if open then
      panel:SetHeight(target)
    else
      panel:Hide()
    end
    anchorTab(open)
    return
  end
  local from = panel:IsShown() and (panel:GetHeight() or 0) or 0
  if open and from <= 1 then
    from = 1
  end
  anchorTab(true) -- the tab rides on the panel's edge while it slides
  panel:Show()
  slide = { from = from, to = open and target or 0, t = 0 }
  panel:SetHeight(math.max(from, 1))
  panel:SetScript("OnUpdate", onSlide)
end

function Bar.SetOpen(open)
  db().profile.barOpen = open and true or false
  place(true)
end

function Bar.Panel()
  return panel
end

function Bar.Tab()
  return tab
end

-- --- wiring -----------------------------------------------------------------------------------

table.insert(Map.onBuild, function(clip)
  local level = (clip:GetFrameLevel() or 1) + 30
  panel = CreateFrame("Frame", nil, clip:GetParent())
  panel:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
  panel:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
  panel:SetFrameLevel(level)
  panel:SetClipsChildren(true) -- the pills show as the panel slides open
  S.panel(panel, S.C.panel)
  S.tint(panel.bg, S.C.panel, 0.85) -- the map shows through a little
  panel:EnableMouse(true) -- clicks on the bar do not pan the map
  tab = CreateFrame("Button", nil, clip:GetParent())
  tab:SetHeight(16)
  tab:SetFrameLevel(level + 1)
  S.panel(tab, S.C.panel)
  tab.arrow = tab:CreateTexture(nil, "ARTWORK")
  tab.arrow:SetTexture(S.ARROW)
  tab.arrow:SetSize(12, 12)
  tab.arrow:SetVertexColor(S.C.accent[1], S.C.accent[2], S.C.accent[3], 1)
  tab.label = S.text(tab, 11, S.C.dim)
  tab.label:SetPoint("LEFT", tab.arrow, "RIGHT", 6, 0)
  tab:SetScript("OnClick", function()
    Bar.SetOpen(not Bar.IsOpen())
  end)
  tab:SetScript("OnEnter", function(self)
    S.TipEnter(self)
  end)
  tab:SetScript("OnLeave", function(self)
    S.TipLeave(self)
  end)
  Map.bar = Bar
  place(false)
end)

-- the width or the zoom changed: lay the pills out again (only then, not on every pan)
local lastWidth, lastLevel
table.insert(Map.onView, function(cam)
  local width = panel and panel:IsShown() and panel:GetWidth()
  local level = cam and math.floor(cam.level + 0.5)
  if width and (width ~= lastWidth or level ~= lastLevel) then
    lastWidth, lastLevel = width, level
    Bar.Refresh()
  end
end)

-- an app came or went with its layers, or a layer was switched from elsewhere (Pins.lua's handlers
-- call this: one bus handler per message and module)
function Bar.LayersChanged()
  if panel and panel:IsShown() then
    Bar.Refresh()
  end
end

table.insert(Map.onEnable, function(self)
  mod = self
end)
ns.mod.LayerBar = Bar
