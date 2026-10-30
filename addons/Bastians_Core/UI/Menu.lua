-- UI kit: Bastians.UI.Menu(anchor, title, items, owner): a flat popup of the caller's own entries
-- (the entity menu lists registry actions; this one lists what an app hands it, R26.16: the Map's
-- player button). items = { { label, icon, header = bool, disabled = bool, on = bool, onClick = fn } };
-- a header is a dim line that cannot be clicked, `on` marks the chosen entry with a lit background
--. One shared frame; it hides when the mouse leaves it,
-- when its anchor hides (the anchor's window closed), on Esc, and on a click elsewhere (owner, retail
-- 27.10.2026, R27.3: the Map's player menu stayed open forever after Esc closed the map).
local _, ns = ...
local B = ns.B
local S = ns.Style

local ITEM_H, WIDTH, MAX_WIDTH = 20, 200, 400
local menu

local function build()
  menu = CreateFrame("Frame", "BastiansMenu", UIParent)
  menu:SetFrameStrata("TOOLTIP")
  menu:SetWidth(WIDTH)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  S.panel(menu, S.C.panel)
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
  -- a click elsewhere closes it, as the game's menus do; listened for only while it is shown
  menu:SetScript("OnShow", function(self)
    pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
  end)
  menu:SetScript("OnHide", function(self)
    pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
  end)
  menu:SetScript("OnEvent", function(self)
    local anchor = self.anchor
    if not self:IsMouseOver() and not (anchor and anchor:IsMouseOver()) then
      self:Hide()
    end
  end)
  table.insert(UISpecialFrames, "BastiansMenu") -- Esc closes it
  menu:Hide()
  return menu
end

-- The menu goes when its anchor goes (a child of a window hides with it, and OnHide reaches it).
local function follow(anchor)
  if not anchor or anchor.bastiansMenuHooked then
    return
  end
  anchor.bastiansMenuHooked = true
  anchor:HookScript("OnHide", function(self)
    if menu and menu.anchor == self then
      menu:Hide()
    end
  end)
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
  b.sel = S.fill(b, S.C.accent, "BACKGROUND")
  S.tint(b.sel, S.C.accent, 0.25)
  b.sel:Hide()
  b.hl = S.fill(b, S.C.hover, "ARTWORK")
  b.hl:Hide()
  b.label = S.text(b, 12)
  b.label:SetPoint("LEFT", 8, 0)
  b.label:SetPoint("RIGHT", -8, 0)
  b.label:SetWordWrap(false)
  b:SetScript("OnEnter", function(self)
    if not self.still then
      self.hl:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.hl:Hide()
  end)
  b:SetScript("OnClick", function(self)
    if self.still then
      return -- a header or a greyed entry: the menu stays
    end
    menu:Hide()
    if self.entry.onClick then
      ns.safecall(menu.owner or ns.coreOwner, self.entry.onClick)
    end
  end)
  menu.items[i] = b
  return b
end

-- Shows the items under `anchor`; returns how many it shows.
function B.UI.Menu(anchor, title, items, owner)
  menu = menu or build()
  menu.owner = owner
  menu.anchor = anchor
  follow(anchor)
  menu.title:SetText(title or "")
  local width = WIDTH
  for i, e in ipairs(items or {}) do
    local b = item(i)
    b.entry = e
    b.still = e.header or e.disabled or false
    local text = (e.icon and not e.header and B.UI.InlineTexture(e.icon, 12) or "") .. (e.label or "")
    b.label:SetText(text)
    local col = (e.header or e.disabled) and S.C.dim or S.C.text
    b.label:SetTextColor(col[1], col[2], col[3])
    b.label:SetJustifyH(e.header and "CENTER" or "LEFT")
    b.sel:SetShown(e.on and not e.header or false)
    width = math.max(width, (b.label:GetStringWidth() or 0) + 24)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 1, -(22 + (i - 1) * ITEM_H))
    b:SetPoint("RIGHT", -1, 0)
    b:Show()
  end
  local n = #(items or {})
  for i = n + 1, #menu.items do
    menu.items[i]:Hide()
  end
  menu:SetHeight(26 + n * ITEM_H)
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
  return n
end

function B.UI.HideMenu()
  if menu then
    menu:Hide()
  end
end

function B.UI.MenuFrame()
  return menu
end
