-- What's new for the whole suite (ADR 0021, core.md "What's new"): the modules' entries (`news` in
-- a module definition), what the player has seen per account, the dot on the suite's minimap
-- button, at most one chat line after an update, and the hub page. News.Entries, News.Unseen and
-- News.Lines are pure over the modules and the saved state; News.Render draws the page.
local _, ns = ...
local B = ns.B
local L = ns.L
local S = ns.Style
local W = B.UI.Widgets

local News = {}
B.UI.News = News

local WEEK = 7 * 24 * 3600
local MODES = { always = true, weekly = true, never = true }

-- Core's per-account state: { seen = { [key] = true }, versions, said }. Created here, not as a
-- default: defaults are metatables, and the seen ids must reach the saved file.
local function state()
  local g = ns.core and ns.core.db and ns.core.db.global
  if not g then
    return nil
  end
  if type(rawget(g, "news")) ~= "table" then
    g.news = {}
  end
  if type(g.news.seen) ~= "table" then
    g.news.seen = {}
  end
  return g.news
end

function News.Mode()
  local g = ns.core and ns.core.db and ns.core.db.global
  local mode = g and g.newsMode
  return MODES[mode] and mode or "always"
end

local function entriesOf(mod)
  local src = mod.def.news
  if type(src) == "function" then
    local ok, list = ns.safecall(mod, src, mod)
    return ok and type(list) == "table" and list or {}
  end
  return type(src) == "table" and src or {}
end

-- Every enabled module's entries, newest first: { key, owner, source, date, version, text, open }.
-- `key` is "<module>:<id>" (the id defaults to the version or date and the text).
function News.Entries()
  local out = {}
  for _, mod in B:IterateModules() do
    if mod.def.news ~= nil and mod.state == "enabled" then
      for _, e in ipairs(entriesOf(mod)) do
        if type(e) == "table" and e.text and e.date then
          local id = e.id or ((e.version or e.date) .. ":" .. e.text)
          out[#out + 1] = {
            key = mod.name .. ":" .. tostring(id),
            owner = mod,
            source = e.source or mod.title,
            date = tostring(e.date),
            version = e.version,
            text = e.text,
            open = e.open,
          }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.date ~= b.date then
      return a.date > b.date
    end
    if a.source ~= b.source then
      return tostring(a.source) < tostring(b.source)
    end
    return a.key < b.key
  end)
  return out
end

function B:NewsEntries()
  return News.Entries()
end

function News.IsSeen(entry, st)
  st = st or state()
  return st ~= nil and st.seen[entry.key] == true
end

function News.Unseen(entries)
  local st = state()
  if not st then
    return 0
  end
  local n = 0
  for _, e in ipairs(entries or News.Entries()) do
    if not st.seen[e.key] then
      n = n + 1
    end
  end
  return n
end

function B:NewsUnseen()
  return News.Unseen()
end

-- What an entry opens: its own function, else the app's window (both the owner's, ADR 0021).
local function opener(e)
  if type(e.open) == "function" then
    return function()
      ns.safecall(e.owner, e.open)
    end
  end
  local open = e.owner.def.open
  if type(open) == "function" and not e.owner.parent then
    return function()
      ns.safecall(e.owner, open)
    end
  end
  return nil
end

-- The page as { kind = "header" | "entry" | "note", text, new, open }, newest first by date.
function News.Lines()
  local lines = {}
  local entries = News.Entries()
  if #entries == 0 then
    lines[1] = {
      kind = "note",
      text = L["Nothing new yet: updates of the suite and the daily data say here what changed."],
    }
    return lines
  end
  local st = state()
  local date
  for _, e in ipairs(entries) do
    if e.date ~= date then
      date = e.date
      lines[#lines + 1] = { kind = "header", text = date }
    end
    local version = e.version and (" " .. S.H.muted .. "(" .. e.version .. ")|r") or ""
    lines[#lines + 1] = {
      kind = "entry",
      text = tostring(e.source) .. ": " .. e.text .. version,
      new = not News.IsSeen(e, st),
      open = opener(e),
    }
  end
  return lines
end

-- ---------------------------------------------------------------------------------------------
-- Marking seen, the dot, the chat line
-- ---------------------------------------------------------------------------------------------

-- Marks the entries seen: all (the page was shown; ids that no longer exist are dropped) or one
-- module's (an app showed its own list).
function News.MarkSeen(owner)
  local st = state()
  if not st then
    return
  end
  local entries = News.Entries()
  if owner == nil then
    local seen = {}
    for _, e in ipairs(entries) do
      seen[e.key] = true
    end
    st.seen = seen
  else
    for _, e in ipairs(entries) do
      if e.owner == owner then
        st.seen[e.key] = true
      end
    end
  end
  News.UpdateDot()
end

function B:MarkNewsSeen(owner)
  News.MarkSeen(owner)
end

local pending = false -- the dot or the line wait for the end of combat
local waiter = CreateFrame("Frame")
waiter:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_REGEN_ENABLED")
  pending = false
  News.UpdateDot()
  if News.lineWaiting then
    News.lineWaiting = nil
    News.Say()
  end
end)

local function inCombat()
  if InCombatLockdown and InCombatLockdown() then
    if not pending then
      pending = true
      waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    return true
  end
  return false
