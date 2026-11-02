-- UI kit: icon kinds -> texture paths and inline texture strings. Backslashes are doubled on purpose:
-- Lua 5.1 drops unknown escapes silently, which is the bug AHSyncGuide Rows.lua shipped (CLAUDE.md §5).
local _, ns = ...
local B = ns.B

local S = ns.Style
local GLYPHS = "Interface\\AddOns\\Bastians_Core\\Media\\Glyphs\\"
-- the tiles: every symbol on a rounded tile in its category's
-- colour, the style of the addon icons; what the icons show since. The bare glyphs stay for
-- whoever needs one tinted (B.UI.GLYPH_PATHS).
local TILES = "Interface\\AddOns\\Bastians_Core\\Media\\Tiles\\"

-- kind -> texture path: the suite's own glyphs (ST4, ; drawn by
-- tools/glyphs.py, written by tools/make_media.py). ~~Vanilla-era Blizzard icons~~ until then.
-- Item icons stay the game's (they show the item itself).
local KINDS = {
  "quest",
  "questActive",
  "done",
  "waiting",
  "never",
  "mob",
  "mob_claw",
  "mob_dagger",
  "mob_bow",
  "mob_staff",
  "mob_axe",
  "mob_mace",
  "rare",
  "herb",
  "mine",
  "treasure",
  "fish",
  "zone",
  "trainer",
  "vendor",
  "service",
  "innkeeper",
  "flight",
  "banker",
  "auctioneer",
  "repair",
  "item",
  "gold",
  "route",
  "spot",
  "other",
  "hide",
  "voice",
  "open",
  "copy",
  "waypoint",
  "settings",
  "cloth",
  "bandage",
  "keep",
  "arrow",
  "leather",
  "ledger",
  "chain",
  "object",
  "grave",
  "note",
  "tale", -- Bastian's Library, a tale's journal (28.10.2026)
  "buttons", -- the box of the minimap buttons (Bastian's minimap, 28.10.2026)
  "play", -- the Orbiter's hub (voice.md, 01.11.2026)
  "pause",
  "stop",
  "replay",
  "orbit", -- Bastian's Orbiter
  -- the action pictograms of the widget set (ADR 0046, 01.11.2026), drawn like the glyphs
  "bookmark",
  "lock",
  "close",
  "filter",
  "clear",
  "invite",
  "more",
  "plus",
  "junk",
  "back",
  "track",
  "share",
  "dock",
  "undock",
  "quiet",
  "layers",
  "scan",
  "rename",
  "remove",
  "help",
  -- the app marks (plan-second-wave.md S1, the icon sheet approved 01.11.2026): one pictogram per
  -- app on its coloured tile; Strategies keeps "ledger", the Orbiter "orbit", the Library "tale"
  "app_suite",
  "app_quests",
  "app_map",
  "app_browser",
  "app_gold",
  "app_route",
  "app_notes",
  "app_alts",
  "app_helpers",
  "app_chat",
  "app_gestures",
  "app_data",
  -- the campfire (plan-second-wave.md S5, 02.11.2026): a shared fire's pin, the camp ring, the app
  "campfire",
  "app_campfire",
}
local PATHS = {}
local GLYPH_PATHS = {}
local GLYPH_OF = {} -- path -> kind, the bare glyphs only: a tile carries its colours itself
local KIND_OF = {} -- path -> kind, tiles and glyphs
for _, kind in ipairs(KINDS) do
  PATHS[kind] = TILES .. kind
  GLYPH_PATHS[kind] = GLYPHS .. kind
  GLYPH_OF[GLYPHS .. kind] = kind
  KIND_OF[GLYPHS .. kind], KIND_OF[TILES .. kind] = kind, kind
end
B.UI.ICON_PATHS = PATHS
B.UI.GLYPH_PATHS = GLYPH_PATHS

-- The theme token that tints a kind (a glyph is white: SetVertexColor colours it); nil keeps it
-- white with its dark rim, readable on dark and light schemes alike.
local TINT = {
  quest = "gold",
  questActive = "gold",
  done = "on",
  waiting = "dim",
  never = "bad",
  mob = "bad",
  mob_claw = "bad",
  mob_dagger = "bad",
  mob_bow = "bad",
  mob_staff = "bad",
  mob_axe = "bad",
  mob_mace = "bad",
  rare = "rare",
  herb = "good",
  mine = "warn",
  treasure = "gold",
  fish = "water",
  flight = "water",
  zone = "accent",
  route = "accent",
  spot = "accent",
  open = "accent",
  waypoint = "accent",
  gold = "gold",
  banker = "gold",
  auctioneer = "gold",
  hide = "dim",
  other = "dim",
  ledger = "gold", -- the Strategies book's button
  leather = "warn",
  grave = "dim",
  note = "gold",
}
B.UI.ICON_TINT = TINT

-- The owner's easter egg: the monster glyph is the weapon of the player's class (class ids of
-- both clients). Crossed swords for the rest.
local CLASS_MOB = {
  [2] = "mob_mace", -- paladin
  [3] = "mob_bow", -- hunter
  [4] = "mob_dagger", -- rogue
  [5] = "mob_staff", -- priest
  [7] = "mob_axe", -- shaman
  [8] = "mob_staff", -- mage
  [9] = "mob_staff", -- warlock
  [10] = "mob_staff", -- monk
  [11] = "mob_claw", -- druid
  [12] = "mob_dagger", -- demon hunter
  [13] = "mob_claw", -- evoker
}
local mobKind
function B.UI.MobKind()
  if not mobKind then
    -- remembered once the class is known (a call before login keeps asking)
    local facts = B.Compat.GetPlayerFacts and B.Compat.GetPlayerFacts() or nil
    if facts and facts.classID then
      mobKind = CLASS_MOB[facts.classID] or "mob"
    end
  end
  return mobKind or "mob"
end

-- The kind of a texture path when it is one of the suite's bare glyphs (tinted by the theme),
-- else nil.
function B.UI.GlyphKind(path)
  return path and GLYPH_OF[path] or nil
end

-- The kind of any of the suite's icon paths, a tile or a glyph, else nil.
function B.UI.IconKind(path)
  return path and KIND_OF[path] or nil
end

-- The colour of a kind in the active theme, or nil for a plain white glyph.
function B.UI.IconTint(kind)
  local token = kind and TINT[kind]
  return token and S.C[token] or nil
end

-- Puts an icon on a texture: a glyph gets its kind's tint from the theme (kept for a theme
-- switch), any other texture (an item's own icon) its own colours.
function B.UI.PaintIcon(tex, path)
  tex:SetTexture(path)
  local tint = B.UI.IconTint(B.UI.GlyphKind(path))
  if tint then
    S.tint(tex, tint)
  else
    S.untint(tex)
  end
end

-- The kind tiles' groups (ADR 0046): a kind's tint token names its group; the group's colour is a
-- theme token (tileGold ... tileGrey) so the tiles follow the scheme.
local GROUP_OF_TINT = {
  gold = "tileGold",
  bad = "tileRed",
  accent = "tileTeal",
  good = "tileGreen",
  water = "tileBlue",
  rare = "tilePurple",
  warn = "tileBrown",
  on = "tileGreen",
  dim = "tileGrey",
}
local GROUP = {
  item = "tileBrown",
  cloth = "tileBrown",
  object = "tileGrey",
  trainer = "tileBlue",
  vendor = "tileGold",
  service = "tileBlue",
  innkeeper = "tilePurple",
  repair = "tileGrey",
  mine = "tileBrown",
  chain = "tileGold",
  tale = "tilePurple",
  keep = "tileTeal",
  buttons = "tileTeal",
  -- the app marks' tiles (the icon sheet's colours)
  app_suite = "tileTeal",
  app_quests = "tileGold",
  app_map = "tileGreen",
  app_browser = "tileBlue",
  app_gold = "tileGold",
  app_route = "tileTeal",
  app_notes = "tileGold",
  app_alts = "tileBlue",
  app_helpers = "tileGrey",
  app_chat = "tileTeal",
  app_gestures = "tileGreen",
  app_data = "tileGrey",
  campfire = "tileGold",
  app_campfire = "tileGold",
}
function B.UI.TileGroup(kind)
  if kind == "mob" then
    kind = B.UI.MobKind()
  end
  return GROUP[kind] or GROUP_OF_TINT[TINT[kind] or ""] or "tileGrey"
