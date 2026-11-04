-- Hand-written WoW API behaviour for the Lua tests (ADR 0006). Loaded before any addon file.
-- Every mocked behaviour is either verified in docs/forever-api.md or marked "assumed" here.
-- Strict by default: an unknown frame method or an unmocked documented API raises instead of returning nil,
-- so a typo or a missing mock never passes silently.
local client = _G.BASTIANS_TEST_CLIENT or "forever" -- set by the harness before this file runs
local Mock = {
  client = client,
  chat = {},
  errors = {},
  clock = 0,
  combat = false,
  frames = {},
  addons = {},
  loaded = {},
}
_G.Mock = Mock

-- ---------------------------------------------------------------------------------------------
-- Lua globals WoW adds (verified: identical on every client since 2004; assumed harmless)
-- ---------------------------------------------------------------------------------------------

function strsplit(sep, str, limit)
  local out = {}
  for piece in string.gmatch(str .. sep, "(.-)" .. sep:gsub("%p", "%%%0")) do
    out[#out + 1] = piece
    if limit and #out >= limit then
      break
    end
  end
  return unpack(out)
end
function strtrim(s)
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end
strlower, strupper, strlen, strsub, strfind, strmatch, format =
  string.lower, string.upper, string.len, string.sub, string.find, string.match, string.format
gsub, gmatch, strrep = string.gsub, string.gmatch, string.rep
tinsert, tremove, tconcat, sort = table.insert, table.remove, table.concat, table.sort
floor, ceil, abs, max, min = math.floor, math.ceil, math.abs, math.max, math.min
function wipe(t)
  for k in pairs(t) do
    t[k] = nil
  end
  return t
end
function tContains(t, v)
  for _, x in pairs(t) do
    if x == v then
      return true
    end
  end
  return false
end
function CopyTable(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and CopyTable(v) or v
  end
  return c
end
function Mixin(obj, ...)
  for i = 1, select("#", ...) do
    for k, v in pairs((select(i, ...))) do
      obj[k] = v
    end
  end
  return obj
end
function CreateFromMixins(...)
  return Mixin({}, ...)
end
function hooksecurefunc(tbl, name, fn)
  if type(tbl) == "string" then
    tbl, name, fn = _G, tbl, name
  end
  local orig = tbl[name]
  tbl[name] = function(...)
    local r = { orig(...) }
    fn(...)
    return unpack(r)
  end
end
function securecall(fn, ...)
  return fn(...)
end
-- retail family: CallbackHandler-1.0 dispatches through it (LibDataBroker's displays, ADR 0043)
function securecallfunction(fn, ...)
  return fn(...)
end
function issecurevariable()
  return false
end
local errorHandler = function(msg)
  Mock.errors[#Mock.errors + 1] = msg
end
function geterrorhandler()
  return errorHandler
end
function seterrorhandler(fn)
  errorHandler = fn
end
function debugstack()
  return debug.traceback()
end

-- ---------------------------------------------------------------------------------------------
-- Clock and timers (C_Timer verified on Forever: AHSyncGuide uses it; shape assumed as retail)
-- ---------------------------------------------------------------------------------------------

function GetTime()
  return Mock.clock
end
function GetTimePreciseSec()
  return Mock.clock
end
-- Mock CPU time: every call costs Mock.cpuStep ms (default 0), so budget loops can be tested.
Mock.cpu = 0
Mock.cpuStep = 0
function debugprofilestop()
  Mock.cpu = Mock.cpu + Mock.cpuStep
  return Mock.clock * 1000 + Mock.cpu
end
function GetServerTime()
  return 1760000000 + math.floor(Mock.clock)
end
function date(fmt, t)
  return os.date(fmt, t)
end
function time(t)
  return os.time(t) -- the client's time(): seconds since the epoch, local clock
end
function GetFramerate()
  return 60
end

local timers = {}
local function addTimer(delay, fn, iterations)
  local t = { at = Mock.clock + delay, fn = fn, delay = delay, left = iterations, cancelled = false }
  function t:Cancel()
    self.cancelled = true
  end
  function t:IsCancelled()
    return self.cancelled
  end
  timers[#timers + 1] = t
  return t
end
-- Timers still pending; `repeating` counts only tickers (tests check that nothing runs while idle).
function Mock.ActiveTimers(repeating)
  local n = 0
  for _, t in ipairs(timers) do
    if not t.cancelled and (not repeating or t.left > 1) then
      n = n + 1
    end
  end
  return n
end
C_Timer = {
  After = function(delay, fn)
    addTimer(delay, fn, 1)
  end,
  NewTimer = function(delay, fn)
    return addTimer(delay, fn, 1)
  end,
  NewTicker = function(delay, fn, iterations)
    return addTimer(delay, fn, iterations or math.huge)
  end,
}

-- Advance the clock; runs due timers in time order, then OnUpdate of shown frames once per 1/60 s.
function Mock.Advance(seconds)
  local target = Mock.clock + seconds
  while true do
    local nextT
    for _, t in ipairs(timers) do
      if not t.cancelled and t.at <= target and (not nextT or t.at < nextT.at) then
        nextT = t
      end
    end
    if not nextT then
      break
    end
    Mock.clock = nextT.at
    nextT.left = nextT.left - 1
    if nextT.left <= 0 then
      nextT.cancelled = true
    else
      nextT.at = nextT.at + nextT.delay
    end
    local ok, err = pcall(nextT.fn, nextT)
    if not ok then
      errorHandler(err)
    end
  end
  Mock.clock = target
end

function Mock.RunFrames(n, dt)
  dt = dt or 1 / 60
  for _ = 1, n or 1 do
    Mock.clock = Mock.clock + dt
    for _, f in ipairs(Mock.frames) do
      local onUpdate = f.scripts.OnUpdate
      if onUpdate and f:IsVisible() then
        local ok, err = pcall(onUpdate, f, dt)
        if not ok then
          errorHandler(err)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- Combat lockdown (taint rule, CLAUDE.md golden rule 6). Secure frames refuse changes in combat.
-- ---------------------------------------------------------------------------------------------

function InCombatLockdown()
  return Mock.combat
end
function UnitAffectingCombat()
  return Mock.combat
end
function Mock.SetCombat(on)
  if Mock.combat == on then
    return
  end
  Mock.combat = on
  Mock.Fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

-- ---------------------------------------------------------------------------------------------
-- Frames. Explicit method list; unknown methods raise (add them here with a citation).
-- ---------------------------------------------------------------------------------------------

local Region = {}
-- WoW methods are PascalCase: an unknown one raises. Lowercase keys are the mock's own data fields and may be nil.
Region.__index = function(self, key)
  local v = Region[key]
  if v ~= nil then
    return v
  end
  if type(key) == "string" and string.match(key, "^%u") then
    error(
      ("frame method '%s' is not mocked (%s); add it to tests/lua/mock/wow.lua"):format(
        key,
        rawget(self, "objectType")
      ),
      2
    )
  end
  return nil
end

local function protectedCheck(self, what)
  if self.protected and Mock.combat then
    error(
      ("ADDON_ACTION_BLOCKED: %s on secure frame %s in combat"):format(what, self:GetName() or "<anonymous>"),
      3
    )
  end
end

function Region:GetName()
  return self.name
end
function Region:GetObjectType()
  return self.objectType
end
function Region:IsObjectType(t)
  return self.objectType == t
end
function Region:GetParent()
  return self.parent
end
-- A new parent gives its strata to the frame unless the frame's strata is fixed (LibDBIcon fixes
-- its buttons' strata and level, ).
function Region:SetParent(p)
  self.parent = p
  if p and not self.fixedStrata and p.strata then
    self.strata = p.strata
  end
end
function Region:SetFixedFrameStrata(on)
  self.fixedStrata = on and true or false
end
function Region:HasFixedFrameStrata()
  return self.fixedStrata == true
end
function Region:SetFixedFrameLevel(on)
  self.fixedLevel = on and true or false
end
function Region:HasFixedFrameLevel()
  return self.fixedLevel == true
end
-- Show/Hide run the OnShow/OnHide scripts on a state change, as the client does.
function Region:Show()
  protectedCheck(self, "Show")
  if self.shown then
    return
  end
  self.shown = true
  local fn = self.scripts.OnShow
  if fn then
    fn(self)
  end
end
function Region:Hide()
  protectedCheck(self, "Hide")
  if not self.shown then
    return
  end
  self.shown = false
  local fn = self.scripts.OnHide
  if fn then
    fn(self)
  end
end
function Region:SetShown(b)
  if b then
    self:Show()
  else
    self:Hide()
  end
end
function Region:IsShown()
  return self.shown
end
function Region:IsVisible()
  local f = self
  while f do
    if not f.shown then
      return false
    end
    f = f.parent
  end
  return true
end
function Region:SetSize(w, h)
  self.width, self.height = w, h
end
function Region:GetSize()
  return self.width, self.height
end
function Region:SetWidth(w)
  self.width = w
end
function Region:SetHeight(h)
  self.height = h
end
function Region:GetWidth()
  return self.width
end
function Region:GetHeight()
  return self.height
end
function Region:SetPoint(point, a, b, c, d)
  protectedCheck(self, "SetPoint")
  local rel, relPoint, x, y
  if type(a) == "table" or type(a) == "string" then
    rel = a
    if type(b) == "string" then
      relPoint, x, y = b, c, d
    else
      relPoint, x, y = point, b, c
    end
  else
    rel, relPoint, x, y = self.parent, point, a, b
  end
  self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
end
function Region:ClearAllPoints()
  self.points = {}
end
function Region:GetNumPoints()
  return #self.points
end
function Region:GetPoint(i)
  local p = self.points[i or 1]
  if not p then
    return nil
  end
  return p.point, p.rel, p.relPoint, p.x, p.y
end
function Region:SetAllPoints(rel)
  self.points = { { point = "ALL", rel = rel or self.parent, relPoint = "ALL", x = 0, y = 0 } }
end
function Region:SetAlpha(a)
  self.alpha = a
end
function Region:GetAlpha()
  return self.alpha
end
function Region:SetScale(s)
  self.scale = s
end
function Region:GetScale()
  return self.scale
end
function Region:GetEffectiveScale()
  return self.scale
end
function Region:SetFrameStrata(s)
  self.strata = s
end
function Region:GetFrameStrata()
  return self.strata
end
function Region:SetFrameLevel(l)
  self.level = l
end
function Region:GetFrameLevel()
  return self.level
end
function Region:SetToplevel() end
function Region:Raise() end
function Region:Lower() end
function Region:SetClampedToScreen() end
function Region:SetClampRectInsets() end
function Region:SetMovable(b)
  self.movable = b
end
function Region:IsMovable()
  return self.movable
end
function Region:SetResizable(b)
  self.resizable = b
end
function Region:SetResizeBounds(minW, minH, maxW, maxH)
  self.resizeBounds = { minW, minH, maxW, maxH } -- for tests
end
function Region:GetResizeBounds()
  local b = self.resizeBounds or {}
  return b[1], b[2], b[3], b[4]
end
function Region:StartMoving() end
function Region:StopMovingOrSizing() end
function Region:StartSizing(edge)
  self.sizingEdge = edge or "BOTTOMRIGHT" -- the edge the grip drags, for tests
end
function Region:SetUserPlaced() end
function Region:EnableMouse(b)
  self.mouse = b
end
function Region:IsMouseEnabled()
  return self.mouse == true
end
function Region:EnableMouseWheel(b)
  self.mouseWheel = b
end
function Region:SetMouseClickEnabled() end
function Region:SetMouseMotionEnabled() end
function Region:RegisterForDrag(...)
  self.drag = { ... }
end
function Region:RegisterForClicks(...)
  self.clicks = { ... }
end
-- protected in combat on retail
function Region:SetPropagateKeyboardInput(on)
  if Mock.combat then
    error("ADDON_ACTION_BLOCKED: SetPropagateKeyboardInput in combat")
  end
  self.propagateKeys = on
end
function Region:EnableKeyboard() end
function Region:SetID(id)
  self.id = id
end
function Region:GetID()
  return self.id
end
function Region:SetAttribute(k, v)
  protectedCheck(self, "SetAttribute")
  self.attributes[k] = v
end
function Region:GetAttribute(k)
  return self.attributes[k]
end
function Region:IsProtected()
  return self.protected
end
function Region:GetLeft()
  return 0
end
function Region:GetRight()
  return self.width
end
function Region:GetTop()
  return self.height
end
function Region:GetBottom()
  return 0
end
function Region:GetCenter()
  return self.width / 2, self.height / 2
end
function Region:GetRect()
  return 0, 0, self.width, self.height
end
function Region:IsMouseOver()
  return Mock.mouseOverFrame == self -- a test sets Mock.mouseOverFrame to put the cursor on a frame
end
function Region:SetHitRectInsets() end
function Region:SetClipsChildren(on)
  self.clips = on and true or nil -- Mock.Layout clips what it lays out inside
end
function Region:SetIgnoreParentScale() end
function Region:SetIgnoreParentAlpha() end
-- the draw layer and sublevel as the client keeps them (R27.5: what covers what on one frame)
function Region:SetDrawLayer(layer, sublevel)
  self.layer, self.sublevel = layer, sublevel or 0
end
function Region:GetDrawLayer()
  return self.layer, self.sublevel or 0
end
-- Model frames (PlayerModel, DressUpModel; the Browser's portraits): what was shown, for tests.
-- the plate's width when the subject was set: a model set on a frame of no size stays empty
function Region:SetCreature(id)
  self.creature, self.unit, self.worn, self.item = id, nil, nil, nil
  self.plateWidthAtSet = self.parent and self.parent.width
end
function Region:SetItem(id)
  self.item, self.creature, self.unit, self.worn = id, nil, nil, nil
  self.plateWidthAtSet = self.parent and self.parent.width
end
function Region:SetCamDistanceScale(s)
  self.camDistance = s
end
function Region:SetUnit(unit)
  self.unit, self.creature, self.worn = unit, nil, {}
end
function Region:Undress()
  self.worn = {}
end
function Region:TryOn(link)
  self.worn = self.worn or {}
  self.worn[#self.worn + 1] = link
end
function Region:ClearModel()
  self.creature, self.unit, self.worn, self.item = nil, nil, nil, nil
end
function Region:SetFacing(f)
  self.facing = f
end
function Region:GetFacing()
  return self.facing or 0
end
function Region:SetBackdrop() end
function Region:SetBackdropColor() end
function Region:SetBackdropBorderColor() end

-- scripts. The client refuses script types an object does not have (verified 20.10.2026, Forever
-- 1.60.1.70450: Frame:SetScript("OnDoubleClick") errors; OnClick and OnDoubleClick are Button scripts).
local BUTTON_SCRIPTS = { OnClick = true, OnDoubleClick = true }
local BUTTON_TYPES = { Button = true, CheckButton = true, ItemButton = true }
function Region:SetScript(name, fn)
  if BUTTON_SCRIPTS[name] and not BUTTON_TYPES[self.objectType] then
    error(
      ("%s:SetScript(): Cannot assign script handler for '%s' (script type not supported by this object)"):format(
        tostring(self.objectType),
        string.lower(name)
      ),
      2
    )
  end
  self.scripts[name] = fn
end
function Region:GetScript(name)
  return self.scripts[name]
end
function Region:HasScript(name)
  return self.hasScripts[name] ~= false
end
function Region:HookScript(name, fn)
  local prev = self.scripts[name]
  self.scripts[name] = function(...)
    if prev then
      prev(...)
    end
    fn(...)
  end
end

-- events
-- an event the client does not know raises, as the game does (Mock.unknownEvents[ev] = true)
function Region:RegisterEvent(ev)
  if Mock.unknownEvents and Mock.unknownEvents[ev] then
    error('Attempt to register unknown event "' .. tostring(ev) .. '"', 2)
  end
  self.events[ev] = true
end
function Region:RegisterUnitEvent(ev)
  self.events[ev] = true
end
function Region:UnregisterEvent(ev)
  self.events[ev] = nil
end
function Region:UnregisterAllEvents()
  self.events = {}
end
function Region:IsEventRegistered(ev)
  return self.events[ev] == true
end

-- children
local newRegion
function Region:CreateTexture(name, layer, template, sublevel)
  local t = newRegion("Texture", name, self, template)
  t.layer, t.sublevel = layer or "ARTWORK", sublevel or 0
  return t
end
function Region:CreateFontString(name, layer, template)
  local s = newRegion("FontString", name, self, template)
  s.layer = layer
  return s
end
function Region:CreateMaskTexture(name)
  return newRegion("MaskTexture", name, self)
end
function Region:CreateAnimationGroup()
  local g = newRegion("AnimationGroup", nil, self)
  g.Play = function() end
  g.Stop = function() end
  g.IsPlaying = function()
    return false
  end
  g.CreateAnimation = function()
    return newRegion("Animation", nil, g)
  end
  return g
end
function Region:GetChildren()
  return unpack(self.children)
end
function Region:GetNumChildren()
  return #self.children
end
function Region:GetRegions()
  return unpack(self.regions)
end

-- Texture
function Region:SetTexture(tex)
  -- a file the client has not seen since it started (a new file in a known addon) is taken
  -- without an error, but GetTexture stays nil until a full restart (Forever, 22.10.2026)
  if Mock.unseen and tex and Mock.unseen[tex] then
    self.texture = nil
    return true
  end
  -- a test that draws the UI (render.py) says which addon files exist: a missing one stays nil
  if Mock.fileExists and type(tex) == "string" and not Mock.fileExists(tex) then
    self.texture = nil
    return true
  end
  self.texture = tex
  return true
end
function Region:GetTexture()
  return self.texture
end
function Region:SetAtlas(a)
  self.atlas = a
end
function Region:GetAtlas()
  return self.atlas
end
function Region:SetColorTexture(r, g, b, a)
  self.texture = nil
  self.color = { r, g, b, a }
end
function Region:SetVertexColor(r, g, b, a)
  self.vertexColor = { r, g, b, a }
end
function Region:GetVertexColor()
  return unpack(self.vertexColor or { 1, 1, 1, 1 })
end
function Region:SetTexCoord(...)
  self.texCoord = { ... }
end
function Region:GetTexCoord()
  return unpack(self.texCoord or { 0, 1, 0, 1 })
end
function Region:SetDesaturated(b)
  self.desaturated = b
end
function Region:SetBlendMode(m)
  self.blend = m
end
function Region:SetRotation(r)
  self.rotation = r
end
function Region:GetRotation()
  return self.rotation or 0
end
function Region:SetGradient() end
function Region:SetSnapToPixelGrid() end
function Region:SetTexelSnappingBias() end
function Region:AddMaskTexture(mask)
  self.masks = self.masks or {}
  self.masks[#self.masks + 1] = mask
end
function Region:RemoveMaskTexture(mask)
  for i, m in ipairs(self.masks or {}) do
    if m == mask then
      table.remove(self.masks, i)
      return
    end
  end
end
function Region:GetNumMaskTextures()
  return #(self.masks or {})
end
function Region:SetHorizTile() end
function Region:SetVertTile() end

-- FontString
function Region:SetText(t)
  -- the client refuses anything but a string, a number or nil (a quest's flags table stopped the
  -- Browser's tree in game, 22.10.2026); the mock refuses it the same way
  if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then
    error("Usage: SetText(text): text must be a string or a number, got " .. type(t), 2)
  end
  self.text = t == nil and "" or tostring(t)
  self.cursor = nil -- the client puts the cursor at the end
  -- an EditBox fires OnTextChanged(self, userInput = false) when its text is set by code (client behaviour)
  if self.objectType == "EditBox" then
    local fn = self.scripts.OnTextChanged
    if fn then
      fn(self, false)
    end
  end
end
function Region:GetText()
  return self.text
end
function Region:SetFormattedText(fmt, ...)
  self.text = string.format(fmt, ...)
end
function Region:SetFont(path, size, flags)
  self.font = { path, size, flags }
end
function Region:GetFont()
  return unpack(self.font or { "Fonts\\FRIZQT__.TTF", 12, "" })
end
function Region:SetFontObject(o)
  self.fontObject = o
end
function Region:GetFontObject()
  return self.fontObject
end
function Region:SetTextColor(r, g, b, a)
  self.textColor = { r, g, b, a }
end
function Region:GetTextColor()
  return unpack(self.textColor or { 1, 1, 1, 1 })
end
function Region:SetJustifyH(j)
  self.justifyH = j
end
function Region:SetJustifyV(j)
  self.justifyV = j
end
function Region:SetWordWrap(b)
  self.wordWrap = b
end
function Region:SetNonSpaceWrap() end
function Region:SetMaxLines(n)
  self.maxLines = n
end
function Region:SetShadowOffset(x, y)
  self.shadowX, self.shadowY = x, y
end
function Region:GetShadowOffset()
  return self.shadowX or 0, self.shadowY or 0
end
function Region:SetShadowColor() end
function Region:SetSpacing(n)
  self.spacing = n
end
function Region:GetSpacing()
  return self.spacing or 0
end
-- Mock.measure(text, fontPath, size, width, spacing) -> width, height: a test that lays out text
-- (the Library's pages) gives the font's real metrics (tests/lua/render.py); else a rough guess.
function Region:GetStringWidth()
  if Mock.measure and self.font then
    return (Mock.measure(self.text or "", self.font[1], self.font[2], 0, self.spacing or 0))
  end
  return (self.text and #self.text or 0) * 6
end
function Region:GetStringHeight()
  if Mock.measure and self.font then
    local _, h = Mock.measure(self.text or "", self.font[1], self.font[2], self.width or 0, self.spacing or 0)
    return h
  end
  return 12
end
-- Models (the Library's witness portrait): what was asked is kept
function Region:SetUnit(unit)
  self.modelUnit = unit
end
function Region:ClearModel()
  self.modelUnit = nil
end
function Region:SetPortraitZoom(z)
  self.portraitZoom = z
end
-- a model's animation (the skin's greetings, ADR 0034): the last one asked, and every one in order
function Region:HasAnimation()
  return true -- every model has every animation; a test sets its own on the model
end
function Region:SetAnimation(id)
  self.animation = id
  self.animations = self.animations or {}
  self.animations[#self.animations + 1] = id
end
function Region:GetWrappedWidth()
  return self:GetStringWidth()
end
function Region:SetIndentedWordWrap() end

-- Button
function Region:Click(button)
  local fn = self.scripts.OnClick
  if fn then
    fn(self, button or "LeftButton", false)
  end
end
function Region:SetNormalTexture(t)
  self.normalTexture = t
end
function Region:GetNormalTexture()
  return self.normalTexture
end
function Region:SetPushedTexture(t)
  self.pushedTexture = t
end
function Region:GetPushedTexture()
  return self.pushedTexture
end
function Region:SetHighlightTexture(t)
  self.highlightTexture = t
end
function Region:GetHighlightTexture()
  return self.highlightTexture
end
function Region:SetDisabledTexture() end
function Region:SetNormalFontObject() end
function Region:SetHighlightFontObject() end
function Region:GetFontString()
  self.fontString = self.fontString or self:CreateFontString()
  return self.fontString
end
function Region:Enable()
  self.enabled = true
end
function Region:Disable()
  self.enabled = false
end
function Region:IsEnabled()
  return self.enabled ~= false
end
function Region:SetEnabled(b)
  self.enabled = b
end
function Region:SetChecked(b)
  self.checked = b
end
function Region:GetChecked()
  return self.checked
end
function Region:SetButtonState() end
function Region:LockHighlight() end
function Region:UnlockHighlight() end

-- EditBox / Slider / ScrollFrame
function Region:SetAutoFocus() end
function Region:SetFocus()
  Mock.focus = self
end
function Region:ClearFocus()
  if Mock.focus == self then
    Mock.focus = nil
  end
end
function Region:HasFocus()
  return Mock.focus == self
end
function Region:SetCursorPosition(n)
  self.cursor = n
end
-- the cursor as a byte offset; the end of the text until something sets it (as after SetText)
function Region:GetCursorPosition()
  local text = self.text or ""
  return math.min(self.cursor or #text, #text)
end
function Region:HighlightText() end
function Region:SetTextInsets() end
function Region:SetMultiLine(on)
  self.multiLine = on and true or false
end
function Region:SetMaxLetters() end
function Region:SetAltArrowKeyMode(on)
  self.altArrowKeyMode = on
end
function Region:SetNumber(n)
  self.text = tostring(n)
end
function Region:GetNumber()
  return tonumber(self.text) or 0
end
function Region:SetMinMaxValues(a, b)
  self.minValue, self.maxValue = a, b
end
function Region:GetMinMaxValues()
  return self.minValue, self.maxValue
end
function Region:SetValue(v)
  self.value = v
  local fn = self.scripts.OnValueChanged
  if fn then
    fn(self, v, true)
  end
end
function Region:GetValue()
  return self.value
end
function Region:SetValueStep(s)
  self.step = s
end
function Region:SetObeyStepOnDrag() end
function Region:SetOrientation() end
function Region:SetThumbTexture(tex)
  self.thumb = self.thumb or newRegion("Texture", nil, self)
  self.thumb:SetTexture(tex)
end
function Region:GetThumbTexture()
  return self.thumb
end
function Region:SetStepsPerPage() end
function Region:SetScrollChild(c)
  self.scrollChild = c
  c.scrollParent = self -- Mock.Layout puts it at the scroll frame's top left
end
function Region:GetScrollChild()
  return self.scrollChild
end
function Region:SetVerticalScroll(v)
  self.verticalScroll = v
end
function Region:GetVerticalScroll()
  return self.verticalScroll or 0
end
function Region:GetVerticalScrollRange()
  return 0
end
function Region:UpdateScrollChildRect() end
function Region:SetHorizontalScroll() end

-- Cooldown frames (the Lore Orbit's progress ring): what was set, for tests.
function Region:SetCooldown(start, duration)
  self.cooldown = { start = start, duration = duration }
end
function Region:Clear()
  self.cooldown = nil
end
function Region:SetReverse(b)
  self.reverse = b
end
function Region:SetDrawEdge() end
function Region:SetDrawBling() end
function Region:SetHideCountdownNumbers() end
function Region:SetSwipeColor(r, g, b, a)
  self.swipeColor = { r, g, b, a }
end
-- StatusBar / Model: add when needed.

local anonymous = 0
newRegion = function(objectType, name, parent, template)
  local f = setmetatable({
    objectType = objectType,
    name = name,
    parent = parent,
    template = template,
    shown = true,
    width = 0,
    height = 0,
    alpha = 1,
    scale = 1,
    strata = "MEDIUM",
    level = parent and parent.level and parent.level + 1 or 0,
    points = {},
    scripts = {},
    hasScripts = {},
    events = {},
    attributes = {},
    children = {},
    regions = {},
    protected = template ~= nil and (string.find(template, "Secure") ~= nil),
  }, Region)
  if objectType == "Texture" or objectType == "FontString" or objectType == "MaskTexture" then
    if parent then
      parent.regions[#parent.regions + 1] = f
    end
  else
    if parent then
      parent.children[#parent.children + 1] = f
    end
    Mock.frames[#Mock.frames + 1] = f
  end
  if name then
    _G[name] = f
  else
    anonymous = anonymous + 1
    f.anonymousID = anonymous
  end
  return f
end

-- The game's window templates (Blizzard's SharedXML; the look's game frames, 31.10.2026): a test
-- sets Mock.templates[name] = true and CreateFrame builds the parts the suite uses; without it the
-- client knows no such template (C_XMLUtil.GetTemplateInfo answers nil, CreateFrame fails).
Mock.templates = {}
local TEMPLATE_PARTS = {
  PortraitFrameTemplate = function(f)
    f.Bg = f:CreateTexture(nil, "BACKGROUND")
    f.Bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    f.CloseButton = CreateFrame("Button", nil, f)
    f.TitleText = f:CreateFontString(nil, "OVERLAY")
    f.portrait = f:CreateTexture(nil, "OVERLAY")
    function f.SetTitle(self, text)
      self.TitleText:SetText(text)
    end
    function f.SetPortraitToAsset(self, path)
      self.portrait:SetTexture(path)
    end
  end,
  InsetFrameTemplate = function(f)
    f.Bg = f:CreateTexture(nil, "BACKGROUND")
    f.Bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble")
  end,
}
function CreateFrame(objectType, name, parent, template)
  if template and TEMPLATE_PARTS[template] and not Mock.templates[template] then
    error("CreateFrame: Couldn't find inherited node: " .. template, 2)
  end
  local f = newRegion(objectType or "Frame", name, parent, template)
  if template and TEMPLATE_PARTS[template] then
    TEMPLATE_PARTS[template](f)
  end
  return f
end
C_XMLUtil = C_XMLUtil or {}
C_XMLUtil.GetTemplateInfo = function(name)
  if TEMPLATE_PARTS[name] and not Mock.templates[name] then
    return nil
  end
  return { type = "Frame", width = 0, height = 0 }
end

UIParent = newRegion("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
WorldFrame = newRegion("Frame", "WorldFrame")
Minimap = newRegion("Frame", "Minimap")
Minimap:SetSize(140, 140)
Mock.minimapZoom = 0
function Minimap:GetZoom()
  return Mock.minimapZoom
end
function Minimap:GetZoomLevels()
  return 6
end
-- the minimap's shape (Bastian's minimap squares it, Mini.lua)
function Minimap:SetMaskTexture(path)
  self.maskPath = path
end
function Minimap:SetZoom(zoom)
  -- the client fires MINIMAP_UPDATE_ZOOM when the zoom changes, on a later frame (an addon
  -- that probes the zoom from that event loops forever, seen on Forever 23.10.2026)
  local changed = Mock.minimapZoom ~= zoom
  Mock.minimapZoom = zoom
  if changed and not Mock.zoomEventPending then
    Mock.zoomEventPending = true
    C_Timer.After(1 / 60, function() -- the next frame
      Mock.zoomEventPending = nil
      Mock.Fire("MINIMAP_UPDATE_ZOOM")
    end)
  end
end

-- The game's world map (retail family; forever-api.md: GetCanvas and SetMapID work on Forever):
-- a frame with a canvas, a map id, data providers (MapCanvasDataProviderMixin) and ToggleWorldMap.
WorldMapFrame = newRegion("Frame", "WorldMapFrame")
WorldMapFrame:SetSize(1024, 768)
WorldMapFrame:Hide() -- the game's map starts closed
WorldMapFrame.ScrollContainer = newRegion("Frame", nil, WorldMapFrame)
WorldMapFrame.ScrollContainer.Child = newRegion("Frame", nil, WorldMapFrame.ScrollContainer)
WorldMapFrame.ScrollContainer.Child:SetSize(1002, 668)
WorldMapFrame.mapID = nil
WorldMapFrame.dataProviders = {}
function WorldMapFrame:GetCanvas()
  return self.ScrollContainer.Child
end
function WorldMapFrame:GetMapID()
  return self.mapID or Mock.playerMap
end
function WorldMapFrame:SetMapID(id)
  self.mapID = id
  for _, p in ipairs(self.dataProviders) do
    if p.OnMapChanged then
      p:OnMapChanged()
    end
  end
end
function WorldMapFrame:AddDataProvider(p)
  self.dataProviders[#self.dataProviders + 1] = p
  p:OnAdded(self)
  p:RefreshAllData()
end
function WorldMapFrame:RemoveDataProvider(p)
  for i, q in ipairs(self.dataProviders) do
    if q == p then
      table.remove(self.dataProviders, i)
      if p.OnRemoved then
        p:OnRemoved(self)
      end
      return
    end
  end
end
MapCanvasDataProviderMixin = {
  OnAdded = function(self, owner)
    self.owningMap = owner
  end,
  OnRemoved = function(self)
    self.owningMap = nil
  end,
  GetMap = function(self)
    return self.owningMap
  end,
  RemoveAllData = function() end,
  RefreshAllData = function() end,
  OnMapChanged = function(self)
    self:RefreshAllData()
  end,
}
function CreateFromMixins(...)
  local out = {}
  for i = 1, select("#", ...) do
    for k, v in pairs(select(i, ...)) do
      out[k] = v
    end
  end
  return out
end
function ToggleWorldMap()
  if WorldMapFrame:IsShown() then
    WorldMapFrame:Hide()
  else
    WorldMapFrame:Show()
  end
end
function GetScreenWidth()
  return 1920
end
function GetScreenHeight()
  return 1080
end
function GetCursorPosition()
  return Mock.cursorX or 960, Mock.cursorY or 540
end

-- Mouse buttons: Mock.SetMouseButton("RightButton", true) presses one (the window gestures poll it)
Mock.mouseDown = {}
function Mock.SetMouseButton(button, down)
  Mock.mouseDown[button or "LeftButton"] = down and true or nil
end
function IsMouseButtonDown(button)
  return Mock.mouseDown[button or "LeftButton"] == true
end
function GetMouseFocus()
  return Mock.mouseFocus
end
function IsShiftKeyDown()
  return Mock.shift or false
end
function IsControlKeyDown()
  return Mock.ctrl or false
end
function IsAltKeyDown()
  return Mock.alt or false
end
function IsModifierKeyDown()
  return IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()
end
-- the client's sound kits: what was played is kept (the skin's page sounds, ADR 0034)
Mock.kits = {}
function PlaySound(id)
  Mock.kits[#Mock.kits + 1] = id
end
SOUNDKIT = { IG_ABILITY_PAGE_TURN = 836, IG_QUEST_LOG_OPEN = 844 }
-- sounds: what was played is kept; like the client, willPlay and a handle for StopSound
Mock.sounds, Mock.stopped = {}, {}
function PlaySoundFile(file, channel)
  -- a test that knows which addon files exist (render.py) gets the client's answer for a missing one
  if Mock.fileExists and type(file) == "string" and not Mock.fileExists(file) then
    return false
  end
  Mock.sounds[#Mock.sounds + 1] = { file = file, channel = channel }
  return true, #Mock.sounds
end
function StopSound(handle)
  Mock.stopped[#Mock.stopped + 1] = handle
end
function CreateColor(r, g, b, a)
  return {
    r = r,
    g = g,
    b = b,
    a = a or 1,
    GetRGB = function(c)
      return c.r, c.g, c.b
    end,
    GetRGBA = function(c)
      return c.r, c.g, c.b, c.a
    end,
  }
end
GameFontNormal, GameFontHighlight, GameFontNormalSmall, GameFontHighlightSmall, GameFontDisable =
  {}, {}, {}, {}, {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
-- The client's font objects (GetFonts in both P1 dumps): names, each with GetFont -> path, size.
local function fontObject(path, size)
  return {
    GetFont = function()
      return path, size, ""
    end,
  }
end
GameFontNormal = fontObject("Fonts\\FRIZQT__.TTF", 12)
NumberFontNormal = fontObject("Fonts\\ARIALN.TTF", 14)
QuestFont = fontObject("Fonts\\K_Pagetext.TTF", 13)
SystemFont_Shadow_Huge3 = fontObject("Fonts\\2002B.TTF", 25)
function GetFonts()
  return { "GameFontNormal", "NumberFontNormal", "QuestFont", "SystemFont_Shadow_Huge3", "NoSuchFont" }
end

-- Event dispatch. Handlers run in registration order over a snapshot, so (un)registering inside is safe.
function Mock.Fire(event, ...)
  local snapshot = {}
  for _, f in ipairs(Mock.frames) do
    if f.events[event] then
      snapshot[#snapshot + 1] = f
    end
  end
  for _, f in ipairs(snapshot) do
    local fn = f.scripts.OnEvent
    if fn and f.events[event] then
      local ok, err = pcall(fn, f, event, ...)
      if not ok then
        errorHandler(err)
      end
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- Chat, slash commands
-- ---------------------------------------------------------------------------------------------

DEFAULT_CHAT_FRAME = newRegion("Frame", "DEFAULT_CHAT_FRAME")
function DEFAULT_CHAT_FRAME:AddMessage(msg)
  Mock.chat[#Mock.chat + 1] = tostring(msg)
end
ChatFrame1 = DEFAULT_CHAT_FRAME
-- Chat windows by tab name (GetChatWindowInfo, in both P1 dumps; assumed): window 1 is "General";
-- Mock.AddChatTab(i, name) opens another, whose lines land in Mock.chatTabs[name].
NUM_CHAT_WINDOWS = 10
Mock.chatWindows, Mock.chatTabs = { "General" }, {}
function GetChatWindowInfo(i)
  return Mock.chatWindows[i] or "", 14, 1, 1, 1, 1, i == 1, false, false, false
end
function Mock.AddChatTab(i, name)
  Mock.chatWindows[i] = name
  Mock.chatTabs[name] = {}
  local frame = newRegion("Frame", "ChatFrame" .. i)
  function frame:AddMessage(msg)
    local lines = Mock.chatTabs[name]
    lines[#lines + 1] = tostring(msg)
  end
  _G["ChatFrame" .. i] = frame
  return frame
end
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring((select(i, ...)))
  end
  Mock.chat[#Mock.chat + 1] = table.concat(parts, " ")
end
SlashCmdList = {}
UISpecialFrames = {} -- frames named here are hidden by the client when ESC is pressed (FrameXML, both clients)
function Mock.PressEscape()
  for _, name in ipairs(UISpecialFrames) do
    local f = _G[name]
    if f and f:IsShown() then
      f:Hide()
    end
  end
end
-- Run "/cmd rest" like the client: finds SLASH_<KEY>n globals, calls SlashCmdList[KEY](rest).
function Mock.Slash(line)
  local cmd, rest = string.match(line, "^(/%S+)%s*(.-)$")
  for key, fn in pairs(SlashCmdList) do
    local i = 1
    while _G["SLASH_" .. key .. i] do
      if string.lower(_G["SLASH_" .. key .. i]) == string.lower(cmd) then
        return fn(rest, DEFAULT_CHAT_FRAME.editBox)
      end
      i = i + 1
    end
  end
  error("unknown slash command " .. cmd)
end
function ChatEdit_GetActiveWindow() end
-- The chat's own edit box and its send (FrameXML ChatFrame, both clients; assumed): a line sent
-- through it lands in Mock.chatSent (Gestures runs the client's built-in commands this way). The
-- box is DEFAULT_CHAT_FRAME's only: no ChatFrame1EditBox global (the ChatSpike and the screen's
-- hide list look for that one and would take a bare mock box).
DEFAULT_CHAT_FRAME.editBox = CreateFrame("EditBox", nil, UIParent)
Mock.chatSent = {}
function ChatEdit_SendText(box)
  Mock.chatSent[#Mock.chatSent + 1] = box:GetText()
  box:SetText("")
end
-- The player's macros (GetNumMacros -> account, character; GetMacroInfo(i) -> name, icon, body;
-- the character's from MAX_ACCOUNT_MACROS + 1): Mock.macros.account / .character, one of each.
MAX_ACCOUNT_MACROS = 120
Mock.macros = {
  account = { { name = "Mount up", icon = 132261, body = "/cast [nomounted] Summon Charger" } },
  character = { { name = "Hearth home", icon = 134414, body = "/use Hearthstone" } },
}
local function macroAt(i)
  if i > MAX_ACCOUNT_MACROS then
    return Mock.macros.character[i - MAX_ACCOUNT_MACROS]
  end
  return Mock.macros.account[i]
end
function GetNumMacros()
  return #Mock.macros.account, #Mock.macros.character
end
function GetMacroInfo(i)
  local m = type(i) == "number" and macroAt(i) or nil
  if type(i) == "string" then
    return GetMacroInfo(GetMacroIndexByName(i))
  end
  if not m then
    return nil
  end
  return m.name, m.icon, m.body
end
function GetMacroIndexByName(name)
  for i, m in ipairs(Mock.macros.account) do
    if m.name == name then
      return i
    end
  end
  for i, m in ipairs(Mock.macros.character) do
    if m.name == name then
      return MAX_ACCOUNT_MACROS + i
    end
  end
  return 0
end
StaticPopupDialogs = {}
function StaticPopup_Show(which, ...)
  Mock.popup = { which = which, ... }
end
function StaticPopup_Hide() end
-- a duel, a trade, a group invite declined (Gestures' courtesy, plan-second-wave S7)
Mock.declined = {}
function CancelDuel()
  Mock.declined[#Mock.declined + 1] = "duel"
end
function CloseTrade()
  Mock.declined[#Mock.declined + 1] = "trade"
end
function DeclineGroup()
  Mock.declined[#Mock.declined + 1] = "invite"
end

-- ---------------------------------------------------------------------------------------------
-- Client facts (verified: GetBuildInfo on Forever beta 1.60.1.70450 interface 16001; retail assumed 12.1.5)
-- ---------------------------------------------------------------------------------------------

local builds = {
  forever = { "1.60.1", "70450", "Oct 16 2026", 16001 },
  retail = { "12.1.5", "70448", "Oct 16 2026", 120105 },
}
function GetBuildInfo()
  return unpack(builds[client])
end
function GetLocale()
  return Mock.locale or "enUS" -- a test sets Mock.locale before start() to boot a German client
end
function GetRealmName()
  return "Mock Realm"
end
function GetNormalizedRealmName()
  return "MockRealm"
end
function GetCurrentRegion()
  return client == "forever" and 110 or 3 -- verified 110 on the Forever beta (AHSync §20.1); retail EU = 3
end
function UnitName(unit)
  if unit == "player" then
    return Mock.playerName or "Mockchar" -- a test logs in another character of the account
  end
  return Mock.unitNames and Mock.unitNames[unit] or nil
end
-- Mock.classID switches the class (8 mage by default; 7 shaman, 11 druid for the teleports)
local CLASS_NAMES = { [7] = { "Shaman", "SHAMAN" }, [8] = { "Mage", "MAGE" }, [11] = { "Druid", "DRUID" } }
function UnitClass()
  local id = Mock.classID or 8
  local n = CLASS_NAMES[id] or { "Class", "CLASS" }
  return n[1], n[2], id
end
function UnitRace()
  return "Human", "Human", 1
end
function UnitLevel(unit)
  if unit == "player" then
    return Mock.level or 12
  end
  return Mock.unitLevels and Mock.unitLevels[unit] or 0
end
function UnitXP(unit)
  return unit == "player" and (Mock.xp or 0) or 0
end
function UnitXPMax(unit)
  return unit == "player" and (Mock.xpMax or 1000) or 0
end
function UnitFactionGroup()
  return "Alliance", "Alliance"
end
function UnitGUID(unit)
  return Mock.guids and Mock.guids[unit] or (unit == "player" and "Player-1-00000001" or nil)
end
function UnitExists(unit)
  return unit == "player" or (Mock.guids and Mock.guids[unit] ~= nil) or false
end
function UnitIsPlayer(unit)
  return unit == "player"
end
function UnitPosition(unit)
  local p = Mock.positions and Mock.positions[unit]
  if p then
    return p.y, p.x, p.z or 0, p.instance or 0
  end
end
-- Movement and the hearthstone: tests set Mock.unitSpeed, Mock.mounted, Mock.onTaxi, Mock.bindLocation
-- and Mock.itemCooldowns[itemID] = { start, duration }.
function GetUnitSpeed()
  return Mock.unitSpeed or 7
end
-- Secret values (Forever 70532, the retail family): Mock.Secret(v) behaves like the client's: any
-- compare, arithmetic, concatenation or index raises; issecretvalue tells it.
local SecretMT = {}
local function secretError()
  error("attempt to use a secret value", 2)
end
for _, ev in ipairs({
  "__index",
  "__newindex",
  "__add",
  "__sub",
  "__mul",
  "__div",
  "__mod",
  "__pow",
  "__unm",
  "__concat",
  "__len",
  "__lt",
  "__le",
  "__call",
}) do
  SecretMT[ev] = secretError
end
function Mock.Secret()
  return setmetatable({}, SecretMT)
end
function issecretvalue(v)
  return type(v) == "table" and getmetatable(v) == SecretMT
end
function IsMounted()
  return Mock.mounted or false
end
function UnitOnTaxi()
  return Mock.onTaxi or false
end
-- addon messages (N3): what was sent is kept in Mock.addonMessages; the prefixes registered
Mock.addonMessages, Mock.addonPrefixes = {}, {}
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function(prefix)
  Mock.addonPrefixes[prefix] = true
  return 0
end
C_ChatInfo.IsAddonMessagePrefixRegistered = function(prefix)
  return Mock.addonPrefixes[prefix] == true
end
C_ChatInfo.SendAddonMessage = function(prefix, text, channel, target)
  Mock.addonMessages[#Mock.addonMessages + 1] =
    { prefix = prefix, text = text, channel = channel, target = target }
end
-- custom channels (#20): Mock.channels[name] = number while joined; Mock.removedFrom[name] = frames
Mock.channels, Mock.removedFrom = {}, {}
function JoinTemporaryChannel(name)
  if not Mock.channels[name] then
    local n = 1
    for _, used in pairs(Mock.channels) do
      n = math.max(n, used + 1)
    end
    Mock.channels[name] = n
  end
end
function LeaveChannelByName(name)
  Mock.channels[name] = nil
end
function GetChannelName(name)
  local n = Mock.channels[name]
  if n then
    return n, name
  end
  return 0, nil
end
function ChatFrame_RemoveChannel(frame, name)
  Mock.removedFrom[name] = (Mock.removedFrom[name] or 0) + 1
end
-- death (R26.8): Mock.deathState "alive" | "dead" | "ghost"; Mock.corpse = { map, x, y }
Mock.deathState = "alive"
function UnitIsGhost(unit)
  return unit == "player" and Mock.deathState == "ghost"
end
function UnitIsDeadOrGhost(unit)
  if unit == "player" then
    return Mock.deathState ~= "alive"
  end
  return Mock.unitDead[unit] or false
end

-- The fact layer (library.md §4, Core Facts.lua): the player's state, other units, loot, readable
-- text, emotes, screenshots, the combat log. Tests set the Mock tables.
Mock.player = {} -- stealthed, swimming, submerged, falling, flying, resting, indoors
Mock.unitTargets = {} -- [unit] = the unit it targets ("player")
Mock.unitHealth = {} -- [unit] = { current, max }
Mock.unitDead = {}
Mock.unitLevels = {}
Mock.unitReaction = {} -- [unit] = 1 (hostile) .. 8
Mock.unitDistance = {} -- [unit] = yards from the player
Mock.auras = {} -- { { name, spellId } } the player's helpful auras
Mock.loot = { slots = {}, fishing = false } -- slots: { { item, name, quantity, source } }
Mock.itemText = nil -- { item, text, page } while a readable text is open
Mock.emotes = {} -- what DoEmote was asked
Mock.screenshots = 0
Mock.combatLogEvent = nil -- { n = 15, ... } what CombatLogGetCurrentEventInfo returns
function IsStealthed()
  return Mock.player.stealthed or false
end
function IsSwimming()
  return Mock.player.swimming or false
end
function IsSubmerged()
  return Mock.player.submerged or false
end
function IsFalling()
  return Mock.player.falling or false
end
function IsFlying()
  return Mock.player.flying or false
end
function IsResting()
  return Mock.player.resting or false
end
function IsIndoors()
  return Mock.player.indoors or false
end
function IsOutdoors()
  return not (Mock.player.indoors or false)
end
local function resolveUnit(u)
  if u == "player" then
    return "player"
  end
  local base = string.match(u, "^(.+)target$")
  if base then
    local t = Mock.unitTargets[base]
    return t and resolveUnit(t) or nil
  end
  return u
end
function UnitIsUnit(a, b)
  local ra, rb = resolveUnit(a), resolveUnit(b)
  return ra ~= nil and ra == rb
end
function UnitHealth(unit)
  local h = Mock.unitHealth[unit]
  return h and h[1] or 100
end
function UnitHealthMax(unit)
  local h = Mock.unitHealth[unit]
  return h and h[2] or 100
end
function UnitIsDead(unit)
  return Mock.unitDead[unit] or false
end
function UnitReaction(_, unit)
  return Mock.unitReaction[unit] or 4
end
local INTERACT_YARDS = { 28, 11.11, 9.9, 28 } -- inspect, trade, duel, follow
function CheckInteractDistance(unit, index)
  local d = Mock.unitDistance[unit]
  return d ~= nil and d <= (INTERACT_YARDS[index] or 28)
end
function GetNumLootItems()
  return #Mock.loot.slots
end
function GetLootSlotInfo(i)
  local s = Mock.loot.slots[i]
  if not s then
    return nil
  end
  return "icon", s.name or ("Item " .. s.item), s.quantity or 1, nil, 1, false, false
end
function GetLootSlotLink(i)
  local s = Mock.loot.slots[i]
  if not s then
    return nil
  end
  return "|cffffffff|Hitem:" .. s.item .. "::::::::1:::::|h[" .. (s.name or "Item") .. "]|h|r"
end
function GetLootSourceInfo(i)
  local s = Mock.loot.slots[i]
  if not s then
    return nil
  end
  return s.source, s.quantity or 1
end
function IsFishingLoot()
  return Mock.loot.fishing or false
end
function ItemTextGetItem()
  return Mock.itemText and Mock.itemText.item or nil
end
function ItemTextGetText()
  return Mock.itemText and Mock.itemText.text or nil
end
function ItemTextGetPage()
  return Mock.itemText and (Mock.itemText.page or 1) or nil
end
function DoEmote(token, target)
  Mock.emotes[#Mock.emotes + 1] = { token = token, target = target }
end
-- The client's emote list (FrameXML GlobalStrings, both clients' probe dumps): EMOTE<i>_TOKEN, its
-- slash commands EMOTE<i>_CMD1.., up to MAXEMOTEINDEX; ten of them here (Gestures' editor v2).
MAXEMOTEINDEX = 10
for i, e in ipairs({
  { "AGREE", "/agree" },
  { "AMAZE", "/amaze" },
  { "ANGRY", "/angry" },
  { "APOLOGIZE", "/apologize" },
  { "APPLAUD", "/applaud", "/bravo" },
  { "BASHFUL", "/bashful" },
  { "BEG", "/beg" },
  { "DANCE", "/dance" },
  { "WAVE", "/wave" },
  { "FLIRT", "/flirt" },
}) do
  _G["EMOTE" .. i .. "_TOKEN"] = e[1]
  for c = 2, #e do
    _G["EMOTE" .. i .. "_CMD" .. (c - 1)] = e[c]
  end
end
-- Chat messages the player sends (SendChatMessage(text, type, language, target); the language is
-- one the character knows, retail family, assumed on Forever); Mock.sentChat keeps them.
Mock.sentChat = {}
function SendChatMessage(text, chatType, language, target)
  Mock.sentChat[#Mock.sentChat + 1] =
    { text = text, type = chatType or "SAY", language = language, target = target }
end
-- The character's languages (GetNumLanguages, GetLanguageByIndex(i) -> name, id; assumed on
-- Forever): Mock.languages = { { name, id } }, a human's Common by default.
Mock.languages = { { "Common", 7 } }
function GetNumLanguages()
  return #Mock.languages
end
function GetLanguageByIndex(i)
  local l = Mock.languages[i]
  if not l then
    return nil
  end
  return l[1], l[2]
end
-- Group membership of a unit token (UnitInParty, UnitInRaid): Mock.groupUnits[unit] = true
Mock.groupUnits = {}
function UnitInParty(unit)
  return Mock.groupUnits[unit] == true
end
function UnitInRaid(unit)
  return Mock.groupUnits[unit] == true and Mock.groupSize > 5 and 1 or nil
end
function Screenshot()
  Mock.screenshots = Mock.screenshots + 1
end
function CombatLogGetCurrentEventInfo()
  local e = Mock.combatLogEvent
  if not e then
    return nil
  end
  return unpack(e, 1, e.n or #e)
end
C_UnitAuras = C_UnitAuras or {}
-- Mock.auras: the player's helpful auras { name, spellId, expirationTime, duration, sourceUnit };
-- Mock.unitAuras[unit] the same for another unit (a party member).
Mock.unitAuras = {}
C_UnitAuras.GetAuraDataByIndex = function(unit, i)
  local list = Mock.unitAuras[unit] or ((unit == nil or unit == "player") and Mock.auras) or {}
  local a = list[i]
  return a
      and {
        name = a.name,
        spellId = a.spellId,
        expirationTime = a.expirationTime or 0,
        duration = a.duration or 0,
        sourceUnit = a.sourceUnit,
      }
    or nil
end
C_DeathInfo = {
  GetCorpseMapPosition = function(mapID)
    local c = Mock.corpse
    if c and c.map == mapID then
      return CreateVector2D(c.x, c.y)
    end
  end,
}
Mock.bindLocation = "Goldshire"
function GetBindLocation()
  return Mock.bindLocation
end
Mock.itemCooldowns = {}
function GetItemCooldown(itemID)
  local c = Mock.itemCooldowns[itemID]
  if c then
    return c.start, c.duration, 1
  end
  return 0, 0, 1
end
C_Container = C_Container or {}
C_Container.GetItemCooldown = GetItemCooldown
-- teleports (R26.7): Mock.spells[spellID] = true (known), Mock.spellCooldowns[spellID] = { start,
-- duration }, Mock.worn[itemID] = true, Mock.toys[itemID] = true, Mock.itemSpells[itemID] = spellID
Mock.spells, Mock.spellCooldowns, Mock.worn, Mock.toys, Mock.itemSpells = {}, {}, {}, {}, {}
function IsLoggedIn() -- the character is in the world (Alts records at enable after a /reload)
  return true
end
C_SpellBook = C_SpellBook or {}
C_SpellBook.IsSpellKnown = function(spellID)
  return Mock.spells[spellID] == true
end
-- the spell book (alts.md "Knowledge"): one skill line holding every known spell of Mock.spells;
-- the open profession window: Mock.openRecipes[recipeID] = learned (nil: no window open)
Enum = Enum or {}
Enum.SpellBookSpellBank = Enum.SpellBookSpellBank or { Player = 0, Pet = 1 }
local function knownList()
  local ids = {}
  for id, known in pairs(Mock.spells) do
    if known then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end
C_SpellBook.GetNumSpellBookSkillLines = function()
  return 1
end
C_SpellBook.GetSpellBookSkillLineInfo = function()
  return { name = "General", itemIndexOffset = 0, numSpellBookItems = #knownList() }
end
C_SpellBook.GetSpellBookItemInfo = function(index)
  local id = knownList()[index]
  return id and { spellID = id, itemType = 1, isPassive = false } or nil
end
Mock.openRecipes = nil
C_TradeSkillUI = C_TradeSkillUI or {}
C_TradeSkillUI.GetAllRecipeIDs = function()
  local ids = {}
  for id in pairs(Mock.openRecipes or {}) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end
C_TradeSkillUI.GetRecipeInfo = function(id)
  local learned = Mock.openRecipes and Mock.openRecipes[id]
  if learned == nil then
    return nil
  end
  return { recipeID = id, learned = learned == true }
end
C_Spell = C_Spell or {}
-- spell names (retail's recipes come without names, 28.10.2026): Mock.spellNames[spellID]
Mock.spellNames = {}
C_Spell.GetSpellName = function(spellID)
  return Mock.spellNames[tonumber(spellID)]
end
C_Spell.GetSpellCooldown = function(spellID)
  local c = Mock.spellCooldowns[spellID]
  return { startTime = c and c.start or 0, duration = c and c.duration or 0, isEnabled = true, modRate = 1 }
end
function PlayerHasToy(itemID)
  return Mock.toys[itemID] == true
end
-- Reputation (C_Reputation.GetFactionDataByID documented on both clients; runtime assumed)
Mock.reputation = { [529] = { name = "Argent Dawn", reaction = 4, currentStanding = 0 } }
C_Reputation = C_Reputation or {}
C_Reputation.GetFactionDataByID = function(id)
  local r = Mock.reputation[id]
  if not r then
    return nil
  end
  return { factionID = id, name = r.name, reaction = r.reaction, currentStanding = r.currentStanding }
end
-- Professions: Forever's C_SkillInfo skill lines (documented Forever-only); retail's trade skill
-- lines. Test data: Mock.professions = { [name] = rank }.
Mock.professions = {}
if client == "forever" then
  C_SkillInfo = C_SkillInfo or {}
  local function lines()
    local out = { { skillName = "Professions", isHeader = true } }
    for name, rank in pairs(Mock.professions) do
      out[#out + 1] = { skillName = name, skillRank = rank, isHeader = false }
    end
    return out
  end
  C_SkillInfo.GetNumSkillLines = function()
    return #lines()
  end
  C_SkillInfo.GetSkillLineInfo = function(i)
    return lines()[i]
  end
else
  C_TradeSkillUI = C_TradeSkillUI or {}
  C_TradeSkillUI.GetAllProfessionTradeSkillLines = function()
    local ids = {}
    for _ in pairs(Mock.professions) do
      ids[#ids + 1] = 100 + #ids
    end
    return ids
  end
  C_TradeSkillUI.GetProfessionInfoBySkillLineID = function(id)
    local i = id - 100
    local names = {}
    for name in pairs(Mock.professions) do
      names[#names + 1] = name
    end
    table.sort(names)
    local name = names[i]
    return name and { professionName = name, skillLevel = Mock.professions[name], maxSkillLevel = 300 } or nil
  end
end
Mock.groupSize = 0
function GetNumGroupMembers()
  return Mock.groupSize
end
function IsInGroup()
  return Mock.groupSize > 0
end
function IsInRaid()
  return Mock.raid == true
end
function IsInGuild()
  return Mock.inGuild == true
end
C_FriendList = C_FriendList or {}
function C_FriendList.GetNumFriends()
  return #(Mock.friends or {})
end
function C_FriendList.GetFriendInfoByIndex(i)
  local f = (Mock.friends or {})[i]
  if not f then
    return nil
  end
  return { name = f.name, connected = f.online ~= false, area = f.area, level = f.level }
end
-- Mock.friends entries may carry className and guid (the Messenger's partner info); a test stub
-- that replaces the function finds the mock's one again as Mock.GetFriendInfo
function C_FriendList.GetFriendInfo(name)
  for _, f in ipairs(Mock.friends or {}) do
    if f.name == name then
      return {
        name = f.name,
        connected = f.online ~= false,
        area = f.area,
        level = f.level,
        className = f.className,
        guid = f.guid,
      }
    end
  end
  return nil
end
Mock.GetFriendInfo = C_FriendList.GetFriendInfo
-- Mock.players[guid] = { class = "Mage", file = "MAGE" } (Mock.guids maps units to GUIDs)
function GetPlayerInfoByGUID(guid)
  local g = Mock.players and Mock.players[guid]
  if not g then
    return nil
  end
  return g.class, g.file, "Human", "Human", 2, g.name, g.realm
end
-- Mock.guildRoster = { { name, level, className, zone, online, class }, ... }; Mock.guildName
function GetNumGuildMembers()
  return #(Mock.guildRoster or {})
end
function GetGuildRosterInfo(i)
  local m = (Mock.guildRoster or {})[i]
  if not m then
    return nil
  end
  return m.name, "Member", 1, m.level, m.className, m.zone, "", "", m.online ~= false, 0, m.class
end
function GetGuildInfo(unit)
  if unit == "player" then
    return Mock.guildName
  end
  return nil
end
function GetMaxPlayerLevel()
  return Mock.maxLevel
end
function GetMaxLevelForPlayerExpansion()
  return Mock.maxLevel -- nil: the client cannot tell (R26.11)
end
function GetZoneText()
  return Mock.zoneText or "Elwynn Forest"
end
function GetSubZoneText()
  return Mock.subZoneText or "Goldshire"
end
function GetRealZoneText()
  return GetZoneText()
end
function GetMinimapZoneText()
  return GetSubZoneText()
end
Mock.instanceType = "none" -- the second value of IsInInstance ("pvp" in a battleground)
function IsInInstance()
  return Mock.instanceType ~= "none", Mock.instanceType
end
-- the PvP flag (the Library's `pvp` trigger): Mock.pvp
function UnitIsPVP(unit)
  return unit == "player" and Mock.pvp == true
end
-- Mock.instanceMap (with Mock.instanceType "party" or "raid") is the dungeon's Map.db2 id
function GetInstanceInfo()
  if Mock.instanceType == "party" or Mock.instanceType == "raid" then
    return Mock.instanceName or "The Deadmines",
      Mock.instanceType,
      1,
      "Normal",
      5,
      0,
      false,
      Mock.instanceMap or 36
  end
  return "Azeroth", "none", 0, "", 0, 0, false, 0
end
function GetMoney()
  return Mock.money or 0
end
function GetPlayerFacing()
  return Mock.facing or 0
end
function ChatFrame_OpenChat(text)
  Mock.chatInput = text
end
-- The client's defaults the suite reads: the minimap's two zoom cvars (outdoors 0, indoors 1)
-- and no rotation.
Mock.cvars = { minimapZoom = "0", minimapInsideZoom = "1", rotateMinimap = "0" }
function GetCVar(name)
  return Mock.cvars and Mock.cvars[name]
end
function SetCVar(name, value)
  Mock.cvars = Mock.cvars or {}
  Mock.cvars[name] = value
end
function GetCVarBool(name)
  local v = GetCVar(name)
  return v == "1" or v == true
end
C_CVar = { GetCVar = GetCVar, SetCVar = SetCVar, GetCVarBool = GetCVarBool }
C_CVar = { GetCVar = GetCVar, SetCVar = SetCVar, GetCVarBool = GetCVarBool }
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage()
  return collectgarbage("count")
end
function GetAddOnCPUUsage()
  return 0
end
function ResetCPUUsage() end

-- ---------------------------------------------------------------------------------------------
-- Addons (C_AddOns verified in both docs, ADR 0009). The harness fills Mock.addons[name] = { meta, files }.
-- ---------------------------------------------------------------------------------------------

local function addonName(idOrName)
  if type(idOrName) == "number" then
    local i = 0
    for name in pairs(Mock.addons) do
      i = i + 1
      if i == idOrName then
        return name
      end
    end
    return nil
  end
  return idOrName
end
C_AddOns = {
  GetAddOnMetadata = function(name, field)
    local a = Mock.addons[addonName(name)]
    return a and a.meta[field] or nil
  end,
  IsAddOnLoaded = function(name)
    name = addonName(name)
    return Mock.loaded[name] == true, Mock.loaded[name] == true
  end,
  IsAddOnLoadOnDemand = function(name)
    local a = Mock.addons[addonName(name)]
    return a ~= nil and a.meta.LoadOnDemand == "1"
  end,
  DoesAddOnExist = function(name)
    return Mock.addons[addonName(name)] ~= nil
  end,
  GetAddOnEnableState = function(name)
    name = addonName(name)
    if not Mock.addons[name] or (Mock.disabledAddons and Mock.disabledAddons[name]) then
      return 0 -- Enum.AddOnEnableState.None
    end
    return 2 -- All
  end,
  GetNumAddOns = function()
    local n = 0
    for _ in pairs(Mock.addons) do
      n = n + 1
    end
    return n
  end,
  GetAddOnInfo = function(name)
    name = addonName(name)
    local a = Mock.addons[name]
    if not a then
      return nil, nil, nil, false, "MISSING"
    end
    return name, a.meta.Title, a.meta.Notes, true, Mock.loaded[name] and "" or "DEMAND_LOADED", "", false
  end,
  LoadAddOn = function(name)
    name = addonName(name)
    if not Mock.addons[name] then
      return false, "MISSING"
    end
    if Mock.loaded[name] then
      return true
    end
    if Mock.combat then
      return false, "INTERFACE_ACTION_BLOCKED" -- assumed: retail refuses LoadAddOn in combat for secure reasons
    end
    Mock.LoadAddOnFiles(name)
    return true
  end,
  EnableAddOn = function() end,
  DisableAddOn = function() end,
}
-- Loads an addon's files in TOC order with the (ADDON, ns) varargs and fires ADDON_LOADED, like the
-- client. Done in Lua on purpose: a Lua -> Python -> Lua round trip inside a coroutine confuses lupa.
-- Mock.addons[name].dir and .files come from the harness; Mock.onAddonLoaded is its pure-Python bookkeeping.
local function readFile(path)
  local f, err = io.open(path, "rb")
  if not f then
    error(err, 0)
  end
  local text = f:read("*a")
  f:close()
  return text
end
function Mock.LoadAddOnFiles(name)
  local a = Mock.addons[name]
  if not a then
    error("no addon " .. tostring(name) .. " is registered with the mock", 2)
  end
  if Mock.loaded[name] then
    return
  end
  local ns = {}
  Mock.missingFiles = Mock.missingFiles or {}
  for _, entry in ipairs(a.files) do
    local rel = string.gsub(entry, "\\", "/")
    local f = io.open(a.dir .. "/" .. rel, "rb")
    if not f then
      -- the client reports a missing listed file and keeps loading the others (assumed from experience)
      Mock.missingFiles[#Mock.missingFiles + 1] = name .. "/" .. rel
    else
      f:close()
      local chunk, err = loadstring(readFile(a.dir .. "/" .. rel), "@addons/" .. name .. "/" .. rel)
      if not chunk then
        error(err, 0)
      end
      chunk(name, ns)
    end
  end
  Mock.loaded[name] = true
  if Mock.onAddonLoaded then
    Mock.onAddonLoaded(name)
  end
  Mock.Fire("ADDON_LOADED", name)
end
-- legacy globals exist on both clients too; same behaviour
GetAddOnMetadata, IsAddOnLoaded, LoadAddOn, GetNumAddOns, GetAddOnInfo =
  C_AddOns.GetAddOnMetadata,
  C_AddOns.IsAddOnLoaded,
  C_AddOns.LoadAddOn,
  C_AddOns.GetNumAddOns,
  C_AddOns.GetAddOnInfo

-- ---------------------------------------------------------------------------------------------
-- Map (C_Map.GetBestMapForUnit / GetPlayerMapPosition / GetMapInfo verified on Forever, forever-api.md)
-- ---------------------------------------------------------------------------------------------

function CreateVector2D(x, y)
  local v = { x = x, y = y }
  function v:GetXY()
    return self.x, self.y
  end
  function v:SetXY(nx, ny)
    self.x, self.y = nx, ny
  end
  return v
end
-- Test data: Mock.maps[uiMapID] = { name, mapType, parent, c00 = {continent, x, y}, c11 = {...}, textures }
Mock.maps = {
  [947] = { name = "Azeroth", mapType = 1, parent = 0 },
  [1415] = {
    name = "Eastern Kingdoms",
    mapType = 2,
    parent = 947,
    c00 = { 0, 1000, 1000 },
    c11 = { 0, -1000, -1000 },
  },
  [1429] = {
    name = "Elwynn Forest",
    mapType = 3,
    parent = 1415,
    c00 = { 0, 200, 200 },
    c11 = { 0, -200, -200 },
  },
  [1453] = {
    name = "Stormwind City",
    mapType = 3,
    parent = 1415,
    c00 = { 0, 300, 300 },
    c11 = { 0, 100, 100 },
  },
}
Mock.playerMap = 1429
Mock.playerMapPos = { x = 0.42, y = 0.65 }
C_Map = {
  GetBestMapForUnit = function(unit)
    if unit == "player" then
      return Mock.playerMap
    end
    local m = Mock.unitMaps and Mock.unitMaps[unit]
    return m and m.map or nil
  end,
  GetPlayerMapPosition = function(mapID, unit)
    if unit == "player" and mapID == Mock.playerMap then
      return CreateVector2D(Mock.playerMapPos.x, Mock.playerMapPos.y)
    end
    local m = Mock.unitMaps and Mock.unitMaps[unit] -- group members (R26.9): { map, x, y }
    if m and m.map == mapID then
      return CreateVector2D(m.x, m.y)
    end
  end,
  -- an area's name (the Library's `discovered`): Mock.areas[areaID] = name
  GetAreaInfo = function(areaID)
    return Mock.areas and Mock.areas[areaID] or nil
  end,
  GetMapInfo = function(mapID)
    local m = Mock.maps[mapID]
    if m then
      return { mapID = mapID, name = m.name, mapType = m.mapType, parentMapID = m.parent, flags = 0 }
    end
  end,
  GetMapChildrenInfo = function(mapID)
    local out = {}
    for id, m in pairs(Mock.maps) do
      if m.parent == mapID then
        out[#out + 1] = { mapID = id, name = m.name, mapType = m.mapType, parentMapID = mapID, flags = 0 }
      end
    end
    return out
  end,
  GetWorldPosFromMapPos = function(mapID, pos)
    local m = Mock.maps[mapID]
    if not (m and m.c00 and m.c11) then
      return nil
    end
    local x, y = pos:GetXY()
    -- affine: y axis of the map runs along world x (north), x axis along world y (west); see coordinates.md
    local wx = m.c00[2] + (m.c11[2] - m.c00[2]) * y
    local wy = m.c00[3] + (m.c11[3] - m.c00[3]) * x
    return m.c00[1], CreateVector2D(wx, wy)
  end,
  GetMapPosFromWorldPos = function(continent, worldPos, mapID)
    local m = Mock.maps[mapID]
    if not (m and m.c00 and m.c00[1] == continent) then
      return nil
    end
    local wx, wy = worldPos:GetXY()
    return mapID,
      CreateVector2D((wy - m.c00[3]) / (m.c11[3] - m.c00[3]), (wx - m.c00[2]) / (m.c11[2] - m.c00[2]))
  end,
  GetMapArtLayers = function(mapID)
    if Mock.maps[mapID] then
      return {
        {
          layerWidth = 1002,
          layerHeight = 668,
          tileWidth = 256,
          tileHeight = 256,
          minScale = 1,
          maxScale = Mock.artMaxScale or 1, -- Blizzard's largest scale (2.14 for zones on retail)
        },
      }
    end
  end,
  GetMapArtLayerTextures = function(mapID)
    local m = Mock.maps[mapID]
    return m and m.textures or (m and { 1001, 1002, 1003 }) or nil
  end,
  GetMapArtID = function(mapID)
    return Mock.maps[mapID] and mapID or nil
  end,
}
-- The explored areas of a map (the Blizzard style's colours): Mock.explored[mapID] = { infos }
-- with textureWidth, textureHeight, offsetX, offsetY, fileDataIDs, isDrawOnTopLayer,
-- isShownByMouseOver as the retail family hands them out.
Mock.explored = {}
C_MapExplorationInfo = {
  GetExploredMapTextures = function(mapID)
    return Mock.explored[mapID] or {}
  end,
}

-- ---------------------------------------------------------------------------------------------
-- Settings (verified in the forever source tree, ADR 0009: Settings.RegisterCanvasLayoutCategory exists)
-- ---------------------------------------------------------------------------------------------

Mock.settingsCategories = {}
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name)
    local cat = { ID = "cat" .. (#Mock.settingsCategories + 1), name = name, frame = frame, children = {} }
    function cat:GetID()
      return self.ID
    end
    Mock.settingsCategories[#Mock.settingsCategories + 1] = cat
    return cat
  end,
  RegisterCanvasLayoutSubcategory = function(parent, frame, name)
    local cat = {
      ID = parent.ID .. "." .. (#parent.children + 1),
      name = name,
      frame = frame,
      children = {},
      parent = parent,
    }
    function cat:GetID()
      return self.ID
    end
    parent.children[#parent.children + 1] = cat
    return cat
  end,
  RegisterAddOnCategory = function(cat)
    cat.registered = true
  end,
  OpenToCategory = function(id)
    Mock.settingsOpened = id
  end,
}
InterfaceOptions_AddCategory = nil -- does not exist in the forever/live source (ADR 0009); stays nil on purpose

-- ---------------------------------------------------------------------------------------------
-- Tooltips (TooltipDataProcessor files exist in the forever source; runtime behaviour is probe P6 = assumed)
-- ---------------------------------------------------------------------------------------------

Enum = Enum or {}
Enum.TooltipDataType = Enum.TooltipDataType or { Item = 0, Spell = 1, Unit = 2, Object = 11, Macro = 24 }
-- The game's text to speech (C_VoiceChat.SpeakText, both API docs; the Orbiter's fallback): what was
-- spoken lands in Mock.tts, a stop counts in Mock.ttsStopped; Mock.ttsVoices = {} means no voice.
Enum.TtsVoiceType = Enum.TtsVoiceType or { Standard = 0, Alternate = 1 }
Mock.tts, Mock.ttsStopped = {}, 0
Mock.ttsVoices = { { voiceID = 2, name = "Microsoft David" }, { voiceID = 3, name = "Microsoft Zira" } }
C_VoiceChat = C_VoiceChat or {}
C_VoiceChat.GetTtsVoices = function()
  return CopyTable(Mock.ttsVoices)
end
C_VoiceChat.SpeakText = function(voiceID, text, rate, volume, overlap)
  Mock.tts[#Mock.tts + 1] = { voice = voiceID, text = text, rate = rate, volume = volume, overlap = overlap }
  Mock.Fire("VOICE_CHAT_TTS_PLAYBACK_STARTED", #Mock.tts)
end
C_VoiceChat.StopSpeakingText = function()
  Mock.ttsStopped = Mock.ttsStopped + 1
end
C_TTSSettings = C_TTSSettings or {}
C_TTSSettings.GetVoiceOptionID = function()
  return Mock.ttsVoice or 3
end
C_TTSSettings.GetSpeechRate = function()
  return 1
end
C_TTSSettings.GetSpeechVolume = function()
  return 80
end
local tooltipPostCalls = {}
TooltipDataProcessor = {
  AddTooltipPostCall = function(kind, fn)
    tooltipPostCalls[#tooltipPostCalls + 1] = { kind = kind, fn = fn }
  end,
  AllTypes = "ALL",
}
GameTooltip = newRegion("GameTooltip", "GameTooltip", UIParent)
GameTooltip.lines = {}
function GameTooltip:AddLine(text, r, g, b, wrap)
  self.lines[#self.lines + 1] = { left = text, r = r, g = g, b = b, wrap = wrap }
end
function GameTooltip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
  self.lines[#self.lines + 1] =
    { left = left, right = right, r = lr, g = lg, b = lb, rr = rr, rg = rg, rb = rb }
end
function GameTooltip:NumLines()
  return #self.lines
end
function GameTooltip:ClearLines()
  self.lines = {}
end
function GameTooltip:SetOwner(owner, anchor)
  self.owner, self.anchor = owner, anchor
end
function GameTooltip:GetOwner()
  return self.owner
end
function GameTooltip:IsOwned(f)
  return self.owner == f
end
function GameTooltip:GetItem()
  return self.itemName, self.itemLink, self.itemID
end
function GameTooltip:GetUnit()
  return self.unitName, self.unit
end
function GameTooltip:SetHyperlink(link)
  self.itemLink = link
end
function GameTooltip:SetItemByID(id)
  self.itemID = id
end
function GameTooltip:SetUnit(unit)
  self.unit = unit
end
function GameTooltip:AddTexture() end
function GameTooltip:SetPadding() end
function GameTooltip:GetTooltipData()
  return self.data
end
-- Simulate a hover: fires the processor post-calls with { type = kind, id = id, guid = guid }.
function Mock.Tooltip(kind, id, guid)
  GameTooltip.lines = {}
  GameTooltip.data = { type = kind, id = id, guid = guid }
  if kind == Enum.TooltipDataType.Item then
    GameTooltip.itemID = id
    GameTooltip.itemLink = "item:" .. id
  elseif kind == Enum.TooltipDataType.Unit then
    GameTooltip.unit = "mouseover"
    Mock.guids = Mock.guids or {}
    Mock.guids.mouseover = guid or ("Creature-0-1-0-1-" .. id .. "-0000000001")
  end
  GameTooltip:Show()
  for _, pc in ipairs(tooltipPostCalls) do
    if pc.kind == kind or pc.kind == TooltipDataProcessor.AllTypes then
      local ok, err = pcall(pc.fn, GameTooltip, GameTooltip.data)
      if not ok then
        errorHandler(err)
      end
    end
  end
  return GameTooltip.lines
end

-- ---------------------------------------------------------------------------------------------
-- Items (C_Item.GetItemInfo documented on both; GetItemInfo verified on Forever) and money formatting
-- ---------------------------------------------------------------------------------------------

Mock.items = {
  [2589] = {
    name = "Linen Cloth",
    quality = 1,
    level = 5,
    class = "Tradeskill",
    sell = 13,
    stack = 20,
    icon = 132889,
  },
  [6948] = {
    name = "Hearthstone",
    quality = 1,
    level = 1,
    class = "Miscellaneous",
    sell = 0,
    stack = 1,
    icon = 134414,
  },
}
local function itemInfo(idOrLink)
  local id = tonumber(idOrLink) or tonumber(string.match(tostring(idOrLink), "item:(%d+)"))
  local it = id and Mock.items[id]
  if not it then
    return nil
  end
  local link = ("|cffffffff|Hitem:%d::::::::1:::::|h[%s]|h|r"):format(id, it.name)
  return it.name,
    link,
    it.quality,
    it.level,
    1,
    it.class,
    it.subclass or "",
    it.stack,
    it.equipLoc or "",
    it.icon,
    it.sell,
    7,
    0,
    1,
    0,
    false
end
C_Item = C_Item or {}
C_Item.GetItemInfo = itemInfo
-- the quality of a known item and the game's quality colours (the skin's loot cells, ADR 0034)
function C_Item.GetItemQualityByID(id)
  local it = Mock.items[tonumber(id)]
  return it and it.quality or nil
end
Mock.QUALITY_RGB =
  { [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 } }
function C_Item.GetItemQualityColor(q)
  local c = Mock.QUALITY_RGB[q]
  if c then
    return c[1], c[2], c[3]
  end
end
-- Item stats and levels (C_Item.GetItemStats, GetDetailedItemLevelInfo: in both P1 dumps, the
-- returns assumed from the retail docs): Mock.items[id].stats = { ITEM_MOD_STAMINA_SHORT = 3 }.
local function itemIDOf(idOrLink)
  return tonumber(idOrLink) or tonumber(string.match(tostring(idOrLink), "item:(%d+)"))
end
C_Item.GetItemStats = function(link)
  local it = Mock.items[itemIDOf(link) or 0]
  if not it then
    return nil
  end
  local out = {}
  for key, amount in pairs(it.stats or {}) do
    out[key] = amount
  end
  return out
end
C_Item.GetDetailedItemLevelInfo = function(link)
  local it = Mock.items[itemIDOf(link) or 0]
  if not it then
    return nil
  end
  return it.level, false, it.level
end
-- What the player wears: Mock.equipped[slot] = itemID (GetInventoryItemLink in both P1 dumps).
Mock.equipped = {}
function GetInventoryItemLink(unit, slot)
  local id = unit == "player" and Mock.equipped[slot] or nil
  if not id then
    return nil
  end
  local _, link = itemInfo(id)
  return link
end
function GetInventoryItemID(unit, slot)
  return unit == "player" and Mock.equipped[slot] or nil
end
C_Item.GetItemInfoInstant = function(idOrLink)
  local id = tonumber(idOrLink) or tonumber(string.match(tostring(idOrLink), "item:(%d+)"))
  local it = id and Mock.items[id]
  if it then
    return id, "Tradeskill", "Cloth", it.equipLoc or "INVTYPE_NON_EQUIP", it.icon, it.classID or 7, it.subclassID or 0
  end
end
-- which items can be worn (the Browser's portrait tries them on): Mock.equippable[itemID] = true
Mock.equippable = {}
C_Item.IsEquippableItem = function(id)
  return Mock.equippable[tonumber(id)] == true
end
C_Item.GetItemNameByID = function(id)
  return Mock.items[id] and Mock.items[id].name
end
C_Item.GetItemIconByID = function(id)
  return Mock.items[id] and Mock.items[id].icon
end
C_Item.DoesItemExistByID = function(id)
  return Mock.items[id] ~= nil
end
GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant
function GetCoinTextureString(copper)
  return tostring(copper) .. "c"
end
function GetMoneyString(copper)
  return tostring(copper) .. "c"
end

-- ---------------------------------------------------------------------------------------------
-- Quest log (C_QuestLog is the retail family on both clients, ADR 0009; runtime shape is probe P2 = assumed)
-- ---------------------------------------------------------------------------------------------

-- Test data: headers are { header = "Zone" }, quests carry questID, title, level, complete, objectives.
Mock.questLog = {
  { header = "Elwynn Forest" },
  {
    questID = 176,
    title = "The Fargodeep Mine",
    level = 7,
    complete = false,
    objectives = {
      {
        text = "Explore the Fargodeep Mine",
        type = "event",
        finished = false,
        numFulfilled = 0,
        numRequired = 1,
      },
    },
  },
  { questID = 62, title = "The Fargodeep Mine II", level = 9, complete = true, objectives = {} },
}
Mock.completedQuests = { 783, 7, 18 }
local function questByID(id)
  for _, e in ipairs(Mock.questLog) do
    if e.questID == id then
      return e
    end
  end
end
C_QuestLog = C_QuestLog or {}
C_QuestLog.GetNumQuestLogEntries = function()
  local quests = 0
  for _, e in ipairs(Mock.questLog) do
    if e.questID then
      quests = quests + 1
    end
  end
  return #Mock.questLog, quests
end
C_QuestLog.GetInfo = function(i)
  local e = Mock.questLog[i]
  if not e then
    return nil
  end
  if e.header then
    return { title = e.header, isHeader = true, questID = 0, questLogIndex = i, level = 0 }
  end
  return {
    title = e.title,
    questID = e.questID,
    level = e.level,
    isHeader = false,
    questLogIndex = i,
    isHidden = e.hidden or false, -- the client's own tracking quests (retail)
  }
end
C_QuestLog.GetQuestObjectives = function(id)
  local e = questByID(id)
  return e and CopyTable(e.objectives) or {}
end
-- The client's quest waypoints and map POIs (retail 12.1.5, D2): test data in Mock.waypoints
-- ([questID] = { map, x, y }); both functions exist on both clients' API dumps, shapes assumed.
Mock.waypoints = {}
C_QuestLog.GetNextWaypointForMap = function(id, map)
  local w = Mock.waypoints[id]
  if w and w.map == map then
    return w.x, w.y
  end
  return nil
end
C_QuestLog.GetQuestsOnMap = function(map)
  local out = {}
  for id, w in pairs(Mock.waypoints) do
    if w.map == map then
      out[#out + 1] = { questID = id, x = w.x, y = w.y, type = 0, isMapIndicatorQuest = false }
    end
  end
  table.sort(out, function(a, b)
    return a.questID < b.questID
  end)
  return out
end
C_QuestLog.IsComplete = function(id)
  local e = questByID(id)
  return e ~= nil and e.complete == true
end
C_QuestLog.ReadyForTurnIn = C_QuestLog.IsComplete
C_QuestLog.GetAllCompletedQuestIDs = function()
  return CopyTable(Mock.completedQuests)
end
C_QuestLog.IsQuestFlaggedCompleted = function(id)
  return tContains(Mock.completedQuests, id)
end
-- Quest item and text (legacy globals used by Blizzard's tracker and quest log on both clients; assumed).
-- Test data: an entry may carry item = { id, icon, charges }, details and objectivesText.
Mock.bags = {} -- [itemID] = count
Mock.selectedQuest = 0
function GetQuestLogSpecialItemInfo(i)
  local e = Mock.questLog[i]
  if not (e and e.item) then
    return nil
  end
  return ("|cffffffff|Hitem:%d::::::::1:::::|h[Item %d]|h|r"):format(e.item.id, e.item.id),
    e.item.icon or 134400,
    e.item.charges or -1,
    e.item.showWhenComplete or false
end
C_Item.GetItemCount = function(id)
  return Mock.bags[id] or 0
end
C_Item.IsEquippedItem = function(id)
  return Mock.worn[id] == true
end
C_Item.GetItemSpell = function(id)
  local spell = Mock.itemSpells[id]
  if spell then
    return "Spell " .. spell, spell
  end
end
-- Bag slots (C_Container, the retail info table): Mock.bagSlots[bag] = { { itemID, count, quality,
-- bound, noValue }, ... }; a nil entry is an empty slot.
Mock.bagSlots = {}
C_Container.GetContainerNumSlots = function(bag)
  local b = Mock.bagSlots[bag]
  if not b then
    return bag == 0 and 16 or 0
  end
  return b.slots or 16 -- slot tables may have holes, so # is no measure
end
C_Container.GetContainerItemID = function(bag, slot)
  local b = Mock.bagSlots[bag]
  return b and b[slot] and b[slot].itemID or nil
end
-- using an item from the bags (the Library's `used` trigger hooks it): what was used is kept
Mock.used = {}
C_Container.UseContainerItem = function(bag, slot)
  Mock.used[#Mock.used + 1] = { bag, slot }
  if MerchantFrame:IsShown() then
    Mock.SellSlot(bag, slot) -- with a merchant open the client sells the stack (Helpers)
  end
end
C_Container.GetContainerItemInfo = function(bag, slot)
  local b = Mock.bagSlots[bag]
  local s = b and b[slot]
  if not s then
    return nil
  end
  local it = Mock.items[s.itemID]
  return {
    itemID = s.itemID,
    stackCount = s.count or 1,
    quality = s.quality or (it and it.quality) or 1,
    isBound = s.bound == true,
    hasNoValue = s.noValue == true,
    iconFileID = it and it.icon or nil,
    hyperlink = "item:" .. s.itemID,
    isLocked = false,
  }
end
GetItemCount = C_Item.GetItemCount
C_QuestLog.SetSelectedQuest = function(id)
  Mock.selectedQuest = id
end
C_QuestLog.GetSelectedQuest = function()
  return Mock.selectedQuest
end
function GetQuestLogQuestText()
  local e = questByID(Mock.selectedQuest)
  if not e then
    return "", ""
  end
  return e.details or "", e.objectivesText or ""
end
-- Quest titles, quest and item data loads, creature names by id (C_QuestLog.GetTitleForQuestID,
-- RequestLoadQuestByID, C_Item.RequestLoadItemDataByID, C_TooltipInfo.GetHyperlink: documented
-- identically on both clients; runtime shapes assumed, probe P2/P6). Test data: Mock.questTitles[id]
-- is a title the client knows once the quest is loaded, Mock.unitNames[npcID] a creature name,
-- Mock.lateItems[id] an item the client has after a load. Loads answer 0.1 s later with the event.
Mock.questTitles = {}
Mock.loadedQuests = {}
Mock.unitNames = {}
Mock.lateItems = {}
Mock.questLoadRequests = {}
Mock.itemLoadRequests = {}
C_QuestLog.GetTitleForQuestID = function(id)
  local e = questByID(id)
  if e then
    return e.title
  end
  return Mock.loadedQuests[id] and Mock.questTitles[id] or nil
end
C_QuestLog.RequestLoadQuestByID = function(id)
  Mock.questLoadRequests[#Mock.questLoadRequests + 1] = id
  C_Timer.After(0.1, function()
    local known = Mock.questTitles[id] ~= nil
    if known then
      Mock.loadedQuests[id] = true
    end
    Mock.Fire("QUEST_DATA_LOAD_RESULT", id, known)
  end)
end
C_Item.RequestLoadItemDataByID = function(id)
  Mock.loadRequests = (Mock.loadRequests or 0) + 1 -- the Gold capture tests count requests
  Mock.itemLoadRequests[#Mock.itemLoadRequests + 1] = id
  C_Timer.After(0.1, function()
    local late = Mock.lateItems[id]
    if late then
      Mock.items[id] = late
    end
    Mock.Fire("ITEM_DATA_LOAD_RESULT", id, Mock.items[id] ~= nil)
  end)
end
C_TooltipInfo = C_TooltipInfo or {}
C_TooltipInfo.GetHyperlink = function(link)
  local npcID = tonumber(string.match(link or "", "^unit:Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
  local name = npcID and Mock.unitNames[npcID]
  if not name then
    return nil
  end
  return { type = Enum.TooltipDataType.Unit, lines = { { type = 0, leftText = name } } }
end
-- The mailbox and the send tab (the retail family's globals, assumed on Forever; Bastian's Alts):
-- Mock.inbox = { { money = copper, items = { { itemID, count } } } }; Mock.OpenMailbox() makes the
-- mail frames and fires MAIL_SHOW and MAIL_INBOX_UPDATE; attaching moves the picked bag stack into
-- Mock.sendItems and fires MAIL_SEND_INFO_UPDATE; SendMail keeps Mock.sentMail and answers
-- MAIL_SEND_SUCCESS a frame later.
Mock.inbox, Mock.sendItems = {}, {}
ATTACHMENTS_MAX_SEND, ATTACHMENTS_MAX_RECEIVE = 12, 16
function GetInboxNumItems()
  return #Mock.inbox
end
function GetInboxHeaderInfo(i)
  local m = Mock.inbox[i]
  return nil, nil, m.sender or "Someone", m.subject or "", m.money or 0, m.cod or 0, 30, m.items ~= nil
end
-- Taking from a mail (Helpers' Take all): the money or the attachments go to the character, an
-- empty mail goes, and MAIL_INBOX_UPDATE answers a frame later.
Mock.taken = {}
local function inboxChanged(i)
  local m = Mock.inbox[i]
  if m and (m.money or 0) == 0 and not m.items then
    table.remove(Mock.inbox, i)
  end
  C_Timer.After(0, function()
    Mock.Fire("MAIL_INBOX_UPDATE")
  end)
end
function TakeInboxMoney(i)
  local m = Mock.inbox[i]
  Mock.taken[#Mock.taken + 1] = { "money", i }
  if m then
    Mock.money = (Mock.money or 0) + (m.money or 0)
    m.money = 0
    inboxChanged(i)
  end
end
function AutoLootMailItem(i)
  local m = Mock.inbox[i]
  Mock.taken[#Mock.taken + 1] = { "items", i }
  if m then
    for _, it in ipairs(m.items or {}) do
      Mock.bags[it[1]] = (Mock.bags[it[1]] or 0) + (it[2] or 1)
    end
    m.items = nil
    inboxChanged(i)
  end
end
local function inboxItem(i, a)
  return Mock.inbox[i] and Mock.inbox[i].items and Mock.inbox[i].items[a]
end
function GetInboxItem(i, a)
  local it = inboxItem(i, a)
  if not it then
    return nil
  end
  return "Item " .. it[1], it[1], nil, it[2] or 1, 1, true
end
function GetInboxItemLink(i, a)
  local it = inboxItem(i, a)
  return it and ("item:" .. it[1]) or nil
end
C_Container.PickupContainerItem = function(bag, slot)
  Mock.cursor = { bag, slot }
end
function ClickSendMailItemButton(i)
  local c = Mock.cursor
  local s = c and Mock.bagSlots[c[1]] and Mock.bagSlots[c[1]][c[2]]
  Mock.cursor = nil
  if s then
    Mock.sendItems[i] = { s.itemID, s.count or 1 }
    Mock.Fire("MAIL_SEND_INFO_UPDATE")
  end
end
function GetSendMailItem(i)
  local it = Mock.sendItems[i]
  if not it then
    return nil
  end
  return "Item " .. it[1], it[1], nil, it[2]
end
function SendMail(recipient, subject)
  local items = {}
  for i, it in pairs(Mock.sendItems) do
    items[i] = it
  end
  Mock.sentMail = { recipient = recipient, subject = subject, items = items }
  Mock.sendItems = {} -- the client clears the send tab
  C_Timer.After(0, function()
    Mock.Fire("MAIL_SEND_SUCCESS")
  end)
end
function Mock.OpenMailbox()
  if not MailFrame then
    MailFrame = CreateFrame("Frame", "MailFrame", UIParent)
    MailFrame:SetSize(340, 420)
    MailFrameTab2 = CreateFrame("Button", "MailFrameTab2", MailFrame)
    MailFrameTab2:SetScript("OnClick", function()
      Mock.sendTab = true
    end)
    SendMailNameEditBox = CreateFrame("EditBox", "SendMailNameEditBox", MailFrame)
    SendMailSubjectEditBox = CreateFrame("EditBox", "SendMailSubjectEditBox", MailFrame)
  end
  MailFrame:Show()
  Mock.Fire("MAIL_SHOW")
  Mock.Fire("MAIL_INBOX_UPDATE")
end
-- Quest givers (Helpers: the quest frame's globals, the greeting frame's and C_GossipInfo; in both
-- P1 dumps, behaviour assumed). Test data: Mock.questFrame = { completable, money, auto, choices =
-- { { itemID, count } } }, Mock.greeting = { active = { { title, complete } }, available = { { title } } },
-- Mock.gossip = { active = { { questID, title, isComplete } }, available = { { questID, title } },
-- options = { { gossipOptionID, name } } }; every call the addon makes lands in Mock.npcCalls.
Mock.questFrame = { completable = false, money = 0, auto = false, choices = {} }
Mock.greeting = { active = {}, available = {} }
Mock.gossip = { active = {}, available = {}, options = {} }
Mock.npcCalls, Mock.pushable = {}, {}
local function npcCall(...)
  Mock.npcCalls[#Mock.npcCalls + 1] = table.concat({ ... }, " ")
end
function AcceptQuest()
  npcCall("accept")
end
function ConfirmAcceptQuest()
  npcCall("confirm")
end
function QuestGetAutoAccept()
  return Mock.questFrame.auto == true
end
function AcknowledgeAutoAcceptQuest()
  npcCall("acknowledge")
end
function IsQuestCompletable()
  return Mock.questFrame.completable == true
end
function GetQuestMoneyToGet()
  return Mock.questFrame.money or 0
end
function CompleteQuest()
  npcCall("continue")
end
function GetNumQuestChoices()
  return #Mock.questFrame.choices
end
function GetQuestItemLink(kind, i)
  local c = kind == "choice" and Mock.questFrame.choices[i]
  return c and ("item:" .. c[1]) or nil
end
function GetQuestItemInfo(kind, i)
  local c = kind == "choice" and Mock.questFrame.choices[i]
  if not c then
    return nil
  end
  return "Item " .. c[1], 134400, c[2] or 1, 1, true, c[1]
end
function GetQuestReward(choice)
  npcCall("reward", tostring(choice))
end
-- The quest frame's texts and id (Bastian's Voice draws the conversation): Mock.questFrame.title,
-- .text, .objectives, .reward, .progress, .questID
function GetTitleText()
  return Mock.questFrame.title or ""
end
function GetQuestText()
  return Mock.questFrame.text or ""
end
function GetObjectiveText()
  return Mock.questFrame.objectives or ""
end
function GetRewardText()
  return Mock.questFrame.reward or ""
end
function GetProgressText()
  return Mock.questFrame.progress or ""
end
function GetQuestID()
  return Mock.questFrame.questID or 0
end
function DeclineQuest()
  npcCall("decline")
end
function CloseQuest()
  npcCall("close quest")
end
C_GossipInfo = C_GossipInfo or {}
C_GossipInfo.CloseGossip = function()
  npcCall("close gossip")
end
function GetNumActiveQuests()
  return #Mock.greeting.active
end
function GetActiveTitle(i)
  local q = Mock.greeting.active[i]
  return q and q.title, q and q.complete or false
end
function GetNumAvailableQuests()
  return #Mock.greeting.available
end
function GetAvailableTitle(i)
  local q = Mock.greeting.available[i]
  return q and q.title
end
function SelectActiveQuest(i)
  npcCall("greeting active", tostring(i))
end
function SelectAvailableQuest(i)
  npcCall("greeting available", tostring(i))
end
C_GossipInfo = C_GossipInfo or {}
C_GossipInfo.GetActiveQuests = function()
  return CopyTable(Mock.gossip.active)
end
C_GossipInfo.GetAvailableQuests = function()
  return CopyTable(Mock.gossip.available)
end
C_GossipInfo.GetOptions = function()
  return CopyTable(Mock.gossip.options)
end
C_GossipInfo.SelectOption = function(id)
  npcCall("gossip option", tostring(id))
end
C_GossipInfo.SelectActiveQuest = function(id)
  npcCall("gossip active", tostring(id))
end
C_GossipInfo.SelectAvailableQuest = function(id)
  npcCall("gossip available", tostring(id))
end
C_QuestLog.IsPushableQuest = function(id)
  return Mock.pushable[id] == true
end
function QuestLogPushQuest()
  npcCall("push", tostring(C_QuestLog.GetSelectedQuest()))
end
-- Durability of the worn items: Mock.durability[slot] = { current, max } (GetInventoryItemDurability)
Mock.durability = {}
function GetInventoryItemDurability(slot)
  local d = Mock.durability[slot]
  if not d then
    return nil
  end
  return d[1], d[2]
end
-- Free slots of a bag (C_Container.GetContainerNumFreeSlots): its slots without an item; family 0
C_Container.GetContainerNumFreeSlots = function(bag)
  local slots = C_Container.GetContainerNumSlots(bag)
  local used = 0
  for i = 1, slots do
    if C_Container.GetContainerItemID(bag, i) then
      used = used + 1
    end
  end
  return slots - used, 0
end
-- An item's tooltip lines (C_TooltipInfo.GetItemByID, retail shape assumed): Mock.itemTooltips[id]
-- = { { leftText, rightText, leftColor = { r, g, b } } }, nil for an item the client lacks.
Mock.itemTooltips = {}
C_TooltipInfo.GetItemByID = function(id)
  local lines = Mock.itemTooltips[id]
  if not lines then
    return nil
  end
  return { type = Enum.TooltipDataType.Item, id = id, lines = lines }
end
-- Objective tracker (C_QuestLog watch functions, documented identically on both clients; assumed).
Mock.watched = {} -- questIDs in watch order
local function watchIndex(id)
  for i, w in ipairs(Mock.watched) do
    if w == id then
      return i
    end
  end
end
C_QuestLog.GetNumQuestWatches = function()
  return #Mock.watched
end
C_QuestLog.GetQuestIDForQuestWatchIndex = function(i)
  return Mock.watched[i]
end
C_QuestLog.GetQuestWatchType = function(id)
  return watchIndex(id) and 1 or nil -- Enum.QuestWatchType.Manual
end
C_QuestLog.AddQuestWatch = function(id)
  if watchIndex(id) or not questByID(id) then
    return false
  end
  Mock.watched[#Mock.watched + 1] = id
  Mock.Fire("QUEST_WATCH_LIST_CHANGED", id, true)
  return true
end
C_QuestLog.RemoveQuestWatch = function(id)
  local i = watchIndex(id)
  if not i then
    return false
  end
  table.remove(Mock.watched, i)
  Mock.Fire("QUEST_WATCH_LIST_CHANGED", id, false)
  return true
end
C_QuestLog.GetLogIndexForQuestID = function(id)
  for i, e in ipairs(Mock.questLog) do
    if e.questID == id then
      return i
    end
  end
end
C_QuestLog.GetQuestIDForLogIndex = function(i)
  local e = Mock.questLog[i]
  return e and e.questID or 0
end

-- ---------------------------------------------------------------------------------------------
-- Taxi (C_TaxiMap.GetAllTaxiNodes documented identically on both; runtime shape is probe P7 = assumed).
-- Test data: Mock.taxiNodes is what the open flight master shows; state uses Enum.FlightPathState values.
-- ---------------------------------------------------------------------------------------------

Mock.taxiNodes = {
  { nodeID = 2, name = "Stormwind, Elwynn", x = 0.66, y = 0.47, state = 0 },
  { nodeID = 4, name = "Sentinel Hill, Westfall", x = 0.56, y = 0.52, state = 1 },
  { nodeID = 6, name = "Ironforge, Dun Morogh", x = 0.59, y = 0.24, state = 2 },
}
Mock.taxiMapID = 1415 -- Eastern Kingdoms continent map, as the flight map shows it
function GetTaxiMapID()
  return Mock.taxiMapID
end
C_TaxiMap = C_TaxiMap or {}
C_TaxiMap.GetAllTaxiNodes = function(uiMapID)
  local out = {}
  if uiMapID ~= Mock.taxiMapID then
    return out
  end
  for i, n in ipairs(Mock.taxiNodes) do
    out[i] = {
      nodeID = n.nodeID,
      name = n.name,
      position = CreateVector2D(n.x, n.y),
      state = n.state,
      slotIndex = i,
      textureKit = "FlightMaster",
      useSpecialIcon = false,
    }
  end
  return out
end
local LEGACY_TAXI = { [0] = "CURRENT", [1] = "REACHABLE", [2] = "DISTANT" }
function NumTaxiNodes()
  return #Mock.taxiNodes
end
function TaxiNodeName(i)
  local n = Mock.taxiNodes[i]
  return n and n.name or nil
end
function TaxiNodePosition(i)
  local n = Mock.taxiNodes[i]
  if n then
    return n.x, n.y
  end
end
function TaxiNodeGetType(i)
  local n = Mock.taxiNodes[i]
  return n and LEGACY_TAXI[n.state] or "NONE"
end
function TaxiNodeCost()
  return 110
end
function TakeTaxiNode()
  Mock.onTaxi = true
end

-- ---------------------------------------------------------------------------------------------
-- Merchant (C_MerchantFrame.GetItemInfo documented on both; legacy GetMerchantItemInfo/Link assumed present)
-- ---------------------------------------------------------------------------------------------

Mock.merchant = {
  {
    itemID = 2589,
    name = "Linen Cloth",
    texture = 132889,
    price = 260,
    stackCount = 20,
    numAvailable = -1,
    isPurchasable = true,
    isUsable = true,
  },
}
local function merchantLink(it)
  return ("|cffffffff|Hitem:%d::::::::1:::::|h[%s]|h|r"):format(it.itemID, it.name)
end
function GetMerchantNumItems()
  return #Mock.merchant
end
function GetMerchantItemLink(i)
  local it = Mock.merchant[i]
  return it and merchantLink(it) or nil
end
function GetMerchantItemInfo(i)
  local it = Mock.merchant[i]
  if not it then
    return nil
  end
  return it.name, it.texture, it.price, it.stackCount, it.numAvailable, it.isPurchasable, it.isUsable, false
end
-- The game's interaction panels (FrameXML on both clients): shown by their events in game.
GossipFrame = newRegion("Frame", "GossipFrame", UIParent)
GossipFrame:SetSize(384, 512)
GossipFrame:Hide()
QuestFrame = newRegion("Frame", "QuestFrame", UIParent)
QuestFrame:SetSize(384, 512)
QuestFrame:Hide()
MerchantFrame = newRegion("Frame", "MerchantFrame", UIParent)
MerchantFrame:SetSize(336, 444)
MerchantFrame:Hide()
-- Bastian's Helpers (helpers.md): selling, repair, buying, the buyback tab (the retail family's
-- globals, in both P1 dumps; behaviour assumed). Mock.OpenMerchant() shows the frame and fires
-- MERCHANT_SHOW; a sale moves the stack to Mock.buyback and pays its vendor price; Mock.repair is
-- what GetRepairAllCost and the guild answer; purchases land in Mock.bought and Mock.bags.
Mock.buyback, Mock.bought, Mock.repaired, Mock.boughtBack = {}, {}, {}, {}
Mock.repair = { cost = 0, can = false, merchant = true, guild = false, guildMoney = 0 }
function Mock.SellSlot(bag, slot)
  local b = Mock.bagSlots[bag]
  local s = b and b[slot]
  if not s then
    return
  end
  local it = Mock.items[s.itemID]
  local price = (it and it.sell or 0) * (s.count or 1)
  Mock.money = (Mock.money or 0) + price
  Mock.buyback[#Mock.buyback + 1] = { itemID = s.itemID, count = s.count or 1, price = price, slot = s }
  b[slot] = nil
end
function Mock.OpenMerchant()
  MerchantFrame:Show()
  Mock.Fire("MERCHANT_SHOW")
end
function Mock.CloseMerchant()
  MerchantFrame:Hide()
  Mock.Fire("MERCHANT_CLOSED")
end
function CanMerchantRepair()
  return Mock.repair.merchant
end
function GetRepairAllCost()
  return Mock.repair.cost, Mock.repair.can
end
function CanGuildBankRepair()
  return Mock.repair.guild
end
function GetGuildBankWithdrawMoney()
  return Mock.repair.guildMoney
end
function RepairAllItems(guild)
  Mock.repaired[#Mock.repaired + 1] = { guild = guild == true }
  if not guild then
    Mock.money = (Mock.money or 0) - Mock.repair.cost
  end
  Mock.repair.cost, Mock.repair.can = 0, false
end
function GetMerchantItemMaxStack(i)
  local it = Mock.merchant[i]
  return it and (it.maxStack or it.stackCount * 20) or 0
end
function BuyMerchantItem(i, count)
  local it = Mock.merchant[i]
  Mock.bought[#Mock.bought + 1] = { i, count }
  if it then
    Mock.money = (Mock.money or 0) - it.price * (count or it.stackCount) / it.stackCount
    Mock.bags[it.itemID] = (Mock.bags[it.itemID] or 0) + (count or it.stackCount)
  end
end
function GetNumBuybackItems()
  return #Mock.buyback
end
function GetBuybackItemLink(i)
  local e = Mock.buyback[i]
  return e and ("item:" .. e.itemID) or nil
end
function GetBuybackItemInfo(i)
  local e = Mock.buyback[i]
  if not e then
    return nil
  end
  return "Item " .. e.itemID, 134400, e.price, e.count
end
function BuybackItem(i)
  local e = table.remove(Mock.buyback, i)
  if e then
    Mock.boughtBack[#Mock.boughtBack + 1] = e.itemID
    Mock.money = (Mock.money or 0) - e.price
  end
end
-- Alt-click on a merchant item: FrameXML's handler, hooked by Helpers
function MerchantItemButton_OnModifiedClick() end
C_MerchantFrame = C_MerchantFrame or {}
C_MerchantFrame.GetItemInfo = function(i)
  local it = Mock.merchant[i]
  if not it then
    return nil
  end
  return {
    name = it.name,
    texture = it.texture,
    price = it.price,
    stackCount = it.stackCount,
    numAvailable = it.numAvailable,
    isPurchasable = it.isPurchasable,
    isUsable = it.isUsable,
    hasExtendedCost = false,
  }
end

-- ---------------------------------------------------------------------------------------------
-- Trainer. Verified on Forever (forever-api.md): GetTrainerServiceInfo -> name, type, icon; the type
-- filter wants a boolean. The retail/Classic order name, subtext, type, expanded and a numeric filter
-- are assumed. C_Trainer exists only in the forever docs.
-- ---------------------------------------------------------------------------------------------

-- Test data: services with kind available | unavailable | used | header (headers may be expanded =
-- false); the list shows only what the filters let through, as the client does.
Mock.trainer = {
  { name = "Fireball", kind = "available", icon = 135812, subtext = "Rank 2", cost = 1200, level = 6 },
  {
    name = "Frostbolt",
    kind = "unavailable",
    icon = 135846,
    subtext = "Rank 3",
    cost = 3000,
    level = 14,
    skill = "Frost",
    skillRank = 1,
  },
}
Mock.trainerFilters = { available = true, unavailable = true, used = false }
Mock.trainerFilterCalls = {}
Mock.tradeskillTrainer = false
local function visibleTrainer()
  local out = {}
  for _, s in ipairs(Mock.trainer) do
    if s.kind == "header" or Mock.trainerFilters[s.kind] then
      out[#out + 1] = s
    end
  end
  return out
end
function GetNumTrainerServices()
  return #visibleTrainer()
end
function GetTrainerServiceInfo(i)
  local s = visibleTrainer()[i]
  if not s then
    return nil
  end
  if client == "forever" then
    return s.name, s.kind, s.icon
  end
  return s.name, s.subtext, s.kind, s.expanded ~= false
end
function GetTrainerServiceCost(i)
  local s = visibleTrainer()[i]
  return s and s.cost or nil
end
function GetTrainerServiceSkillReq(i)
  local s = visibleTrainer()[i]
  if s and s.skill then
    return s.skill, s.skillRank
  end
  return nil
end
function GetTrainerServiceLevelReq(i)
  local s = visibleTrainer()[i]
  return s and s.level or nil
end
function GetTrainerServiceItemLink(i)
  local s = visibleTrainer()[i]
  if s and s.itemID then
    return "|cffffffff|Hitem:" .. s.itemID .. "::::::::60|h[x]|h|r"
  end
  return nil
end
function GetTrainerServiceTypeFilter(kind)
  return Mock.trainerFilters[kind]
end
function SetTrainerServiceTypeFilter(kind, on)
  if client == "forever" and type(on) ~= "boolean" then
    error('Usage: SetTrainerServiceTypeFilter("type", on/off): Missing on/off parameter')
  end
  Mock.trainerFilterCalls[#Mock.trainerFilterCalls + 1] = { kind = kind, on = on }
  Mock.trainerFilters[kind] = (on == true or on == 1)
end
function IsTradeskillTrainer()
  return Mock.tradeskillTrainer
end

-- ---------------------------------------------------------------------------------------------
-- Auction house (C_AuctionHouse.ReplicateItems and the replicate readers: verified on Forever,
-- forever-api.md). Test data: Mock.auctions rows { itemID, count, buyout, bid, owner, name, texture,
-- quality, level, levelType, minBid, minIncrement, sale, timeLeft, link, late, noInfo, noFull };
-- `late` rows have no item data or seller until Mock.ownersLoaded is true. Index is 0-based.
-- ---------------------------------------------------------------------------------------------

Mock.auctions = {}
Mock.ownersLoaded = false
Mock.replicateRequests = 0
Mock.loadRequests = 0
AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
AuctionHouseFrame:Hide()
C_AuctionHouse = C_AuctionHouse or {}
C_AuctionHouse.ReplicateItems = function()
  Mock.replicateRequests = Mock.replicateRequests + 1
end
C_AuctionHouse.GetNumReplicateItems = function()
  return #Mock.auctions
end
C_AuctionHouse.GetReplicateItemInfo = function(i)
  local l = Mock.auctions[i + 1]
  if not l then
    return nil
  end
  local full = l.owner
  local info = not l.noInfo and not (l.late and not Mock.ownersLoaded)
  if l.late and not Mock.ownersLoaded then
    full = nil
  end
  local short = full and (string.match(full, "^[^-]+") or full) or nil
  if l.noFull then
    full = nil
  end
  -- positions as in the API docs: 12 highBidder, 13 bidderFullName, 14 owner, 15 ownerFullName
  return l.name or ("Item" .. l.itemID),
    l.texture or 134936,
    l.count,
    l.quality or 1,
    true,
    l.level,
    l.levelType,
    l.minBid,
    l.minIncrement,
    l.buyout,
    l.bid or 0,
    "Bidder",
    "Bidder-Realm",
    short,
    full,
    l.sale or 0,
    l.itemID,
    info
end
C_AuctionHouse.GetReplicateItemTimeLeft = function(i)
  local l = Mock.auctions[i + 1]
  return l and (l.timeLeft or 3) or nil
end
C_AuctionHouse.GetReplicateItemLink = function(i)
  local l = Mock.auctions[i + 1]
  if not l then
    return nil
  end
  return l.link or ("|cffffffff|Hitem:" .. l.itemID .. "::::::::60|h[x]|h|r")
end
if client == "forever" then
  C_Trainer = {
    GetTrainerType = function()
      return 0
    end,
    GetCategorizeTrainerUI = function()
      return false
    end,
    SetCategorizeTrainerUI = function() end,
  }
end

-- ---------------------------------------------------------------------------------------------
-- Generated stubs: every documented function on this client that is not mocked above raises
-- "not mocked" instead of returning nil, so a test that needs it adds behaviour deliberately.
-- ---------------------------------------------------------------------------------------------

function Mock.InstallStubs(api)
  Mock.api = api
  if type(api) ~= "table" or type(api.functions) ~= "table" then
    return 0
  end
  local n = 0
  for fullName in pairs(api.functions) do
    local ns, fn = string.match(fullName, "^([%w_]+)%.([%w_]+)$")
    local holder, key
    if ns then
      _G[ns] = _G[ns] or {}
      holder, key = _G[ns], fn
    else
      holder, key = _G, fullName
    end
    if holder[key] == nil then
      holder[key] = function()
        error(
          ("'%s' is documented on %s but not mocked; add behaviour to tests/lua/mock/wow.lua"):format(
            fullName,
            client
          ),
          2
        )
      end
      n = n + 1
    end
  end
  if type(api.enums) == "table" then
    for name, values in pairs(api.enums) do
      Enum[name] = Enum[name] or values
    end
  end
  return n
end

-- ---------------------------------------------------------------------------------------------
-- Saved variables: WoW-style serializer, used by the harness for the /reload round trip
-- ---------------------------------------------------------------------------------------------

local function serialize(v, indent, out)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif t == "number" or t == "boolean" then
    out[#out + 1] = tostring(v)
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then
        return ta < tb
      end
      return a < b
    end)
    out[#out + 1] = "{\n"
    for _, k in ipairs(keys) do
      out[#out + 1] = indent .. "  ["
      serialize(k, indent .. "  ", out)
      out[#out + 1] = "] = "
      serialize(v[k], indent .. "  ", out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
  else
    error("cannot save a " .. t .. " in saved variables")
  end
end
function Mock.SerializeSavedVariables(names)
  local out = {}
  for _, name in ipairs(names) do
    if _G[name] ~= nil then
      out[#out + 1] = name .. " = "
      serialize(_G[name], "", out)
      out[#out + 1] = "\n"
    end
  end
  return table.concat(out)
end

-- ---------------------------------------------------------------------------------------------
-- Layout for pictures of the UI (tests/lua/render.py): the anchors resolved into rectangles and
-- every visible texture and text in drawing order. Scales are taken as 1.
-- ---------------------------------------------------------------------------------------------

local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function anchorXY(r, point)
  local l, b, rr, t = r[1], r[2], r[3], r[4]
  local x = point:find("LEFT") and l or point:find("RIGHT") and rr or (l + rr) / 2
  local y = point:find("TOP") and t or point:find("BOTTOM") and b or (b + t) / 2
  return x, y
end

local function ownSize(f)
  local w, h = f.width or 0, f.height or 0
  if f.objectType == "FontString" then
    local tw, th = 0, 0
    if Mock.measure and f.font then
      tw, th = Mock.measure(f.text or "", f.font[1], f.font[2], w or 0, f.spacing or 0)
    end
    if w == 0 then
      w = tw
    end
    if h == 0 then
      h = th
    end
  end
  return w, h
end

local function rectOf(f, memo)
  if memo[f] then
    return memo[f]
  end
  if f == UIParent or not f.parent and #f.points == 0 then
    local r = { 0, 0, f.width or 1920, f.height or 1080 }
    memo[f] = r
    return r
  end
  memo[f] = { 0, 0, 0, 0 } -- a cycle stops here
  if #f.points == 0 and f.scrollParent then
    -- a scroll child: its top left at the scroll frame's, moved up by the scroll
    local sr = rectOf(f.scrollParent, memo)
    local w, h = ownSize(f)
    local top = sr[4] + (f.scrollParent.verticalScroll or 0)
    local r = { sr[1], top - h, sr[1] + w, top }
    memo[f] = r
    return r
  end
  local l, rgt, cx, b, t, cy
  for _, p in ipairs(f.points) do
    local rel = p.rel
    if type(rel) == "string" then
      rel = _G[rel]
    end
    rel = rel or f.parent or UIParent
    local rr = rectOf(rel, memo)
    if p.point == "ALL" then
      l, b, rgt, t = rr[1], rr[2], rr[3], rr[4]
    else
      local ax, ay = anchorXY(rr, p.relPoint or p.point)
      ax, ay = ax + (p.x or 0), ay + (p.y or 0)
      if p.point:find("LEFT") then
        l = ax
      elseif p.point:find("RIGHT") then
        rgt = ax
      else
        cx = ax
      end
      if p.point:find("TOP") then
        t = ay
      elseif p.point:find("BOTTOM") then
        b = ay
      else
        cy = ay
      end
    end
  end
  local w, h = ownSize(f)
  if l and rgt and f.objectType == "FontString" and Mock.measure and f.font then
    local _, th = Mock.measure(f.text or "", f.font[1], f.font[2], rgt - l, f.spacing or 0)
    h = (f.height or 0) > 0 and f.height or th -- anchored at both sides: it wraps at that width
  end
  if not (l and rgt) then
    if l then
      rgt = l + w
    elseif rgt then
      l = rgt - w
    else
      cx = cx or 0
      l, rgt = cx - w / 2, cx + w / 2
    end
  end
  if not (t and b) then
    if t then
      b = t - h
    elseif b then
      t = b + h
    else
      cy = cy or 0
      b, t = cy - h / 2, cy + h / 2
    end
  end
  local r = { l, b, rgt, t }
  memo[f] = r
  return r
end

function Mock.Layout(root)
  local memo, out = {}, {}
  local function walk(f, alpha, clip)
    if not f.shown then
      return
    end
    alpha = alpha * (f.alpha or 1)
    if f.clips or f.objectType == "ScrollFrame" then -- what lies outside is not drawn
      local r = rectOf(f, memo)
      clip = clip
          and {
            math.max(clip[1], r[1]),
            math.max(clip[2], r[2]),
            math.min(clip[3], r[3]),
            math.min(clip[4], r[4]),
          }
        or { r[1], r[2], r[3], r[4] }
    end
    local regions = {}
    for i, r in ipairs(f.regions) do
      regions[#regions + 1] = { r = r, i = i }
    end
    table.sort(regions, function(a, c)
      local la, lc = LAYERS[a.r.layer or "ARTWORK"] or 3, LAYERS[c.r.layer or "ARTWORK"] or 3
      if la ~= lc then
        return la < lc
      end
      if (a.r.sublevel or 0) ~= (c.r.sublevel or 0) then
        return (a.r.sublevel or 0) < (c.r.sublevel or 0)
      end
      return a.i < c.i
    end)
    for _, e in ipairs(regions) do
      local r = e.r
      if r.shown and r.objectType ~= "MaskTexture" and (r.layer or "ARTWORK") ~= "HIGHLIGHT" then
        local rect = rectOf(r, memo)
        out[#out + 1] = {
          kind = r.objectType,
          l = rect[1],
          b = rect[2],
          r = rect[3],
          t = rect[4],
          alpha = alpha * (r.alpha or 1),
          texture = r.texture,
          color = r.color,
          vertexColor = r.vertexColor,
          texCoord = r.texCoord,
          desaturated = r.desaturated,
          text = r.text,
          font = r.font,
          textColor = r.textColor,
          justifyH = r.justifyH,
          spacing = r.spacing,
          width = r.width,
          clip = clip,
        }
      end
    end
    local kids = {}
    for i, c in ipairs(f.children) do
      kids[#kids + 1] = { c = c, i = i }
    end
    table.sort(kids, function(a, c)
      if (a.c.level or 0) ~= (c.c.level or 0) then
        return (a.c.level or 0) < (c.c.level or 0)
      end
      return a.i < c.i
    end)
    for _, k in ipairs(kids) do
      walk(k.c, alpha, clip)
    end
  end
  walk(root, 1, nil)
  local box = rectOf(root, memo)
  return out, box
end

return Mock
