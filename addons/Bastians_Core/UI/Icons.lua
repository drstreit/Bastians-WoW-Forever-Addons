-- UI kit: icon kinds -> texture paths and inline texture strings. Backslashes are doubled on purpose:
-- Lua 5.1 drops unknown escapes silently, which is the bug AHSyncGuide Rows.lua shipped (CLAUDE.md §5).
local _, ns = ...
local B = ns.B

local S = ns.Style
local GLYPHS = "Interface\\AddOns\\Bastians_Core\\Media\\Glyphs\\"

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
}
local PATHS = {}
local GLYPH_OF = {} -- path -> kind
for _, kind in ipairs(KINDS) do
  PATHS[kind] = GLYPHS .. kind
  GLYPH_OF[GLYPHS .. kind] = kind
end
B.UI.ICON_PATHS = PATHS

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

-- The kind of a texture path when it is one of the suite's glyphs, else nil.
function B.UI.GlyphKind(path)
  return path and GLYPH_OF[path] or nil
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
