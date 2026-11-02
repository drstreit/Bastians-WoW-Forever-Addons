-- Bastian's Helpers, tooltips (helpers.md "Tooltips"): the item and NPC ids and the item level
-- of what can be worn, one dim line each at the end of the game's tooltip.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Helpers = ns.Helpers

local Tooltips = {}
ns.Tooltips = Tooltips
Helpers.Tooltips = Tooltips

-- Equip locations without an item level worth reading.
Tooltips.NO_LEVEL =
  { [""] = true, INVTYPE_BAG = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_NON_EQUIP = true }

-- The lines for an item or a unit tooltip: { text } in order; empty for anything else.
function Tooltips.Lines(info)
  local out = {}
  if not (info and info.id) then
    return out
  end
  if info.kind == "item" then
    if Helpers.On("tooltipItemLevel") then
      local it = B.Compat.GetItemInfo(info.link or info.id)
      if it and it.level and not Tooltips.NO_LEVEL[it.equipLoc or ""] then
        out[#out + 1] = string.format(L["Item level %d"], it.level)
      end
    end
    if Helpers.On("tooltipIDs") then
      out[#out + 1] = string.format(L["Item ID %d"], info.id)
    end
  elseif info.kind == "unit" and Helpers.On("tooltipIDs") then
    local guid = info.guid
    if guid == nil or string.match(guid, "^Creature") or string.match(guid, "^Vehicle") then
      out[#out + 1] = string.format(L["NPC ID %d"], info.id)
    end
  end
  return out
end

local function render(tooltip, info)
  local key = info and info.kind and info.id and (info.kind .. ":" .. info.id)
  if not key or tooltip.bastiansHelpers == key then
    return
  end
  tooltip.bastiansHelpers = key
  for _, text in ipairs(Tooltips.Lines(info)) do
    S.TipLine(tooltip, text, "tipDim")
  end
end
Tooltips.render = render

-- Hooked once for the session (Compat keeps the hook); the switches are read at every tooltip.
function Tooltips.Attach()
  if Tooltips.hooked then
    return
  end
  Tooltips.hooked = true
  B.Compat.HookTooltip("item", render)
  B.Compat.HookTooltip("unit", render)
  if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnHide", function(tt)
      tt.bastiansHelpers = nil
    end)
  end
end
