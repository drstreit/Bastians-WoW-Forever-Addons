-- The ring of Bastian's Gestures (gestures.md): the key opens Core's ring kit at the cursor with
-- the current ring's wedges, the wheel or the second key cycles the three rings, releasing the
-- key (or a click) fires the wedge: an emote, a line of the player's own, a command, a suite
-- action, a game control, or a sub-ring in its place. Nothing fires without the player's key or
-- click.
local _, ns = ...
local B = Bastians
local L = ns.L
local Model = ns.Model
local Compat = ns.Compat

local Ring = {}
ns.Ring = Ring

local mod, kit
local page = 1 -- the ring shown (1 to Ring.Pages(): the three own rings, then the registered ones)
local stack = {} -- the sub-rings entered, innermost last
local hiddenByKey = false
local pendingShot -- a screenshot without UI: { step }

local function profile()
  return mod.db.profile
end

local function rings()
  return Model.Ensure(mod.db.global)
end

-- The rings other apps registered with Core (Bastian's Campfire's camp ring, plan-second-wave.md
-- decision F): shown after the three own rings, read from the registry each time.
local function plugins()
  return B.GetRings and B:GetRings() or {}
end

function Ring.Pages()
  return Model.RINGS + #plugins()
end

-- The registered ring shown now, or nil on an own ring.
function Ring.Plugin()
  if page > Model.RINGS and #stack == 0 then
    return plugins()[page - Model.RINGS]
  end
  return nil
end

