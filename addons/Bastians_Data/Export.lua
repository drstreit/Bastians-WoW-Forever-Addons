-- Bastian's Data: your captures as a text to share (catalog review B5, 07.11.2026): the walks the
-- mesh missed, the flight times, the ride waits and (version 2, 10.11.2026) the places where a
-- quest step's count rose, as lines a player copies into a GitHub issue ("Share your captures");
-- tools/capture_import.py reads them and the build credits "n captures". Positions and times
-- only: no name, no character, no account.
local _, ns = ...
local B = Bastians
local Data = ns.Data
local L = ns.L
local S = B.UI.Style

local Export = {}
Data.Export = Export

Export.VERSION = 2 -- 2: the `step` lines (data.md "Step places from play")
Export.FRAME = "BastiansDataExport"

local function fmt1(n)
  return string.format("%.1f", n)
end

-- "<quest>:<n>" -> quest, n; nil for a key that is none.
local function stepKey(key)
  local quest, n = tostring(key):match("^(%d+):(%d+)$")
  return tonumber(quest), tonumber(n)
end

-- The checksum both sides agree on: the bytes of the body (the lines joined with newlines),
-- summed, modulo 65536.
function Export.Sum(body)
  local sum = 0
  for i = 1, #body do
    sum = (sum + body:byte(i)) % 65536
  end
  return sum
end

-- The text, pure over the learned table (world-graph.md section 9): the header, one line per
-- walk, flight time, ride and quest step (`step <quest> <n> <uiMapID> <x,y;...>`, one line per
-- map, map fractions with four decimals), then END with the line count and the checksum, so a
-- cut or a changed paste shows. nil when nothing was learned.
function Export.Text(learned, client, build, at)
  local lines = {}
  for _, w in ipairs(learned and learned.walk or {}) do
    if type(w) == "table" and type(w.map) == "number" and type(w.points) == "table" and #w.points >= 2 then
      local pts = {}
      for i, p in ipairs(w.points) do
        pts[i] = fmt1(p[1]) .. "," .. fmt1(p[2])
      end
      lines[#lines + 1] = string.format(
        "walk %d %s %s %s",
        w.map,
        type(w.len) == "number" and fmt1(w.len) or "-",
        w.at and tostring(w.at) or "-",
        table.concat(pts, ";")
      )
    end
  end
  local keys = {}
  for k, v in pairs(learned and learned.taxi or {}) do
    if type(v) == "number" then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    lines[#lines + 1] = string.format("taxi %s %s", k, fmt1(learned.taxi[k]))
  end
  keys = {}
  for k, v in pairs(learned and learned.ride or {}) do
    if type(v) == "table" and #v > 0 then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local waits = {}
    for i, w in ipairs(learned.ride[k]) do
      waits[i] = fmt1(w)
    end
    lines[#lines + 1] = string.format("ride %s %s", k, table.concat(waits, ","))
  end
  keys = {}
  for k, v in pairs(learned and learned.steps or {}) do
    if type(v) == "table" and stepKey(k) then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys, function(a, b)
    local qa, na = stepKey(a)
    local qb, nb = stepKey(b)
    if qa ~= qb then
      return qa < qb
    end
    return na < nb
  end)
  for _, k in ipairs(keys) do
    local quest, n = stepKey(k)
    local byMap, maps = {}, {}
    for _, p in ipairs(learned.steps[k]) do
      if
        type(p) == "table"
        and type(p[1]) == "number"
        and type(p[2]) == "number"
        and type(p[3]) == "number"
      then
        if not byMap[p[1]] then
          byMap[p[1]] = {}
          maps[#maps + 1] = p[1]
        end
        table.insert(byMap[p[1]], string.format("%.4f,%.4f", p[2], p[3]))
      end
    end
    table.sort(maps)
    for _, map in ipairs(maps) do
      lines[#lines + 1] = string.format("step %d %d %d %s", quest, n, map, table.concat(byMap[map], ";"))
    end
  end
  if #lines == 0 then
    return nil
  end
  local body = table.concat(lines, "\n")
  return string.format(
    "BASTIANS CAPTURE %d %s %s %s\n%s\nEND %d %d\n",
    Export.VERSION,
    tostring(client),
    tostring(build),
    tostring(at),
    body,
    #lines,
    Export.Sum(body)
  )
end

-- The client and build the packs were built for (the packs' meta), else the game's.
local function origin()
  local service = B:GetService("data")
  local meta = service and service.Meta and service:Meta() or nil
  local world = meta and meta.packs and meta.packs.world or nil
  local client = world and world.client or "forever"
  local build = world and world.build
  if not build then
    local ok, _, number = pcall(GetBuildInfo)
    build = ok and number or "?"
  end
  return client, build
end

local win

-- The window: the text in a read-only box, selected for Ctrl+C; a change is undone; Escape closes.
local function buildWindow()
  win = CreateFrame("Frame", Export.FRAME, UIParent)
  win:SetSize(560, 360)
  win:SetPoint("CENTER")
  win:SetFrameStrata(B.UI.WINDOW_STRATA) -- over the window it was opened from
  win:SetToplevel(true)
  win:EnableMouse(true)
  S.panel(win, S.C.bg)
  win.title = S.text(win, 13, S.C.text)
  win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -10)
  win.title:SetPoint("RIGHT", win, "RIGHT", -40, 0)
  win.title:SetText(L["Your captures"])
  win.note = S.text(win, 11, S.C.dim)
  win.note:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -4)
  win.note:SetPoint("RIGHT", win, "RIGHT", -12, 0)
  win.note:SetText(
    L["The text is selected: press Ctrl+C, then paste it into a GitHub issue (Share your captures). Positions and times only, no names."] -- luacheck: ignore 631 (a locale key stays one literal)
  )
  win.close = S.action(win, {
    icon = "close",
    label = L["Close"],
    row = true,
    onClick = function()
      win:Hide()
    end,
  })
  win.close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -8)
  local scroll = CreateFrame("ScrollFrame", nil, win)
  scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -52)
  scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -26, 12)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFont(S.font(), S.size(11), "")
  S.fonts[box] = 11
  S.ink(box, S.C.text)
  box:SetWidth(510)
  box:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)
  box:SetScript("OnTextChanged", function(self, byUser)
    if byUser and self.payload then
      self:SetText(self.payload) -- read-only: a key press puts the text back
      self:HighlightText()
    end
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    win:Hide()
  end)
  scroll:SetScrollChild(box)
  win.box = box
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, Export.FRAME) -- Escape closes it like the game's own windows
  end
end

-- Shows the captures as text; false, with a line in the chat, when nothing was learned yet.
function Export.Show()
  local client, build = origin()
  local at = date("!%Y-%m-%dT%H:%M:%SZ")
  local text = Export.Text(Data.Graph and Data.Graph.learned, client, build, at)
  if not text then
    B:Say(L["Nothing learned yet: walk off the roads, fly, ride a boat; then come back here."])
    return false
  end
  if not win then
    buildWindow()
  end
  win.box.payload = text
  win.box:SetText(text)
  win:Show()
  win:Raise()
  win.box:SetFocus()
  return true
end

function Export.Hide()
  if win then
    win:Hide()
  end
end

function Export.Window()
  return win
end