end

-- The action pictograms (ADR 0046, Bastians.UI.Pictogram(name)): the suite's own icons for the
-- widget set, drawn by tools/glyphs.py like the glyphs (E4, 01.11.2026). A name that says the
-- same as a glyph maps to it; a name without any answers nil and the button draws its text alone.
-- (Until 01.11.2026 this was B.UI.Icon(name), shadowed by the inline B.UI.Icon(kind, size) below:
-- every button reserved the space and drew nothing, the words sat right of an empty gap.)
local PICTOGRAM_GLYPH = {
  map = "zone",
  route = "route",
  note = "note",
  copy = "copy",
  open = "open",
  search = "open",
  settings = "settings",
  send = "arrow",
  forward = "arrow",
  check = "done",
  sound = "voice",
  locate = "spot",
  page = "ledger",
  messenger = "service",
  chat = "service",
  quest = "quest",
  gold = "gold",
  waypoint = "waypoint",
  hide = "hide",
}
B.UI.PICTOGRAMS_TO_DRAW = {} -- every name of the canvas is drawn (E4, 01.11.2026)
function B.UI.Pictogram(name)
  local glyph = PICTOGRAM_GLYPH[name]
  if glyph then
    return GLYPH_PATHS[glyph]
  end
  if type(name) == "number" or (type(name) == "string" and name:find("\\", 1, true)) then
    return name -- a texture of its own (a registered action's icon, an item's)
  end
  return GLYPH_PATHS[name] -- a glyph kind named directly (zone, note, ...)
