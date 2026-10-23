-- UI kit: Bastians.UI.EntityMenu(ref, anchor, ctx): the right-click menu every app uses (core-contracts §5).
-- A flat popup listing the actions from the registry for this entity; no Blizzard menu templates.
local _, ns = ...
local B = ns.B
local S = ns.Style

local ITEM_H, WIDTH, MAX_WIDTH = 20, 180, 380
local menu

local function build()
  menu = CreateFrame("Frame", "BastiansEntityMenu", UIParent)
  menu:SetFrameStrata("TOOLTIP")
  menu:SetWidth(WIDTH)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  S.panel(menu, S.C.panel)
  -- opaque: the rows under the menu showed through
  S.tint(menu.bg, S.C.panel, 1)
  menu.title = S.text(menu, 12, S.C.dim)
  menu.title:SetPoint("TOPLEFT", 8, -5)
  menu.title:SetPoint("RIGHT", -8, 0)
  menu.title:SetWordWrap(false)
  menu.items = {}
  menu:SetScript("OnLeave", function(self)
    if not self:IsMouseOver() then
      self:Hide()
    end
  end)
  menu:Hide()
  return menu
end

local function item(i)
  local b = menu.items[i]
  if b then
    return b
  end
  b = CreateFrame("Button", nil, menu)
  b:SetHeight(ITEM_H)
  b:SetPoint("LEFT", 1, 0)
  b:SetPoint("RIGHT", -1, 0)
  b.hl = S.fill(b, S.C.hover, "ARTWORK")
  b.hl:Hide()
  b.label = S.text(b, 12)
  b.label:SetPoint("LEFT", 8, 0)
  b.label:SetPoint("RIGHT", -8, 0)
  b.label:SetWordWrap(false) -- one line per entry: long labels wrapped over the next entries
  b:SetScript("OnEnter", function(self)
    self.hl:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self.hl:Hide()
  end)
  b:SetScript("OnClick", function(self)
    if self.disabled then
      return -- greyed: the menu stays
    end
    menu:Hide()
    if self.action then
      B:RunAction(self.action.id, menu.ref, menu.ctx)
    end
  end)
  menu.items[i] = b
  return b
end

-- Shows the menu for ref next to `anchor`. Returns the number of actions shown (0: nothing to show).
function B.UI.EntityMenu(ref, anchor, ctx)
  if B.UI.GestureRecent and B.UI.GestureRecent() then
    return 0 -- the right button just finished a back or forward drag, not a click
  end
  ctx = ctx or { source = "menu" }
  ctx.button = "RightButton"
  local actions = B:GetActions(ref, ctx)
  if #actions == 0 then
    if menu then
      menu:Hide()
    end
    return 0
  end
  menu = menu or build()
  menu.ref, menu.ctx = ref, ctx
  local e = B:Entity(ref)
  menu.title:SetText(e:Name() or ref)
  local width = WIDTH
  for i, action in ipairs(actions) do
    local b = item(i)
    b.action = action
    b.disabled = not B:ActionEnabled(action, ref, ctx)
    b.label:SetText((action.icon and B.UI.InlineTexture(action.icon, 12) or "") .. action.label)
    local col = b.disabled and S.C.dim or S.C.text
    b.label:SetTextColor(col[1], col[2], col[3])
    width = math.max(width, (b.label:GetStringWidth() or 0) + 24) -- the widest entry sets it
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 1, -(22 + (i - 1) * ITEM_H))
    b:SetPoint("RIGHT", -1, 0)
    b:Show()
  end
  for i = #actions + 1, #menu.items do
    menu.items[i]:Hide()
  end
  menu:SetHeight(26 + #actions * ITEM_H)
  menu:SetWidth(math.min(MAX_WIDTH, width))
  menu:ClearAllPoints()
  if anchor then
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  else
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
  end
  menu:Show()
  menu:Raise()
  return #actions
end

function B.UI.HideEntityMenu()
  if menu then
    menu:Hide()
  end
end

function B.UI.EntityMenuFrame()
  return menu
end