-- The ring at the top: the entered sub-ring, else the page's ring (a registered ring as
-- { name, plugin = spec }).
function Ring.Current()
  if stack[#stack] then
    return stack[#stack]
  end
  local spec = Ring.Plugin()
  if spec then
    return { name = spec.name, plugin = spec }
  end
  if page > Model.RINGS then
    page = 1 -- the ring went away while it was shown
  end
  return rings()[page]
end

function Ring.Page()
  return page
end

local function inCombat()
  local lock = rawget(_G, "InCombatLockdown")
  return type(lock) == "function" and lock() and true or false
end

Ring.LINE_MAX = 255 -- characters of one macro line the client takes (assumed as for a typed line)

-- A command slot with a protected line (/cast, /use, /target, ...; #24, 04.11.2026): its text with
-- the placeholders filled now, for the secure button over the wedge, which runs it as a macro on
-- the player's click. Nil for any other slot, and for a text with a line too long for the client
-- (that one keeps the old way: the app reads it and refuses the protected line with a note).
function Ring.SecureText(slot)
  if not (slot and slot.kind == "command" and type(slot.text) == "string") then
    return nil
  end
  local protected = false
  for line in (slot.text .. "\n"):gmatch("(.-)\r?\n") do
    local step = Compat.ParseLine(line)
    if step and step.kind == "secure" then
      protected = true
      break
    end
  end
  if not protected then
    return nil
  end
  local text = Model.Fill(slot.text, Ring.Context())
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    if #line > Ring.LINE_MAX then
      return nil
    end
  end
  return text
end

-- Whether a slot can fire now: an action needs its app's action in the registry, a game control
-- the client's call.
function Ring.Available(slot)
  if slot and slot.kind == "macro" then
    -- a macro runs from a secure button, laid only out of combat; a gone macro is never guessed
    if not Compat.MacroExists(slot.name) then
      return false, string.format(L["Macro not found: %s"], slot.name or "")
    end
    if inCombat() then
      return false, L["Not in combat."]
    end
    return true
  end
  if slot and slot.kind == "command" and inCombat() and Ring.SecureText(slot) then
    return false, L["Not in combat."] -- its secure button is laid out of combat only
  end
  if slot and slot.kind == "game" then
    if not Model.GameDef(slot.id) or not Compat.HasGame(slot.id) then
      return false, L["Not in this client"]
    end
    return true
  end
  if not slot or slot.kind ~= "action" then
    return true
  end
  local def = Model.ActionDef(slot.id)
  if not def then
    return false, L["Unknown action"]
  end
  if def.action and not B:GetAction(def.action) then
    return false, string.format(L["Needs Bastian's %s"], def.needs or "")
  end
  return true
end

-- What the placeholders fill from: the target, the place, the character, the hour. Each fact is
-- read when a placeholder asks for it and once per line (CLAUDE.md §4.7: no work without a
-- reason); a fact the client does not give stays nil (§4.2).
local function first(...)
  return (...)
end

local FACTS = {
  target = function()
    return Compat.UnitPlayerName("target")
  end,
  name = function()
    return Compat.UnitPlayerName("player")
  end,
  zone = function()
    return Compat.Call("GetZoneText")
  end,
  area = function(ctx)
    local area = Compat.Call("GetSubZoneText")
    if area == nil or area == "" then
      return ctx.zone
    end
    return area
  end,
  race = function(ctx)
    return ctx.target and first(Compat.Call("UnitRace", "target")) or nil
  end,
  class = function(ctx)
    return ctx.target and first(Compat.Call("UnitClass", "target")) or nil
  end,
  guild = function(ctx)
    return ctx.target and first(Compat.Call("GetGuildInfo", "target")) or nil
  end,
  rp = function(ctx)
    -- the target's roleplay name (Total RP 3, MyRolePlay: msp through Core, read only); the
    -- profile is asked for when the target has none yet
    if not ctx.target then
      return nil
    end
    local rp = B.Compat.MspName("target")
    if not rp then
      B.Compat.MspRequest("target")
    end
    return rp and rp.name or nil
  end,
  myRace = function()
    return first(Compat.Call("UnitRace", "player"))
  end,
  myClass = function()
    return first(Compat.Call("UnitClass", "player"))
  end,
  faction = function()
    local token, word = Compat.Call("UnitFactionGroup", "player")
    return word or token -- the client's word for the faction, the token without one
  end,
  level = function()
    local level = tonumber((Compat.Call("UnitLevel", "player")))
    return level and level > 0 and level or nil
  end,
  sex = function()
    return Model.SexWord((Compat.Call("UnitSex", "player")))
  end,
  daytime = function()
    return Model.DayTime((Compat.Call("GetGameTime")))
  end,
}

function Ring.Context()
  local known = {}
  return setmetatable({}, {
    __index = function(ctx, key)
      local fact = FACTS[key]
      if not fact then
        return nil
      end
      if known[key] == nil then
        local value = fact(ctx)
        known[key] = (value == nil or value == "") and false or value
      end
      return known[key] or nil
    end,
  })
end

-- Sends `text` to `channel` in parts of at most 255 bytes (whispers to `to`).
local function chat(text, channel, language, to)
  local sent = false
  for _, part in ipairs(Model.Split(text)) do
    sent = Compat.SendChat(part, channel, language, to) or sent
  end
  return sent
end

-- Sends a line of the player's own: filled, split, each part to the client.
function Ring.Say(slot)
  local text = Model.Fill(slot.text, Ring.Context())
  if text == "" then
    return false
  end
  return chat(text, slot.channel or "SAY", slot.language)
end

local function playerPoint()
  local continent, wx, wy, map = B.Coords.Player()
  if not map then
    return nil
  end
  return "zone:" .. map, { continent, wx, wy, map = map }, map
end

-- the screenshot's two frames (ticking only while one is pending): the shot, then the screen back
local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self)
  if not pendingShot then
    self:Hide()
    return
  end
  pendingShot.step = pendingShot.step + 1
  if pendingShot.step == 1 then
    B.Compat.TakeScreenshot()
  elseif pendingShot.step >= 2 then
    pendingShot = nil
    self:Hide()
    if B.UI.Screen.Hidden() then
      B.UI.Screen.Toggle()
    end
  end
end)

-- The suite's actions, through Core's registry and Core's own frames only (CLAUDE.md §4.3).
function Ring.RunAction(id)
  local def = Model.ActionDef(id)
  if not def then
    return false
  end
  if id == "screen" then
    B.UI.Screen.Toggle()
    return true
  elseif id == "screenshot" then
    -- the screen cleared, the shot a frame later, the screen back a frame after
    if B.UI.Screen.Hidden() then
      return B.Compat.TakeScreenshot()
    end
    B.UI.Screen.Toggle()
    pendingShot = { step = 0 }
    ticker:Show()
    return true
  end
  local ref, point, map = playerPoint()
  if not ref then
    return false
  end
  if id == "lore" then
    return B:RunAction("voice.play", ref, { source = "gestures" })
  elseif id == "note" or id == "spot" then
    return B:RunAction(def.action, ref, { source = "gestures", point = { map, point[2], point[3] } })
  elseif def.action then
    -- home, heard, tracker: the app's action with the player's zone as the ref (S6)
    return B:RunAction(def.action, ref, { source = "gestures" })
  end
  return false
end

-- A command slot (editor v2): its text filled, then line by line: a chat line, an emote, a
-- registered slash command. ~~RunMacroText~~ is protected in the retail family (HasRestrictions in
-- both clients' API documentation: the client runs it from its secure buttons only), so the app
-- reads the lines itself; a secure command (/cast, /use, /target, ...) is refused with a note.
function Ring.RunCommand(slot)
  local text = Model.Fill(slot.text, Ring.Context())
  local target = UnitExists("target") and "target" or nil
  local ran = false
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local step = Compat.ParseLine(line)
    if step and step.kind == "chat" then
      ran = chat(step.text, step.channel, nil, step.to) or ran
    elseif step and step.kind == "emote" then
      if B.Compat.Emote(step.token, target) then
        ran = true
      elseif inCombat() then
        B:Say(L["Not in combat."])
      end
    elseif step and step.kind == "slash" then
      step.fn(step.rest, Compat.ChatEditBox())
      ran = true
    elseif step and step.kind == "client" then
      -- the client's own commands (/reload, /played, /who, ...): the chat's edit box sends them,
      -- and the chat answers an unknown one itself
      if Compat.SendToChat(step.line) then
        ran = true
      else
        B:Say(L["Unknown command: %s (the game's chat could not take it)"], step.cmd or "")
      end
    elseif step and step.kind == "secure" then
      B:Say(L["%s is a protected command: the game runs it from its own macros and buttons only."], step.cmd)
    elseif step then
      B:Say(L["Unknown command: %s"], step.cmd or "")
    end
  end
  return ran
end

-- A game control (editor v2): never in combat.
function Ring.RunGame(id)
  local def = Model.GameDef(id)
  if not def then
    return false
  end
  if inCombat() then
    B:Say(L["%s: not in combat."], L[def.label])
    return false
  end
  return Compat.RunGame(id)
end

-- After a wedge fired: a ring held on the key closes; one the key toggles stays until the key is
-- pressed again.
local function afterFire()
  if not profile().toggle then
    Ring.Close()
  end
end

-- Fires wedge `i` of the current ring.
function Ring.Fire(i, button)
  local ring = Ring.Current()
  if ring and ring.plugin then
    -- a registered ring: its owner fires (a secure wedge only from its own button's click)
    local item = kit and kit.items[i]
    if not item or item.disabled or item.secure then
      return false
    end
    afterFire()
    return ring.plugin.fire(i, item, button) and true or false
  end
  local slot = ring and ring.slots[i]
  if not slot then
    return false
  end
  if slot.kind == "ring" then
    stack[#stack + 1] = slot
    Ring.Refresh()
    return true
  end
  if not Ring.Available(slot) then
    return false
  end
  if slot.kind == "macro" or Ring.SecureText(slot) then
    return false -- only the secure button over the wedge runs it, on the player's click
  end
  afterFire()
  if slot.kind == "emote" or slot.kind == "line" or slot.kind == "command" then
    local done
    if slot.kind == "emote" then
      done = B.Compat.Emote(slot.token, UnitExists("target") and "target" or nil)
    elseif slot.kind == "line" then
      done = Ring.Say(slot)
    else
      done = Ring.RunCommand(slot)
    end
    if done then
      B:Fire("BASTIANS_GESTURE_FIRED", slot.kind) -- the welcome's "greet someone" step ticks
    end
    return done
  elseif slot.kind == "action" then
    return Ring.RunAction(slot.id)
  elseif slot.kind == "game" then
    return Ring.RunGame(slot.id)
  end
  return false
end

function Ring.Refresh()
  if not kit then
    return
  end
  local ring = Ring.Current()
  local title = ring.name or ""
  if #stack > 0 then
    title = (L["Back"] .. "\n" .. title)
  end
  kit:SetScale(profile().scale or 100)
  local items
  if ring.plugin then
    items = ring.plugin.items() or {}
  else
    items = Model.Items(ring, Ring.Available, not profile().toggle, Ring.SecureText)
  end
  kit:SetItems(items, title, page, Ring.Pages())
end

function Ring.IsOpen()
  return kit ~= nil and kit:IsShown()
end

function Ring.Open()
  if hiddenByKey or not mod:IsEnabled() then
    return false
  end
  stack = {}
  Ring.Refresh()
  kit:OpenAtCursor()
  return true
end

function Ring.Close()
  if kit then
    kit:Close()
  end
  stack = {}
end

-- The wheel or the second key: the next ring to the right (delta > 0, wheel up; owner, retail
-- 01.11.2026: "mouse up should scroll the next right, not left") or the previous one.
function Ring.Cycle(delta)
  delta = tonumber(delta) or 1
  page = ((page - 1 + (delta > 0 and 1 or -1)) % Ring.Pages()) + 1
  stack = {}
  if Ring.IsOpen() then
    Ring.Refresh()
  end
  B:Fire("BASTIANS_GESTURES_CHANGED")
end

function Ring.SetPage(n)
  page = math.max(1, math.min(Ring.Pages(), n or 1))
  stack = {}
  if Ring.IsOpen() then
    Ring.Refresh()
  end
end

-- The binding (Bindings.xml, runOnUp): held, the ring opens on "down" and fires the hovered wedge
-- on "up"; with the toggle setting, "down" opens or closes and a click fires.
function Ring.Key(keystate)
  if keystate == "down" then
    if profile().toggle and Ring.IsOpen() then
      Ring.Close()
      return
    end
    Ring.Open()
  elseif keystate == "up" and not profile().toggle then
    if Ring.IsOpen() then
      local i = kit:HoveredIndex()
      local item = i and kit.items[i]
      if item and item.secure then
        return -- a macro wedge: the release is no click, the ring stays for one (the wedge's tip)
      elseif item then
        Ring.Fire(i)
      else
        Ring.Close()
      end
    end
  end
end

-- The clear-screen key (BASTIANS_SUITE_HIDDEN): the ring closes and stays closed until it returns.
function Ring.HideByKey(hidden)
  hiddenByKey = hidden and true or false
  if hidden then
    Ring.Close()
  end
end

function Ring.HiddenByKey()
  return hiddenByKey
end

function Ring.Attach(m)
  mod = m
  page = 1
  stack = {}
  kit = kit
    or B.UI.Ring.New("BastiansGesturesRing", {
      wedges = Model.WEDGES,
      onFire = function(i, _, button)
        Ring.Fire(i, button)
      end,
      onCycle = function(delta)
        Ring.Cycle(delta)
      end,
      onSecure = function(i, item, button)
        local spec = Ring.Plugin()
        afterFire() -- the secure button ran the player's macro (or a registered ring's item)
        if spec and spec.secure then
          spec.secure(i, item, button)
        end
      end,
      onHub = function()
        if #stack > 0 then
          stack[#stack] = nil
          Ring.Refresh()
        else
          Ring.Close()
        end
      end,
    })
  Ring.kit = kit
  -- an open ring follows combat: a macro wedge dims on entering it and lights again after it
  local function follow()
    if Ring.IsOpen() then
      Ring.Refresh()
    end
  end
  m:RegisterEvent("PLAYER_REGEN_DISABLED", follow)
  m:RegisterEvent("PLAYER_REGEN_ENABLED", follow)
  -- a registered ring came or went: past the last ring the first one shows
  m:On("BASTIANS_REGISTRY_CHANGED", function(_, _, kind)
    if kind == "ring" then
      if page > Ring.Pages() then
        page, stack = 1, {}
      end
      follow()
    end
  end)
  hiddenByKey = B.UI.Screen and B.UI.Screen.Hidden() and B.UI.Screen.Hides("Gestures") or false
end

-- Whether a screenshot without UI is under way (tests).
function Ring.Pending()
  return pendingShot ~= nil
end

function Ring.Detach()
  Ring.Close()
  hiddenByKey = false
end