end

-- The dot on the suite's minimap button: shown while something is new, unless the setting is
-- Never; not changed in combat.
function News.UpdateDot()
  local button = B.UI.Launcher and B.UI.Launcher.Current and B.UI.Launcher.Current()
  if not button or inCombat() then
    return
  end
  local show = News.Mode() ~= "never" and News.Unseen() > 0
  if show and not button.newsDot then
    local dot = button:CreateTexture(nil, "OVERLAY", nil, 7)
    dot:SetTexture(S.DISC)
    dot:SetSize(9, 9)
    dot:SetPoint("TOPRIGHT", button, "TOPRIGHT", -3, -3)
    S.tint(dot, S.C.warn)
    button.newsDot = dot
  end
  if button.newsDot then
    if show then
      button.newsDot:Show()
    else
      button.newsDot:Hide()
    end
  end
end

-- The tooltip line of the suite's button.
function News.TipLine(tt)
  local n = News.Mode() ~= "never" and News.Unseen() or 0
  if n > 0 then
    S.TipLine(tt, string.format(L["%d new things: /bastians news"], n), "tipGold")
  end
end

-- The one chat line, by the setting: Always after every update, Weekly at most every seven days.
function News.Say()
  local st = state()
  local mode = News.Mode()
  if not st or mode == "never" or News.said then
    return false
  end
  local n = News.Unseen()
  if n == 0 then
    return false
  end
  local now = time()
  if mode == "weekly" and st.said and now - st.said < WEEK then
    return false
  end
  if inCombat() then
    News.lineWaiting = true
    return false
  end
  News.said, st.said = true, now
  local fmt = n == 1 and L["Bastian's Suite updated: 1 new thing, /bastians news"]
    or L["Bastian's Suite updated: %d new things, /bastians news"]
  B:Say(fmt, n)
  return true
end

-- At PLAYER_LOGIN, before the optional addons are listed: whether the suite ran on this account
-- before (its first start says nothing).
function News.Login()
  local g = ns.core and ns.core.db and ns.core.db.global
  News.ranBefore = g ~= nil and (rawget(g, "news") ~= nil or g.companionsNoted ~= nil)
end

-- A few seconds after login (the apps and packs have registered): first start, or an update?
function News.Check()
  local st = state()
  if not st then
    return
  end
  local versions = B.UI.Settings.Fingerprint(true)
  if st.versions == nil and not News.ranBefore then
    News.MarkSeen() -- a first start: everything there is counts as seen
    st.versions = versions
    return
  end
  local updated = st.versions ~= versions
  st.versions = versions
  News.UpdateDot()
  if updated then
    News.Say()
  end
end

-- ---------------------------------------------------------------------------------------------
-- The hub page
-- ---------------------------------------------------------------------------------------------

local function linkRow(canvas, text, onClick)
  local b = CreateFrame("Button", nil, canvas)
  b.label = S.text(b, 12, S.C.text)
  b.label:SetPoint("TOPLEFT", 0, -2)
  b.label:SetPoint("RIGHT", 0, 0)
  b.label:SetWordWrap(true)
  b.label:SetJustifyH("LEFT")
  b.label:SetText(text)
  b:SetHeight(math.max(1, math.ceil(#text / 76)) * 14 + 4)
  if onClick then
    b.hl = S.fill(b, S.C.hover, "ARTWORK")
    b.hl:Hide()
    b:SetScript("OnEnter", function(self)
      self.hl:Show()
    end)
    b:SetScript("OnLeave", function(self)
      self.hl:Hide()
    end)
    b:SetScript("OnClick", onClick)
  end
  b.text = text
  return b
end

function News.Render(canvas)
  for _, w in ipairs(canvas.widgets or {}) do
    w:Hide()
  end
  local width = (canvas:GetWidth() or 400) - 24
  local widgets = {}
  local y = -10
  local header = W.Header(canvas, L["What's new"])
  header:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
  header:SetWidth(width)
  header.text = L["What's new"]
  widgets[1] = header
  y = y - (header:GetHeight() or 16) - 6
  for _, line in ipairs(News.Lines()) do
    local w
    if line.kind == "header" then
      w = W.Note(canvas, line.text, S.C.accent)
      y = y - 4
    elseif line.kind == "entry" then
      local text = (line.new and (S.H.good .. L["new"] .. "|r  ") or "") .. line.text
      w = linkRow(canvas, text, line.open)
      w.open = line.open
    else
      w = W.Note(canvas, line.text)
    end
    w:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, y)
    w:SetWidth(width)
    w.text = w.text or line.text
    widgets[#widgets + 1] = w
    y = y - (w:GetHeight() or 16) - 2
  end
  canvas.widgets = widgets
  canvas.mod = nil
  canvas.contentHeight = -y + 10
  if canvas.onRendered then
    canvas.onRendered(canvas.contentHeight)
  end
  News.MarkSeen() -- read once shown; the "new" marks stay until the page is drawn again
end

-- Login and updates: the check after the apps registered; the dot follows module changes.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  C_Timer.After(3, News.Check)
end)
ns.on("BASTIANS_MODULE_STATE", function()
  News.UpdateDot()
end)
ns.on("BASTIANS_DATA_LOADED", function()
  News.UpdateDot()
end)
