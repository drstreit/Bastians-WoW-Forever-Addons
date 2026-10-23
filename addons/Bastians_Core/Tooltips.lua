-- Tooltip host (core-contracts §7): hooks unit, item and object tooltips once through Compat and renders the
-- tooltip rows of every registered detail section. Cached by the registry; under 0.2 ms when cached.
local _, ns = ...
local B = ns.B

local MAX_LINES_DEFAULT = 6 -- target of, top drops, quest givers (guide gaps, 23.10.2026)
local S = ns.Style -- our tooltip lines: the theme's tipDim and tipText (ST3)

local function maxLines()
  local core = ns.core
  return core and core.db and core.db.profile.tooltipLines or MAX_LINES_DEFAULT
end

local function refFor(info)
  if info.kind == "unit" then
    if info.guid and not string.match(info.guid, "^Creature") and not string.match(info.guid, "^Vehicle") then
      return nil -- players and pets have no entity
    end
    return info.id and ("npc:" .. info.id) or nil
  elseif info.kind == "item" then
    return info.id and ("item:" .. info.id) or nil
  elseif info.kind == "object" then
    -- by id only, never by the tooltip's name: on Forever 70532 it is a secret value (Z2)
    if info.guid and not string.match(info.guid, "^GameObject") then
      return nil
    end
    return info.id and ("object:" .. info.id) or nil
  end
  return nil
end

-- Adds the rows for the entity under the mouse; `tooltip.bastiansRef` marks a processed tooltip.
local function render(tooltip, info)
  local ref = refFor(info)
  if not ref or tooltip.bastiansRef == ref then
    return
  end
  tooltip.bastiansRef = ref
  local rows = B:GetTooltipRows(ref)
  local limit = maxLines()
  for i = 1, math.min(#rows, limit) do
    local row = rows[i]
    local value = B.UI.FormatValue(row.value, row.valueKind)
    local text = (row.icon and B.UI.InlineTexture(row.icon, 12) or "") .. (row.text or "")
    if value then
      tooltip:AddDoubleLine(
        text,
        value,
        S.C.tipDim[1],
        S.C.tipDim[2],
        S.C.tipDim[3],
        S.C.tipText[1],
        S.C.tipText[2],
        S.C.tipText[3]
      )
    else
      tooltip:AddLine(text, S.C.tipDim[1], S.C.tipDim[2], S.C.tipDim[3])
    end
  end
  if #rows > limit then
    tooltip:AddLine(
      string.format("%s (%d)", ns.L["more in the Browser"], #rows - limit),
      S.C.tipDim[1],
      S.C.tipDim[2],
      S.C.tipDim[3]
    )
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  B.Compat.HookTooltip("unit", render)
  B.Compat.HookTooltip("item", render)
  B.Compat.HookTooltip("object", render) -- gathering nodes and chests (guide gaps, 23.10.2026)
  GameTooltip:HookScript("OnHide", function(tt)
    tt.bastiansRef = nil
  end)
end)

ns.Tooltips = { render = render, refFor = refFor }