end

-- The suite's own mark (its minimap button, its LibDataBroker launcher, its Addon Compartment
-- entry): one kind, so the suite has one face (plan-launch-review.md I3): the compass star of the
-- app marks (plan-second-wave.md S1, 01.11.2026; the magnifier until then).
B.UI.SUITE_ICON = "app_suite"

-- Bastians.UI.AppIcon(module) -> the one icon of an app of the suite (`icon` in B.APPS, the
-- identity record, plan-launch-review.md I1): its minimap button, its feed and the hub draw this
-- and nothing else; nil for a module that is no app of the suite.
function B.UI.AppIcon(module)
  local settings = B.UI.Settings
  local app = settings and settings.AppByModule and settings.AppByModule(module)
  return app and app.icon and B.UI.IconTexture(app.icon) or nil
end

-- Bastians.UI.IconTexture(kind) -> path or fileID for SetTexture; nil for an unknown kind.
function B.UI.IconTexture(kind)
  if kind == "mob" then
    return PATHS[B.UI.MobKind()]
  end
  return PATHS[kind]
end

-- An inline texture escape; a tinted glyph carries its colour in the escape (r, g, b 0..255).
local function inline(path, size)
  local tint = B.UI.IconTint(B.UI.GlyphKind(path))
  if tint then
    return string.format(
      "|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t ",
      path,
      size,
      size,
      tint[1] * 255 + 0.5,
      tint[2] * 255 + 0.5,
      tint[3] * 255 + 0.5
    )
  end
  return string.format("|T%s:%d:%d|t ", tostring(path), size, size)
end

-- Bastians.UI.Icon(kind, size) -> inline "|T...:12:12|t " string for text, "" when unknown.
function B.UI.Icon(kind, size)
  local path = B.UI.IconTexture(kind)
  if not path then
    return ""
  end
  return inline(path, size or 12)
end

-- Inline string for any texture path or file ID (item icons from GetItemInfo are file IDs).
function B.UI.InlineTexture(texture, size)
  if not texture then
    return ""
  end
  return inline(texture, size or 12)
end
