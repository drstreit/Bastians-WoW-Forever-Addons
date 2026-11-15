-- UI kit: flat style (core-contracts §13). The theme's surfaces, 1 px lines, one accent colour, no
-- Blizzard templates (but the game's window frame of the skin, ADR 0034). Ported from AHSyncGuide
-- Style.lua; the font comes from Core's profile, the colours from the theme (ST3, ADR 0017),
-- EllesmereUI is optional.
local _, ns = ...
local B = ns.B

B.UI = B.UI or {}
local S = {}
B.UI.Style = S
ns.Style = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
S.WHITE = WHITE
-- The Asian clients (ADR 0033, 29.10.2026): ARIALN and Morpheus carry no Hangul or Han, so there
-- the default font is the client's own (STANDARD_TEXT_FONT, set by FrameXML for its script) and
-- the Azeroth headings stay in it.
local CJK = { koKR = true, zhCN = true, zhTW = true }
S.CJK = CJK[type(GetLocale) == "function" and GetLocale() or ""] or false
-- Russian (04.11.2026, assumed, forever-api.md): Cyrillic is not verified in ARIALN, Morpheus,
-- Friz Quadrata or the suite's own fonts, so ruRU keeps the client's font too. S.CLIENT_FONT is
-- true for every client that does (the Asian ones and ruRU); S.CJK stays true for the Asian ones only.
local CLIENT_FONT = { koKR = true, zhCN = true, zhTW = true, ruRU = true }
S.CLIENT_FONT = CLIENT_FONT[type(GetLocale) == "function" and GetLocale() or ""] or false
S.DEFAULT_FONT = S.CLIENT_FONT and rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\ARIALN.TTF"
-- The suite's own textures (tools/make_media.py): a 64x64 white arrow with a dark rim pointing
-- east, tinted with SetVertexColor and turned with SetRotation.
S.ARROW = "Interface\\AddOns\\Bastians_Core\\Media\\Arrow"

-- The colour tokens of the active theme (ST3, ADR 0017; the themes are UI/Themes.lua, compiled from
-- pipeline/config/themes/*.toml). S.C holds one table { r, g, b, a } per token. A theme change
-- writes the new values into the same tables, so a widget that kept `S.C.accent` sees the new
-- colour at its next draw; the kit re-colours what it drew itself (fills, edges, texts) and
-- BASTIANS_THEME_CHANGED asks the apps to draw again. S.H holds the tokens as "|cffRRGGBB" for
-- text (strings cannot change in place: read S.H at use, never keep it in a local). S.SHAPE
-- holds the corner radii.
S.C = {}
S.H = {}
S.SHAPE = { radius = 0, radiusSmall = 0 }
S.G = {} -- the look's geometry tokens (ADR 0046), filled by the theme
S.THEMES = ns.THEMES or {}

-- What the kit drew with a token: texture -> { token table, alpha }, font string -> token table.
S.painted = setmetatable({}, { __mode = "k" })
S.inked = setmetatable({}, { __mode = "k" })

local function hexOf(c)
  return string.format("|cff%02x%02x%02x", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5)
end

local function themeById(id)
  for _, theme in ipairs(S.THEMES) do
    if theme.id == id then
      return theme
    end
  end
  return S.THEMES[1]
end

-- The colour tokens of a theme by id (0..1 RGBA tables), for a swatch of a look that is not in
-- use (the welcome's second pane); nil for an unknown id.
function S.ThemeColors(id)
  for _, theme in ipairs(S.THEMES) do
    if theme.id == id then
      return theme.colors
    end
  end
  return nil
end

-- The themes to choose from: { { id, name } } in their order.
function S.Themes()
  local out = {}
  for _, theme in ipairs(S.THEMES) do
    out[#out + 1] = { id = theme.id, name = theme.name }
  end
  return out
end

-- The id of the theme in use.
function S.ThemeId()
  return S.themeId
end

-- The corner radii: the theme's, then the look's own over them (ADR 0046: Glass rounds more,
-- Parchment squares the kind tiles); `tile` is the kind tiles' radius, the small one unless a
-- look says otherwise. Called with every theme load and every look change (S.ApplyLook).
local themeShape = {}
function S.applyShape()
  for key, value in pairs(themeShape) do
    S.SHAPE[key] = value
  end
  S.SHAPE.tile = S.SHAPE.radiusSmall
  local own = S.LookShape and S.LookShape() or nil
  for key, value in pairs(own or {}) do
    S.SHAPE[key] = value
  end
end

-- The theme's own radii, before a look's (S.RadiusOf for a frame of a look of its own).
function S.ThemeShape()
  return themeShape
end

-- Writes a theme's values into the token tables (an unknown id falls back to the first theme).
local function loadTheme(id)
  local theme = themeById(id)
  if not theme then
    return
  end
  S.themeId = theme.id
  for token, value in pairs(theme.colors) do
    local c = S.C[token]
    if not c then
      c = {}
      S.C[token] = c
    end
    c[1], c[2], c[3], c[4] = value[1], value[2], value[3], value[4] or 1
    S.H[token] = hexOf(c)
  end
  themeShape = theme.shape or {}
  S.applyShape()
  -- the look's geometry (ADR 0046): the widget set's sizes, read as S.G.<token> like S.C
  for key, value in pairs(theme.geometry or {}) do
    S.G[key] = value
  end
end
loadTheme(S.THEMES[1] and S.THEMES[1].id)

-- A fixed palette ("leave the menu out of the styling, it should always
-- be the same - the WoW look"): a theme's tokens in tables of their own, never touched by a theme
-- change. A window holding one (`frame.palette`) draws inside it: S.WithPalette while it builds,
-- S.Tok for what its widgets colour later (hover, focus, a list opened).
local palettes = {}
local themeC, themeH = S.C, S.H -- the theme's own tables (loadTheme fills them in place)
function S.Palette(id)
  if palettes[id] then
    return palettes[id]
  end
  local theme = themeById(id)
  local C, H = setmetatable({}, { __index = themeC }), setmetatable({}, { __index = themeH })
  for token, value in pairs(theme.colors) do
    C[token] = { value[1], value[2], value[3], value[4] or 1 }
    H[token] = hexOf(C[token])
  end
  palettes[id] = { id = id, C = C, H = H }
  return palettes[id]
end

-- Runs fn with S.C and S.H pointing at the palette, and puts the theme back even on an error.
function S.WithPalette(palette, fn, ...)
  if not palette or S.C == palette.C then -- the theme, or inside this palette already
    return fn(...)
  end
  local oldC, oldH = S.C, S.H
  S.C, S.H = palette.C, palette.H
  local result = { pcall(fn, ...) }
  S.C, S.H = oldC, oldH
  if not result[1] then
    error(result[2], 0)
  end
  return unpack(result, 2)
end

-- The palette a frame draws in: its own or an ancestor's, nil for the theme.
function S.PaletteOf(frame)
  local f = frame
  for _ = 1, 40 do
    if not f then
      return nil
    end
    local p = f.palette
    if p then
      return p
    end
    f = f.GetParent and f:GetParent() or nil
  end
  return nil
end

-- A colour token as `frame` sees it: its window's palette, else the theme's (S.C).
function S.Tok(frame, name)
  local p = S.PaletteOf(frame)
  return (p and p.C[name]) or themeC[name]
end

-- Whether a region (a frame, a texture, a text) stands under `frame`.
local function under(region, frame)
  local f = region
  for _ = 1, 40 do
    if not f then
      return false
    end
    if f == frame then
      return true
    end
    f = f.GetParent and f:GetParent() or nil
  end
  return false
end

-- Whether a region stands under `frame` with no frame of a palette of its own between them (a
-- part that keeps its own palette, as the chat's stream on the game's dark ground, keeps it).
local function ownedBy(region, frame)
  local f = region
  for _ = 1, 40 do
    if not f then
      return false
    end
    if f == frame then
      return true
    end
    if f ~= region and f.palette ~= nil then
      return false
    end
    f = f.GetParent and f:GetParent() or nil
  end
  return false
end

-- The same for a painted part: a shape (S.roundFill, S.roundEdges) is no region and has no
-- parent; it stands in its frame, whose own palette counts too. Found 13.11.2026 (V25): a
-- window of a light look of its own kept its header's and its panels' rounded fills in the
-- suite's dark colours, so the header's buttons read dark on dark.
local function paintOwnedBy(part, frame)
  if getmetatable(part) ~= S.Shape then
    return ownedBy(part, frame)
  end
  local f = part.frame
  for _ = 1, 40 do
    if not f then
      return false
    end
    if f == frame then
      return true
    end
    if f.palette ~= nil then
      return false
    end
    f = f.GetParent and f:GetParent() or nil
  end
  return false
end

-- A frame changes its palette (`from` and `to` are palettes, nil for the theme): what the kit
-- drew under it with a token takes the same token of the new one, and its widgets draw again;
-- a part under it with a palette of its own keeps that one. The frame's own `palette` is set by
-- the caller first. Walks everything the kit drew once, so it is for a changed option, never for
-- a layout.
function S.Repalette(frame, from, to)
  local old, new = from and from.C or themeC, to and to.C or themeC
  local names = {}
  for name in pairs(themeC) do
    names[old[name]] = name
  end
  for tex, paint in pairs(S.painted) do
    local name = names[paint[1]]
    if name and paintOwnedBy(tex, frame) then
      S.tint(tex, new[name], paint[2])
    end
  end
  for fs, color in pairs(S.inked) do
    local name = names[color]
    if name and ownedBy(fs, frame) then
      S.ink(fs, new[name])
    end
  end
  for widget in pairs(S.widgets or {}) do
    if under(widget, frame) then
      S.Draw(widget)
    end
  end
end

-- A frame draws in a preset of its own (ADR 0046's look per window; plan-chat-v3.md §9, V13):
-- `values` a preset's values (Bastians.UI.Settings.PresetValues), its scheme the frame's palette,
-- its renderer the frame's look; nil puts the suite's back. What the kit drew under the frame
-- takes the new tokens, its widgets and their corners draw again. For a changed option, never
-- for a layout (it walks everything the kit drew).
function S.SetFramePreset(frame, values)
  local from = frame.palette
  local to = values and values.theme and S.Palette(values.theme) or nil
  frame.palette = to
  frame.look = values and values.look or nil
  frame.presetValues = values or nil
  if values then
    S.anyLook = true
  end
  S.Repalette(frame, from, to)
  for shape in pairs(S.shapes or {}) do
    if shape.frame and under(shape.frame, frame) then
      shape:Layout()
    end
  end
  -- its fonts (V17): every kit text under the frame takes the font of its role as the frame has it
  for fs in pairs(S.fonts) do
    if under(fs, frame) then
      S.refont(fs)
    end
  end
  for fs in pairs(S.headings) do
    if under(fs, frame) then
      S.applyHeading(fs)
    end
  end
end

local function eui()
  return _G.EllesmereUI
end

-- Take EllesmereUI's accent colour when it is loaded (optional bridge, never required).
function S.adopt()
  local E = eui()
  if E and E.GetAccentColor then
    local ok, r, g, b = pcall(E.GetAccentColor)
    if ok and r then
      local c = S.C.accent
      c[1], c[2], c[3] = r, g, b
      S.H.accent = hexOf(c)
    end
  end
end

-- Switches the theme: the tokens, then what the kit drew, then the apps (BASTIANS_THEME_CHANGED).
function S.ApplyTheme(id)
  loadTheme(id)
  S.adopt()
  for tex, paint in pairs(S.painted) do
    local c = paint[1]
    tex:SetVertexColor(c[1], c[2], c[3], paint[2] or c[4] or 1)
  end
  for fs, c in pairs(S.inked) do
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  end
  for shape in pairs(S.shapes or {}) do
    shape:Layout() -- the theme's radius
  end
  for fs in pairs(S.fonts) do
    S.applyShadow(fs)
  end
  for fs in pairs(S.headings) do
    S.applyShadow(fs)
  end
  B:Fire("BASTIANS_THEME_CHANGED", S.themeId)
end

-- Colours a texture with a token (and an alpha of its own), kept for the next theme change.
function S.tint(tex, color, alpha)
  S.painted[tex] = { color, alpha }
  tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

-- Colours a text with a token, kept for the next theme change.
function S.ink(fs, color)
  S.inked[fs] = color
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- A tooltip line in a tooltip-safe token (tipText, tipDim, tipGold): the game's tooltip stays dark
-- in every theme, so its words never take the window's text colours.
function S.TipLine(tooltip, text, token, wrap)
  local c = S.C[token or "tipText"] or S.C.tipText
  tooltip:AddLine(text, c[1], c[2], c[3], wrap)
end

-- An entity's lines on the game's tooltip ("the complete icon with all
-- stats"): an item, or a recipe's product, as the game draws it (every stat; Tooltips.lua adds the
-- suite's lines), anything else its name and summary. `text` stands in for an unknown name.
function S.EntityTip(tooltip, ref, text)
  local typ, id = B.Entity.Parse(ref)
  if typ == "recipe" then
    local d = B:GetService("data")
    local r = d and type(id) == "number" and d:Get("recipe", id)
    if r and r.item then
      typ, id = "item", r.item
    end
  end
  if typ == "item" and type(id) == "number" and tooltip.SetItemByID then
    tooltip:SetItemByID(id)
    return
  end
  local e = B:Entity(ref)
  S.TipLine(tooltip, e:Name() or text or ref, "tipText")
  local summary = e:Summary()
  if summary then
    S.TipLine(tooltip, summary, "tipDim")
  end
end

-- A texture back to its own colours (the game's icons): no token, nothing kept.
function S.untint(tex)
  S.painted[tex] = nil
  tex:SetVertexColor(1, 1, 1, 1)
end

-- Every font string the kit made, with its size, so a font change applies at once (weak keys).
S.fonts = setmetatable({}, { __mode = "k" })

function S.font()
  local core = ns.core -- Core's module, once Settings.lua has created and initialized it
  local font = core and core.db and core.db.profile.font
  if font then
    return font
  end
  local E = eui()
  if E and E.GetFontPath then
    local ok, path = pcall(E.GetFontPath)
    if ok and path then
      return path
    end
  end
  return S.DEFAULT_FONT
end

-- The text size in percent of the kit's sizes (General page, "and a
-- size, naturally"); rows keep their height, so the range stays 80 to 130.
function S.scale()
  local core = ns.core
  local pct = core and core.db and tonumber(core.db.profile.fontScale) or 100
  return math.max(80, math.min(130, pct)) / 100
end

-- A base size scaled to the setting.
function S.size(base)
  return math.floor((base or 12) * S.scale() + 0.5)
end

-- Fonts per window (plan-chat-v3.md V17, ADR 0046): a kit text has a role, each role a look
-- setting. `text` (S.text) and `heading` (S.heading) as before; `label` the small heads (a
-- section's title, a tab's label), `number` counts, times and prices. nil for label and number is
-- the text font, so a preset without them looks as it did.
S.FONT_KEYS = { text = "font", heading = "headingFont", label = "labelFont", number = "numberFont" }
S.LABEL_STEP = 2 -- px: a label in a face of its own reads small (the condensed ones)
S.roles = setmetatable({}, { __mode = "k" }) -- [font string] = "label" | "number"; nil: text

-- The values of the nearest frame up from `region` with a preset of its own, nil for the suite's.
local function ownValues(region)
  if not S.anyLook then -- no frame took a preset of its own (S.SetFramePreset)
    return nil
  end
  local f = region
  for _ = 1, 40 do
    if not f then
      return nil
    end
    local v = f.presetValues
    if v then
      return v
    end
    f = f.GetParent and f:GetParent() or nil
  end
  return nil
end

-- The font of a role where `region` stands: its window's preset, else the suite's profile. A
-- client with its own script (S.CLIENT_FONT) keeps the client's font for every role.
function S.FontOf(region, role)
  if S.CLIENT_FONT then
    return S.font()
  end
  local key = S.FONT_KEYS[role or "text"] or "font"
  local own = region and ownValues(region)
  if own then
    local text = own.font or S.font()
    return key ~= "font" and own[key] or text
  end
  if key == "font" then
    return S.font()
  elseif key == "headingFont" then
    return S.headingFont()
  end
  return S.Skin(key) or S.font()
end

-- A kit text's font and size again, by its role and where it stands.
function S.refont(fs)
  local base = S.fonts[fs]
  if not base then
    return
  end
  local role = S.roles[fs] or "text"
  local path = S.FontOf(fs, role)
  if role == "label" and path ~= S.FontOf(fs, "text") then
    base = base + S.LABEL_STEP
  end
  fs:SetFont(path, S.size(base), "")
end

-- Gives a kit text its role ("text", "label", "number") and the font of it.
function S.SetRole(fs, role)
  S.roles[fs] = (role and role ~= "text") and role or nil
  S.refont(fs)
  return fs
end

-- ---------------------------------------------------------------------------------------------
-- LibSharedMedia (plan-chat-v3.md V25, the look engine's skinning): borders, backgrounds and
-- sounds other addons register. Optional: without the library every answer is nil (golden rule 4).
-- ---------------------------------------------------------------------------------------------

local function sharedMedia()
  local stub = rawget(_G, "LibStub")
  if type(stub) ~= "table" and type(stub) ~= "function" then
    return nil
  end
  local ok, lsm = pcall(stub, "LibSharedMedia-3.0", true)
  return ok and type(lsm) == "table" and lsm or nil
end

-- Is LibSharedMedia loaded?
function S.HasMedia()
  return sharedMedia() ~= nil
end

-- The file of a medium of LibSharedMedia (`kind` "border", "background", "sound", ...) by its
-- name, nil without the library, the name, or for "none".
function S.Media(kind, name)
  local lsm = sharedMedia()
  if not lsm or type(name) ~= "string" or name == "" or name == "none" then
    return nil
  end
  local ok, path = pcall(lsm.Fetch, lsm, kind, name, true)
  return ok and type(path) == "string" and path ~= "" and path or nil
end

-- The names of a kind of medium, sorted; an empty list without the library.
function S.MediaNames(kind)
  local lsm = sharedMedia()
  local out = {}
  if lsm and type(lsm.HashTable) == "function" then
    local ok, list = pcall(lsm.HashTable, lsm, kind)
    for name in pairs(ok and type(list) == "table" and list or {}) do
      if type(name) == "string" then
        out[#out + 1] = name
      end
    end
  end
  table.sort(out)
  return out
end

-- A text that keeps a font of its own (the chat's lines): no font or preset change touches it.
function S.OwnFont(fs)
  S.fonts[fs] = nil
  S.roles[fs] = nil
  return fs
end

-- Sets a kit text's base size (scaled), kept for the next font or size change.
function S.setSize(fs, base)
  S.fonts[fs] = base
  S.refont(fs)
end

function S.applyFont()
  for fs in pairs(S.fonts) do
    S.refont(fs)
  end
  for fs in pairs(S.headings) do
    S.applyHeading(fs)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The look (ADR 0034, ADR 0038, core.md "The skin"): every look setting of the suite lives in
-- Core's profile and S.Skin reads it with its default; a preset writes them all at once
-- (Settings.ApplyPreset). The parts: the game's window frames, the colour scheme, the text and
-- the heading font, the game's buttons, the ornaments under section titles, the content switches.
-- ---------------------------------------------------------------------------------------------

S.SKIN_DEFAULTS = {
  preset = "modern-dark", -- the look as a preset (ADR 0038); headingFont nil is the text font
  -- `look` (ADR 0046, 01.11.2026): modern | wow | parchment | glass; nil in a profile saved before
  -- reads the game's buttons switch (S.LookId)
  skinFrames = true, -- the game's frames are the standard
  rowPortraits = true,
  placeCuts = true,
  diorama = true,
  modelMotion = true,
  pageSounds = true,
  gameButtons = false, -- the game's button textures on every kit button
  ornaments = false, -- the gold ornament under section titles
  sheetParchment = true, -- a page reads on parchment (ADR 0054); off: the look's colours
  gameFrames = false, -- the game's own windows and insets
}
S.HEADING_FONT = "Fonts\\MORPHEUS.TTF"
-- The suite's own fonts (ADR 0038, owner: "add 5 more"; 13.11.2026, plan-chat-v3.md V17: "5 new
-- open fonts - we should give some variety"; SIL Open Font License, Fonts/): { path, name }, listed
-- after the client's four. None has Hangul or Han (S.CLIENT_FONT keeps the client's).
local FONT_DIR = "Interface\\AddOns\\Bastians_Core\\Fonts\\" -- beside Media, like the Library's
S.ADDON_FONTS = {
  { FONT_DIR .. "Inter.ttf", "Inter" },
  { FONT_DIR .. "Exo2.ttf", "Exo 2" },
  { FONT_DIR .. "RobotoCondensed.ttf", "Roboto Condensed" },
  { FONT_DIR .. "Alegreya.ttf", "Alegreya" },
  { FONT_DIR .. "Cinzel.ttf", "Cinzel" },
  { FONT_DIR .. "IBMPlexSans.ttf", "IBM Plex Sans" },
  { FONT_DIR .. "IBMPlexMono.ttf", "IBM Plex Mono" },
  { FONT_DIR .. "Oswald.ttf", "Oswald" },
  { FONT_DIR .. "VarelaRound.ttf", "Varela Round" },
  { FONT_DIR .. "Almendra.ttf", "Almendra" },
}
S.SANS_FONT = FONT_DIR .. "IBMPlexSans.ttf" -- the artifact's text (Bastian's Chat, V17)
S.MONO_FONT = FONT_DIR .. "IBMPlexMono.ttf" -- the artifact's numbers (Bastian's Chat, V17)
S.SERIF_FONT = FONT_DIR .. "Alegreya.ttf" -- the Parchment preset's headings (plan-round4 H4)
S.ORNAMENT = "Interface\\AddOns\\Bastians_Core\\Media\\Ornament"
S.GLOW = "Interface\\AddOns\\Bastians_Core\\Media\\Glow" -- a soft disc behind the plate (ADR 0038)
-- a tileable parchment of our own (tools/make_media.py): the game's insets on a light scheme
S.PARCHMENT = "Interface\\AddOns\\Bastians_Core\\Media\\Parchment"

-- Colour by meaning (ADR 0038): the theme token of a service word (Data's kind groups), of an
-- entity type, and of an icon kind; nil for an unknown one. The colour sits on tiles, chips,
-- badges, counts and the plate, never on a name.
S.SERVICE_TOKENS = {
  Vendor = "svcVendor",
  Banker = "svcVendor",
  Auctioneer = "svcVendor",
  ["Quest giver"] = "svcQuest",
  Trainer = "svcTrainer",
  Innkeeper = "svcInn",
  ["Flight master"] = "svcFlight",
  Repair = "svcRepair",
  Hostile = "svcHostile",
  Friendly = "svcFriendly",
}
S.TYPE_TOKENS = {
  npc = "typeNpc",
  item = "typeItem",
  quest = "typeQuest",
  object = "typeObject",
  node = "typeNode",
  zone = "typeZone",
  recipe = "typeRecipe",
  spot = "typeSpot",
  chain = "typeChain",
  here = "typeHere",
}
S.KIND_TOKENS = {
  vendor = "svcVendor",
  banker = "svcVendor",
  auctioneer = "svcVendor",
  quest = "svcQuest",
  questActive = "svcQuest",
  trainer = "svcTrainer",
  innkeeper = "svcInn",
  flight = "svcFlight",
  repair = "svcRepair",
  mob = "svcHostile",
  mob_claw = "svcHostile",
  mob_dagger = "svcHostile",
  mob_bow = "svcHostile",
  mob_staff = "svcHostile",
  mob_axe = "svcHostile",
  mob_mace = "svcHostile",
  rare = "rare",
  item = "typeItem",
  zone = "typeZone",
  object = "typeObject",
  herb = "typeNode",
  mine = "typeNode",
  fish = "typeNode",
  treasure = "typeNode",
  spot = "typeSpot",
  chain = "typeChain",
  route = "typeHere",
  waypoint = "typeHere",
}
function S.ServiceToken(word)
  return word and S.SERVICE_TOKENS[word] or nil
end
function S.TypeToken(typ)
  return typ and S.TYPE_TOKENS[typ] or nil
end
function S.KindToken(kind)
  return kind and S.KIND_TOKENS[kind] or nil
end
S.FRAME_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Border"
S.FRAME_BG = "Interface\\DialogFrame\\UI-DialogBox-Background" -- the Blizzard skin's window ground
S.FRAME_INSETS = { left = 11, right = 12, top = 12, bottom = 11 } -- the border's own insets

function S.Skin(key)
  local core = ns.core
  local p = core and core.db and core.db.profile
  local v = p and p[key]
  if v == nil then
    return S.SKIN_DEFAULTS[key]
  end
  return v
end

-- The look's parts (ADR 0038): the ornaments, the game's buttons, a heading font of its own.
function S.Ornaments()
  return S.Skin("ornaments") == true
end

function S.GameButtons()
  return S.Skin("gameButtons") == true
end

-- The heading font: the profile's `headingFont`, else the text font; a client with its own script
-- keeps its own (Morpheus and the suite's fonts carry no Hangul or Han, Cyrillic is unverified).
function S.headingFont()
  if S.CLIENT_FONT then
    return S.font()
  end
  return S.Skin("headingFont") or S.font()
end

-- The game's own type and button textures ("a style that closely reflects
-- Blizzard"): the WoW preset sets them, `gameButtons` dresses every kit button in them.
S.BLIZZARD_FONT = "Fonts\\FRIZQT__.TTF"
S.BUTTON_UP = "Interface\\Buttons\\UI-Panel-Button-Up"
S.BUTTON_DOWN = "Interface\\Buttons\\UI-Panel-Button-Down"
S.BUTTON_HIGHLIGHT = "Interface\\Buttons\\UI-Panel-Button-Highlight"
-- The used part of the game's button textures (80 x 22 of 128 x 32) in three slices, as the game's
-- UIPanelButtonTemplate draws them: the caps keep their width and only the middle stretches (owner,
-- retail 31.10.2026: one stretched texture squeezed the caps of a wide settings button).
S.BUTTON_SLICES = { { 0, 0.09375 }, { 0.09375, 0.53125 }, { 0.53125, 0.625 } }
S.BUTTON_BOTTOM = 0.6875
S.BUTTON_CAP = 12 / 22 -- a cap's width per height of the button

-- Every kit button, so a skin change re-dresses the ones that exist.
S.buttons = setmetatable({}, { __mode = "k" })

local function slices(b, layer, path, blend)
  local parts = {}
  for i, s in ipairs(S.BUTTON_SLICES) do
    local t = b:CreateTexture(nil, layer)
    t:SetTexture(path)
    t:SetTexCoord(s[1], s[2], 0, S.BUTTON_BOTTOM)
    if blend then
      t:SetBlendMode(blend)
    end
    parts[i] = t
  end
  parts[1]:SetPoint("TOPLEFT")
  parts[1]:SetPoint("BOTTOMLEFT")
  parts[3]:SetPoint("TOPRIGHT")
  parts[3]:SetPoint("BOTTOMRIGHT")
  parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT")
  parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "BOTTOMLEFT")
  return parts
end

local function showSlices(parts, on)
  for _, t in ipairs(parts) do
    t:SetShown(on)
  end
end

-- The caps follow the button's height, and never pass its middle on a narrow one.
local function fitCaps(b)
  local art = b.gameArt
  local w, h = b:GetWidth() or 0, b:GetHeight() or 0
  local cap = math.max(1, math.min(math.floor(h * S.BUTTON_CAP + 0.5), math.floor(w / 2)))
  for _, parts in pairs(art) do
    parts[1]:SetWidth(cap)
    parts[3]:SetWidth(cap)
  end
end

local function gameArt(b)
  if b.gameArt then
    return b.gameArt
  end
  b.gameArt = {
    up = slices(b, "BACKGROUND", S.BUTTON_UP),
    down = slices(b, "BACKGROUND", S.BUTTON_DOWN),
    hl = slices(b, "HIGHLIGHT", S.BUTTON_HIGHLIGHT, "ADD"),
  }
  showSlices(b.gameArt.down, false)
  fitCaps(b)
  b:HookScript("OnSizeChanged", fitCaps)
  b:HookScript("OnMouseDown", function(self)
    if self.gameArtOn and self.enabledFlat ~= false then
      showSlices(self.gameArt.up, false)
      showSlices(self.gameArt.down, true)
    end
  end)
  b:HookScript("OnMouseUp", function(self)
    if self.gameArtOn then
      showSlices(self.gameArt.down, false)
      showSlices(self.gameArt.up, true)
    end
  end)
  return b.gameArt
end

-- The caps again after a look sized the button (the WoW renderer, after its layout).
function S.fitGameArt(b)
  if b.gameArt then
    fitCaps(b)
  end
end

-- Hides the game's button art where a look of its own draws the button (ADR 0046's Modern,
-- Parchment and Glass renderers call it; the WoW renderer calls S.applyButton).
function S.hideGameArt(b)
  if b.gameArt then
    b.gameArtOn = false
    for _, parts in pairs(b.gameArt) do
      showSlices(parts, false)
    end
  end
end

function S.applyButton(b)
  if S.GameButtons() then
    local art = gameArt(b)
    b.gameArtOn = true
    showSlices(art.up, true)
    showSlices(art.down, false)
    showSlices(art.hl, true)
    b.face:Hide()
    b.edges:Hide()
    -- the game's red buttons carry gold words ("gray on dark red is
    -- tricky"), whatever the scheme's text colour
    if b.label then
      S.ink(b.label, S.Palette("blizzard").C.gold) -- the game's own gold, on every scheme
    end
  else
    S.hideGameArt(b)
    b.face:Show()
    b.edges:Show()
    if b.label and b.labelToken then
      S.ink(b.label, S.Tok(b, b.labelToken))
    end
  end
end

-- A text's shadow by the scheme: none on a light ground (black under brown ink blurred the type
-- on parchment, ), the 1 px drop on a dark one.
function S.applyShadow(fs)
  local parent = fs.GetParent and fs:GetParent()
  if S.Light(parent) then
    fs:SetShadowOffset(0, 0)
  else
    fs:SetShadowOffset(1, -1)
  end
end

-- A heading: the heading font (ADR 0038: the profile's, else the text font) at `size`, or at
-- `bigSize` when a heading font of its own is set (Morpheus and the like read smaller), in
-- `color`; kept, so a preset, font or theme change applies at once.
S.headings = setmetatable({}, { __mode = "k" })

function S.applyHeading(fs)
  local h = S.headings[fs]
  if not h then
    return
  end
  local font = S.FontOf(fs, "heading") -- the window's (V17), else the suite's
  fs:SetFont(font, S.size(font ~= S.FontOf(fs, "text") and h.bigSize or h.size), "")
  S.ink(fs, h.color)
end

function S.heading(parent, size, bigSize, color, layer)
  local fs = S.text(parent, size, color, layer)
  S.fonts[fs] = nil -- the heading keeps its own font
  S.headings[fs] = {
    size = size or 12,
    bigSize = bigSize or size or 12,
    color = color or S.C.text,
  }
  S.applyHeading(fs)
  return fs
end

-- The gold ornament under a section title (`ornaments`), hidden by the caller when off.
function S.ornament(parent, layer)
  local t = parent:CreateTexture(nil, layer or "BORDER")
  t:SetTexture(S.ORNAMENT)
  S.tint(t, S.C.gold)
  t:SetHeight(8)
  return t
end

-- A skin setting changed: the headings, the window frames, then every app draws again.
-- The game's own frames ("I need a clearly skinned style according to
-- Blizzard examples"): the look's switch, and whether the client has the parts.
function S.GameFrames()
  return S.Skin("gameFrames") == true
end

-- Whether the scheme is light: dark ink on a light ground (Modern light, the Parchment look);
-- with `frame`, as that frame's window sees it (a fixed palette).
function S.Light(frame)
  local t = frame and S.Tok(frame, "text") or S.C.text
  return (0.299 * t[1] + 0.587 * t[2] + 0.114 * t[3]) < 0.5
end

-- ---------------------------------------------------------------------------------------------
-- Readable colours on a light ground (plan-chat-v3.md V25, "full skinning"): the game writes its
-- colours for its own dark frames (a common item's white link, a priest's white name, a rogue's
-- pale yellow, the say channel's white). On a light look such a colour is darkened just as far as
-- 4.5:1 on the window's panel needs (WCAG, as the theme compiler checks the tokens); on a dark
-- look nothing changes.
-- ---------------------------------------------------------------------------------------------

local function linear(c)
  return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(r, g, b)
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

S.READABLE = 4.5

-- A colour readable on `ground` ({ r, g, b }), the colour itself when it already is.
function S.ReadableColor(r, g, b, ground)
  local lg = luminance(ground[1], ground[2], ground[3])
  for step = 0, 40 do
    local k = 1 - step / 40
    local lc = luminance(r * k, g * k, b * k)
    local hi, lo = math.max(lc, lg), math.min(lc, lg)
    if (hi + 0.05) / (lo + 0.05) >= S.READABLE then
      return r * k, g * k, b * k
    end
  end
  return 0, 0, 0
end

local readable = {} -- [ground table] = { [RRGGBB] = RRGGBB }

-- A text's colour codes made readable where `frame` stands (a light look only).
function S.ReadableText(text, frame)
  if type(text) ~= "string" or not text:find("|c", 1, true) or not S.Light(frame) then
    return text
  end
  local ground = S.Tok(frame, "panel")
  local cache = readable[ground]
  if not cache then
    cache = {}
    readable[ground] = cache
  end
  return (
    text:gsub("|c(%x%x)(%x%x%x%x%x%x)", function(alpha, rgb)
      local out = cache[rgb]
      if not out then
        local r, g, b = S.ReadableColor(
          tonumber(rgb:sub(1, 2), 16) / 255,
          tonumber(rgb:sub(3, 4), 16) / 255,
          tonumber(rgb:sub(5, 6), 16) / 255,
          ground
        )
        out = string.format("%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
        cache[rgb] = out
      end
      return "|c" .. alpha .. out
    end)
  )
end

-- Shows or hides a texture, a frame or one of the kit's shapes (they have Show and Hide only).
function S.showPart(part, shown)
  if not part then
    return
  elseif part.SetShown then
    part:SetShown(shown and true or false)
  elseif shown then
    part:Show()
  else
    part:Hide()
  end
end

-- The game's inset behind a pane (InsetFrameTemplate: the bevelled edge, the marble ground; the
-- parchment ground on a light scheme so brown ink reads), shown while the look wears the game's
-- frames, the pane's own flat fill hidden then. The ground follows the window opacity.
S.insets = setmetatable({}, { __mode = "k" })
S.insetAlpha = 1
function S.applyInset(frame)
  local on = frame.insetForced or S.GameFrames()
  if on and frame.gameInset == nil then
    frame.gameInset = B.Compat.NewInset(frame) or false
    if frame.gameInset then
      frame.gameInset:SetAllPoints(frame)
      frame.gameInset.marble = frame.gameInset.Bg:GetTexture()
    end
  end
  local inset = frame.gameInset
  on = on and inset ~= nil and inset ~= false
  if inset then
    inset:SetShown(on)
    if on then
      if S.Light(frame) then
        inset.Bg:SetTexture(S.PARCHMENT, "REPEAT", "REPEAT")
      elseif inset.marble then
        inset.Bg:SetTexture(inset.marble, "REPEAT", "REPEAT")
      end
      inset.Bg:SetAlpha(S.insetAlpha)
    end
  end
  S.showPart(frame.bg, not on)
  S.showPart(frame.edges, not on)
end

-- `force`: the inset shows whatever the look (the settings window's menu, always the WoW look).
function S.inset(frame, force)
  S.insets[frame] = true
  frame.insetForced = force or nil
  S.applyInset(frame)
  return frame
end

function S.ApplySkin()
  for fs in pairs(S.headings) do
    S.applyHeading(fs)
  end
  for b in pairs(S.buttons) do
    S.applyButton(b)
  end
  for frame in pairs(S.insets) do
    S.applyInset(frame)
  end
  if S.ApplyLook then
    S.ApplyLook() -- the widget set, drawn by the look (ADR 0046)
  end
  if B.UI.ApplyWindowLook then
    B.UI.ApplyWindowLook()
  end
  B:Fire("BASTIANS_THEME_CHANGED", S.themeId)
end

function S.hex(c)
  return hexOf(c)
end

-- An item's name in the game's colour of its quality (Compat.QualityColor), the strongest text
-- when the quality or the colour is unknown. The game's quality colours read on every theme.
function S.QualityText(quality, text)
  local r, g, b = B.Compat.QualityColor(quality)
  if not r then
    return S.H.bright .. tostring(text) .. "|r"
  end
  return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, tostring(text))
end

-- The game's difficulty colour of a level against the character's, as a token name: red from +5,
-- orange from +3, yellow around it, green while it still gives experience (the Classic rule),
-- grey below; nil when a level is unknown.
function S.LevelToken(level, playerLevel)
  if not (level and playerLevel) then
    return nil
  end
  local diff = level - playerLevel
  if diff >= 5 then
    return "diffRed"
  elseif diff >= 3 then
    return "diffOrange"
  elseif diff >= -2 then
    return "diffYellow"
  end
  local green = playerLevel <= 5 and 5
    or (playerLevel <= 39 and math.floor(playerLevel / 10) + 5)
    or math.floor(playerLevel / 5) + 1
  return -diff <= green and "diffGreen" or "diffGrey"
end

-- The difficulty token of a level band (a zone's or a dungeon's) against the character's level:
-- the character's own level while it lies inside the band (yellow), else the nearer end, so a band
-- still ahead is orange or red and one left behind is green or grey. A band with one end takes
-- that end; nil when neither end or the character's level is known.
function S.BandToken(lo, hi, playerLevel)
  local level = lo or hi
  if not (level and playerLevel) then
    return nil
  end
  if lo and hi and hi > lo then
    level = math.max(lo, math.min(hi, playerLevel))
  end
  return S.LevelToken(level, playerLevel)
end

-- The relative luminance of a colour (WCAG 2), and the contrast of two colours (1 to 21).
local function channel(v)
  return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
end

function S.Luminance(c)
  return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
end

function S.Contrast(a, b)
  local la, lb = S.Luminance(a), S.Luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

-- The ink for words on a filled ground (a tile's badge, ADR 0056: 4.5 to 1): the dark or the
-- light badge ink of the colour set in force, whichever stands out more against `ground`.
function S.InkOn(ground)
  local dark, light = S.C.badgeInk, S.C.badgeInkLight
  return S.Contrast(dark, ground) >= S.Contrast(light, ground) and dark or light
end

-- A line of the game's tooltip in the theme (the tooltip's white would vanish on parchment): green
-- (Equip, Use) good, red (a requirement not met) bad, yellow gold, grey muted, the rest text.
function S.TipInk(r, g, b)
  if not (r and g and b) then
    return S.H.text
  end
  if g > 0.8 and r < 0.4 and b < 0.4 then
    return S.H.good
  elseif r > 0.8 and g < 0.4 and b < 0.4 then
    return S.H.bad
  elseif r > 0.85 and g > 0.7 and b < 0.3 then
    return S.H.gold
  elseif math.abs(r - g) < 0.05 and math.abs(g - b) < 0.05 and r < 0.75 then
    return S.H.muted
  end
  return S.H.text
end

function S.accent()
  return S.H.accent
end

function S.text(parent, size, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  S.fonts[fs] = size or 12
  S.refont(fs) -- the font of its window (V17)
  S.ink(fs, color or S.C.text)
  fs:SetJustifyH("LEFT")
  S.applyShadow(fs)
  return fs
end

function S.fill(frame, color, layer)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(WHITE)
  t:SetAllPoints()
  S.tint(t, color)
  return t
end

-- 1 px outline from four textures (no backdrop template needed on any client).
function S.border(frame, color)
  local c = color or S.C.line
  local edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetTexture(WHITE)
    S.tint(t, c)
    if side == "TOP" or side == "BOTTOM" then
      t:SetPoint(side .. "LEFT")
      t:SetPoint(side .. "RIGHT")
      t:SetHeight(1)
    else
      t:SetPoint("TOP" .. side)
      t:SetPoint("BOTTOM" .. side)
      t:SetWidth(1)
    end
    edges[side] = t
  end
  return edges
end

-- ---------------------------------------------------------------------------------------------
-- Round corners. A shape is
-- a fill or a 1 px outline made of pieces: four corners cut from Media/Disc (a disc's quarters) or
-- Media/Ring* (its outline), and WHITE8X8 bands between them. The radius is a theme token
-- ("radius", "radiusSmall"), a number, or "pill" (half the frame's height); a theme switch lays the
-- shapes out again. `corners` = "all" (default), "top" or "bottom": the others stay square. A
-- shape answers SetVertexColor, GetVertexColor, SetAlpha, Show, Hide like the texture it replaces,
-- so S.tint, S.setEdges and `frame.bg` work on it.
-- ---------------------------------------------------------------------------------------------

S.DISC = "Interface\\AddOns\\Bastians_Core\\Media\\Disc"
S.RINGS = {
  S = "Interface\\AddOns\\Bastians_Core\\Media\\RingS",
  M = "Interface\\AddOns\\Bastians_Core\\Media\\RingM",
  L = "Interface\\AddOns\\Bastians_Core\\Media\\RingL",
}
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local QUARTER = {
  TOPLEFT = { 0, 0.5, 0, 0.5 },
  TOPRIGHT = { 0.5, 1, 0, 0.5 },
  BOTTOMLEFT = { 0, 0.5, 0.5, 1 },
  BOTTOMRIGHT = { 0.5, 1, 0.5, 1 },
}
local Shape = {}
Shape.__index = Shape
S.Shape = Shape
S.shapes = setmetatable({}, { __mode = "k" }) -- every shape, laid out again on a theme switch

-- The ring whose line stays about one pixel wide at a corner of r pixels (tools/make_media.py).
function S.RingFor(r)
  if r <= 4 then
    return S.RINGS.S
  elseif r <= 7 then
    return S.RINGS.M
  end
  return S.RINGS.L
end

function Shape:Radius()
  local r = self.radius
  if r == "pill" then
    r = math.floor((self.frame:GetHeight() or 0) / 2)
  elseif type(r) == "string" then
    r = S.RadiusOf(self.frame, r) or 0
  end
  r = r or 0
  local w, h = self.frame:GetWidth() or 0, self.frame:GetHeight() or 0
  if w > 0 and h > 0 then
    r = math.min(r, math.floor(math.min(w, h) / 2)) -- a small frame never folds over itself
  end
  return math.max(0, r)
end

-- A corner radius by its name as a frame sees it: the suite's (S.SHAPE), or for a frame of a look
-- of its own (S.SetFramePreset) the theme's radii under that look's own.
function S.RadiusOf(frame, key)
  local id = S.anyLook and frame and S.LookOf and S.LookOf(frame) or nil
  if not id or id == S.LookId() then
    return S.SHAPE[key]
  end
  local own = S.LOOKS[id] and S.LOOKS[id].shape or {}
  if own[key] then
    return own[key]
  end
  if key == "tile" then
    return own.radiusSmall or themeShape.radiusSmall or S.SHAPE.radiusSmall
  end
  local theme = themeShape[key]
  if theme == nil then
    return S.SHAPE[key]
  end
  return theme
end

function Shape:Rounded(corner)
  local c = self.corners
  if c == "top" then
    return corner == "TOPLEFT" or corner == "TOPRIGHT"
  elseif c == "bottom" then
    return corner == "BOTTOMLEFT" or corner == "BOTTOMRIGHT"
  end
  return true
end

function Shape:Piece(i)
  local t = self.pieces[i]
  if not t then
    t = self.frame:CreateTexture(nil, self.layer)
    self.pieces[i] = t
    local c = self.color
    if c then
      t:SetVertexColor(c[1], c[2], c[3], c[4])
    end
  end
  return t
end

local function band(t, f, p1, x1, y1, p2, x2, y2)
  t:SetTexture(S.WHITE)
  t:SetTexCoord(0, 1, 0, 1)
  t:ClearAllPoints()
  t:SetPoint(p1, f, p1, x1, y1)
  t:SetPoint(p2, f, p2, x2, y2)
end

-- Lays the pieces out for the current radius (after a theme switch, a pill's new height).
function Shape:Layout()
  local f, r = self.frame, self:Radius()
  self.r = r
  for i, corner in ipairs(CORNERS) do
    local t = self:Piece(i)
    t:ClearAllPoints()
    if r > 0 and self:Rounded(corner) then
      t:SetTexture(self.outline and S.RingFor(r) or S.DISC)
      local q = QUARTER[corner]
      t:SetTexCoord(q[1], q[2], q[3], q[4])
      t:SetSize(r, r)
      t:SetPoint(corner, f, corner, 0, 0)
      t:Show()
    elseif r > 0 and not self.outline then -- a square corner of a fill
      t:SetTexture(S.WHITE)
      t:SetTexCoord(0, 1, 0, 1)
      t:SetSize(r, r)
      t:SetPoint(corner, f, corner, 0, 0)
      t:Show()
    else
      t:Hide()
    end
  end
  if self.outline then
    -- the straight lines stop where a rounded corner starts
    local tl = (r > 0 and self:Rounded("TOPLEFT")) and r or 0
    local tr = (r > 0 and self:Rounded("TOPRIGHT")) and r or 0
    local bl = (r > 0 and self:Rounded("BOTTOMLEFT")) and r or 0
    local br = (r > 0 and self:Rounded("BOTTOMRIGHT")) and r or 0
    local top, bottom, left, right = self:Piece(5), self:Piece(6), self:Piece(7), self:Piece(8)
    band(top, f, "TOPLEFT", tl, 0, "TOPRIGHT", -tr, 0)
    top:SetHeight(1)
    band(bottom, f, "BOTTOMLEFT", bl, 0, "BOTTOMRIGHT", -br, 0)
    bottom:SetHeight(1)
    band(left, f, "TOPLEFT", 0, -tl, "BOTTOMLEFT", 0, bl)
    left:SetWidth(1)
    band(right, f, "TOPRIGHT", 0, -tr, "BOTTOMRIGHT", 0, br)
    right:SetWidth(1)
    for i = 5, 8 do
      self.pieces[i]:Show()
    end
  else
    -- the middle band runs the full height; the side bands fill between the corners
    band(self:Piece(5), f, "TOPLEFT", r, 0, "BOTTOMRIGHT", -r, 0)
    local left, right = self:Piece(6), self:Piece(7)
    band(left, f, "TOPLEFT", 0, -r, "BOTTOMLEFT", 0, r)
    left:SetWidth(r)
    band(right, f, "TOPRIGHT", 0, -r, "BOTTOMRIGHT", 0, r)
    right:SetWidth(r)
    self.pieces[5]:Show()
    if r > 0 then
      left:Show()
      right:Show()
    else
      left:Hide()
      right:Hide()
    end
  end
  if self.hidden then
    self:Hide()
  end
end

function Shape:SetVertexColor(r, g, b, a)
  local c = self.color or {}
  c[1], c[2], c[3], c[4] = r, g, b, a or 1
  self.color = c
  for _, t in ipairs(self.pieces) do
    t:SetVertexColor(r, g, b, a or 1)
  end
end

function Shape:GetVertexColor()
  local c = self.color or { 1, 1, 1, 1 }
  return c[1], c[2], c[3], c[4]
end

function Shape:SetAlpha(a)
  for _, t in ipairs(self.pieces) do
    t:SetAlpha(a)
  end
end

function Shape:Show()
  self.hidden = nil
  self:Layout()
end

function Shape:Hide()
  self.hidden = true
  for _, t in ipairs(self.pieces) do
    t:Hide()
  end
end

function Shape:IsShown()
  return not self.hidden
end

local function newShape(frame, color, radius, layer, corners, outline)
  local shape = setmetatable({
    frame = frame,
    radius = radius or "radius",
    layer = layer,
    corners = corners or "all",
    outline = outline,
    pieces = {},
  }, Shape)
  S.shapes[shape] = true
  shape:Layout()
  S.tint(shape, color)
  return shape
end

-- A rounded fill of the frame in a token colour.
function S.roundFill(frame, color, radius, layer, corners)
  return newShape(frame, color or S.C.bg, radius, layer or "BACKGROUND", corners, false)
end

-- A rounded 1 px outline of the frame in a token colour.
function S.roundEdges(frame, color, radius, corners)
  return newShape(frame, color or S.C.line, radius, "BORDER", corners, true)
end

function S.setEdges(edges, c, alpha)
  if getmetatable(edges) == Shape then
    S.tint(edges, c, alpha)
    return
  end
  for _, e in pairs(edges) do
    S.tint(e, c, alpha)
  end
end

-- A window, menu or panel: a rounded fill with a rounded outline (the theme's radius).
function S.panel(frame, color, radius)
  frame.bg = S.roundFill(frame, color or S.C.bg, radius or "radius")
  frame.edges = S.roundEdges(frame, S.C.line, radius or "radius")
  return frame
end

-- Button tips ("an information text on every button of every addon,
-- shown after one second of hovering, the time set globally"). A widget carries `tip`: a string,
-- or a function(widget) returning the title and an optional second line. S.TipEnter starts the
-- wait, S.TipLeave cancels it; the kit's buttons call both. The delay comes from Core's General
-- page (`tipDelay`, seconds, default 1; `tips` off shows none). A widget with `tipNow` is an icon
-- without words (the map's layer bar): its tip is its name and shows at once (owner, retail
-- 31.10.2026: "needs to be superfast - really immediately - if you search for something").
local tipToken = 0

function S.TipDelay()
  local core = ns.core
  local profile = core and core.db and core.db.profile
  if profile and profile.tips == false then
    return nil
  end
  return profile and tonumber(profile.tipDelay) or 1
end

local function showTip(widget)
  local tip = widget.tip
  if not tip or not GameTooltip then
    return
  end
  local title, text
  if type(tip) == "function" then
    title, text = tip(widget)
  else
    title = tip
  end
  if not title or title == "" then
    return
  end
  GameTooltip:SetOwner(widget, "ANCHOR_TOP")
  local c = S.C.tipText
  GameTooltip:AddLine(title, c[1], c[2], c[3], true)
  if text and text ~= "" then
    c = S.C.tipDim
    GameTooltip:AddLine(text, c[1], c[2], c[3], true)
  end
  GameTooltip:Show()
  if GameTooltip.Raise then
    GameTooltip:Raise() -- over a window on top (Window.TOP_STRATA shares the tooltip's strata)
  end
  widget.tipShown = true
end

function S.TipEnter(widget)
  tipToken = tipToken + 1
  if not widget.tip then
    return
  end
  local delay = S.TipDelay()
  if not delay then
    return
  end
  if delay <= 0 or widget.tipNow then
    showTip(widget)
    return
  end
  local token = tipToken
  C_Timer.After(delay, function()
    if token == tipToken then -- still on the same widget: no leave, no other enter
      showTip(widget)
    end
  end)
end

function S.TipLeave(widget)
  tipToken = tipToken + 1
  if widget.tipShown then
    widget.tipShown = nil
    if GameTooltip then
      GameTooltip:Hide()
    end
  end
end

-- Flat button with a label: since ADR 0046 a declared action without a pictogram (the look
-- draws it; `width` stays the app's, the label centred). `accent` makes it the primary one.
function S.button(parent, label, width, height, accent)
  local b = S.action(parent, {
    label = label or "",
    boxed = true,
    primary = accent or nil,
    width = width or 80,
    row = (height or 20) <= 20 or nil,
  })
  b.labelToken = accent and "accent" or "text"
  return b
end
-- A coloured button with a symbol:
-- the face in a theme colour (`token`), the kind's tile left of the label; as wide as it needs
-- unless `width` is given. Hover brightens the face.
S.TILE_FACE_ALPHA, S.TILE_FACE_HOVER = 0.35, 0.55
function S.tileButton(parent, label, kind, token, width, height)
  height = height or 22
  local b = CreateFrame("Button", nil, parent)
  local color = S.C[token or "accent"] or S.C.accent
  b.token = token or "accent"
  b.face = S.roundFill(b, color, "radiusSmall")
  S.tint(b.face, color, S.TILE_FACE_ALPHA)
  b.edges = S.roundEdges(b, color, "radiusSmall")
  S.setEdges(b.edges, color, 0.9)
  local icon = kind and B.UI.IconTexture and B.UI.IconTexture(kind) or nil
  local left = 6
  if icon then
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(icon)
    b.icon:SetSize(height - 6, height - 6)
    b.icon:SetPoint("LEFT", 4, 0)
    left = height
  end
  b.label = S.text(b, 12, S.C.text)
  b.label:SetPoint("LEFT", left, 0)
  b.label:SetJustifyH("LEFT")
  b.label:SetText(label or "")
  local w = b.label:GetStringWidth() or 0
  if w == 0 then
    w = #(label or "") * 6
  end
  b:SetSize(width or (left + w + 8), height)
  b:SetScript("OnEnter", function(self)
    S.tint(self.face, S.C[self.token] or S.C.accent, S.TILE_FACE_HOVER)
    S.TipEnter(self)
  end)
  b:SetScript("OnLeave", function(self)
    S.tint(self.face, S.C[self.token] or S.C.accent, S.TILE_FACE_ALPHA)
    S.TipLeave(self)
  end)
  function b.SetLabel(self, text)
    self.label:SetText(text)
  end
  return b
end

-- The text keys of a box (ADR 0045, Bastians.TextKeys): `key` went down while `box` had focus.
-- opts = { shell = function() -> bool (the readline set), extra = { [key] = op } (Ctrl keys of
-- the box's own), onOp = function(box, op) -> true when the box did the op itself }; `state`
-- keeps the kill text between keys. The result is computed from the text before the key and set
-- on the next frame, so it is right whether or not the client handles the key as well. Returns
-- the op or nil.
function S.TextKey(box, key, opts, state)
  local ctrl = IsControlKeyDown and IsControlKeyDown()
  local alt = IsAltKeyDown and IsAltKeyDown()
  local shift = IsShiftKeyDown and IsShiftKeyDown()
  local selecting = ctrl and shift and B.TextKeys.SELECT[key]
  if
    state
    and not selecting
    and key ~= "LSHIFT"
    and key ~= "RSHIFT"
    and key ~= "LCTRL"
    and key ~= "RCTRL"
  then
    state.anchor = nil -- any other key ends a word selection
  end
  if not (ctrl or alt) then
    return nil
  end
  opts = opts or {}
  local shell = opts.shell and opts.shell() or false
  local op = B.TextKeys.Op(key, ctrl, alt, shell, opts.extra, shift)
  if not op then
    return nil
  end
  if selecting then
    -- Ctrl+Shift+Left/Right: the selection from where it started to the next word's edge
    local text = box:GetText() or ""
    local cursor = type(box.GetCursorPosition) == "function" and box:GetCursorPosition() or #text
    state = state or {}
    if not state.anchor or state.at ~= cursor then
      state.anchor = cursor -- a click moved the cursor: a new selection starts there
    end
    local _, to = B.TextKeys.Edit(op, text, cursor)
    local anchor = state.anchor
    state.at = to
    C_Timer.After(0, function()
      box:SetCursorPosition(to)
      box:HighlightText(math.min(anchor, to), math.max(anchor, to))
    end)
    return op
  end
  if opts.onOp and opts.onOp(box, op) then
    return op
  end
  local text = box:GetText() or ""
  local cursor = type(box.GetCursorPosition) == "function" and box:GetCursorPosition() or #text
  local newText, newCursor, killed = B.TextKeys.Edit(op, text, cursor, state and state.kill)
  if not newText then
    return nil
  end
  if killed and state then
    state.kill = killed
  end
  C_Timer.After(0, function()
    if newText ~= (box:GetText() or "") then
      box:SetText(newText)
      -- our own boxes hear it as typed: a box that searches only on typing (the book's) follows
      local typed = state and state.own and box:GetScript("OnTextChanged")
      if typed then
        typed(box, true)
      end
    end
    box:SetCursorPosition(newCursor)
    box:HighlightText(newCursor, newCursor)
  end)
  return op
end

-- The kit's handlers of a box stay when an app sets its own script (an app's SetScript of
-- OnKeyDown would else drop the text keys): `kit` = { [script] = handler }, run before the app's.
-- Only for our own frames; the game's boxes take a HookScript.
local function keepKitScripts(box, kit)
  local setScript = box.SetScript
  box.SetScript = function(self, name, fn)
    local mine = kit[name]
    if mine then
      return setScript(self, name, function(...)
        mine(...)
        if fn then
          return fn(...)
        end
      end)
    end
    return setScript(self, name, fn)
  end
  for name, fn in pairs(kit) do
    setScript(box, name, fn)
  end
end

-- The Windows and Word keys on one of our boxes (the kit's search boxes have them); opts as
-- S.TextKey's.
function S.EditKeys(box, opts)
  local state = { own = true }
  keepKitScripts(box, {
    OnKeyDown = function(self, key)
      S.TextKey(self, key, opts, state)
    end,
  })
  return box
end

-- A search box's query (ADR 0045): the box's text compiled with its fields (`box.queryOpts`,
-- set by the box's app: { fields = ... }). A broken query colours the edges.
function S.BoxQuery(box)
  local q = B.Query.Compile(box.plainText and "" or (box:GetText() or ""), box.queryOpts)
  box.queryError = q.error
  if q.error then
    S.setEdges(box.edges, S.Tok(box, "bad"), 0.9)
  elseif box:HasFocus() then
    S.setEdges(box.edges, S.Tok(box, "accent"), 0.8)
  else
    S.setEdges(box.edges, S.Tok(box, "line"))
  end
  return q
end

-- The syntax on the box's tooltip: the help lines, the box's fields (`box.queryFields`, words for
-- the player such as "level, zone"), the error of its query.
function S.SearchTip(box)
  if box.plainText then
    return nil
  end
  local L = ns.L
  local lines = {}
  for _, line in ipairs(B.Query.HELP) do
    lines[#lines + 1] = L[line]
  end
  if box.queryFields then
    lines[#lines + 1] = string.format(L["Fields: %s (field:word, level>30)"], box.queryFields)
  end
  if box.queryError then
    lines[#lines + 1] = S.H.bad .. L[B.Query.ERRORS[box.queryError]] .. "|r"
  end
  return L["Search syntax"], table.concat(lines, "\n")
end

-- Search box: flat field with a hint text while empty and a clear button (ASCII "x", see CLAUDE.md §12).
-- `plainText`: a text field, not a search (no syntax tooltip, no query look; the text keys stay).
function S.search(parent, hint, plainText)
  local box = CreateFrame("EditBox", nil, parent)
  box.plainText = plainText or nil
  box:SetHeight(22)
  box:SetAutoFocus(false)
  box:SetFont(S.font(), S.size(12), "")
  S.fonts[box] = 12
  S.ink(box, S.C.text)
  box:SetTextInsets(8, 22, 0, 0)
  box.face = S.roundFill(box, S.C.panel, "radiusSmall")
  box.edges = S.roundEdges(box, S.C.line, "radiusSmall")
  box.hint = S.text(box, 12, S.C.dim)
  box.hint:SetPoint("LEFT", 8, 0)
  box.hint:SetText(hint or "")
  box.clear = CreateFrame("Button", nil, box)
  box.clear:SetSize(18, 18)
  box.clear:SetPoint("RIGHT", -2, 0)
  box.clear.label = S.text(box.clear, 14, S.C.dim)
  box.clear.label:SetPoint("CENTER")
  box.clear.label:SetText("x")
  box.clear:SetScript("OnClick", function()
    box:SetText("")
    box:ClearFocus()
  end)
  box.clear:Hide()
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  -- the text keys and the query's look stay when the box's app sets its own scripts (ADR 0045)
  local state = { own = true }
  keepKitScripts(box, {
    OnKeyDown = function(self, key)
      S.TextKey(self, key, nil, state)
    end,
    OnTextChanged = function(self)
      S.BoxQuery(self)
    end,
    OnEditFocusGained = function(self)
      S.BoxQuery(self)
    end,
    OnEditFocusLost = function(self)
      S.BoxQuery(self)
    end,
  })
  box.tip = S.SearchTip
  box:HookScript("OnEnter", S.TipEnter)
  box:HookScript("OnLeave", S.TipLeave)
  return box
end

-- A slim scroll bar that follows a ScrollFrame; mouse wheel on the frame, the thumb can be dragged.
-- `onScroll` is called after every change so a virtual list can re-render.
function S.scrollbar(scroll, parent, onScroll)
  local track = CreateFrame("Frame", nil, parent)
  track:SetWidth(4)
  track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
  track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
  S.fill(track, S.C.track)
  local thumb = CreateFrame("Frame", nil, track)
  thumb:SetWidth(4)
  thumb.tex = S.fill(thumb, S.C.accent)
  thumb.tex:SetAlpha(0.6)
  thumb:EnableMouse(true)
  track.thumb = thumb
  track.total = 0 -- content height, set by the owner (virtual lists do not size a scroll child)

  local function range()
    local view = scroll:GetHeight() or 0
    return math.max(0, track.total - view), view
  end

  function track.SetTotal(total)
    track.total = total or 0
    track.Update()
  end

  function track.Update()
    local rng, view = range()
    if rng <= 0 or view <= 0 then
      thumb:Hide()
      if (scroll:GetVerticalScroll() or 0) ~= 0 then
        scroll:SetVerticalScroll(0)
      end
      return
    end
    thumb:Show()
    local h = math.max(20, view * view / track.total)
    local off = scroll:GetVerticalScroll() or 0
    if off > rng then
      off = rng
      scroll:SetVerticalScroll(off)
    end
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -(view - h) * off / rng)
  end

  function track.ScrollTo(off)
    local rng = range()
    off = math.min(rng, math.max(0, off))
    scroll:SetVerticalScroll(off)
    track.Update()
    if onScroll then
      onScroll(off)
    end
  end

  function track.ScrollBy(delta)
    track.ScrollTo((scroll:GetVerticalScroll() or 0) + delta)
  end

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta)
    track.ScrollBy(-delta * 54)
  end)

  thumb:SetScript("OnMouseDown", function(self)
    local _, cy = GetCursorPosition()
    self.startY = cy / (self:GetEffectiveScale() or 1)
    self.startOff = scroll:GetVerticalScroll() or 0
    self:SetScript("OnUpdate", function(me)
      local _, y = GetCursorPosition()
      y = y / (me:GetEffectiveScale() or 1)
      local rng, view = range()
      local free = math.max(1, view - (me:GetHeight() or 20))
      track.ScrollTo(me.startOff + (me.startY - y) * rng / free)
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  return track
end
