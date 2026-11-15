-- Bastian's Chat, its client wrappers (chat.md "Client wrappers"): every chat API the app calls,
-- measured on retail 12.1.5.70688 by the CH0 spike (31.10.2026), assumed on Forever. They move into
-- Core as Compat/Chat.lua when the app is merged; until then this branch never changes Core.
local _, ns = ...
local B = Bastians

local Compat = {}
ns.Compat = Compat

local function fn(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then
      return nil
    end
    v = rawget(v, part)
  end
  return type(v) == "function" and v or nil
end

-- A secret value is unknown to us (forever-api.md "Secret values").
function Compat.Plain(v)
  return B.Compat.Plain(v)
end

function Compat.IsSecret(v)
  local check = fn("issecretvalue")
  return check ~= nil and check(v) == true
end

-- The command of the channel a bar sends to, from its attributes: "/p", "/w Name", "/2"; nil when
-- the client names no command for its chat type (the game's SLASH_<TYPE>1 globals; Chattynator
-- reads them the same way). Assumed on Forever, probe X14.
function Compat.ChatHead(box)
  local ok, chatType = pcall(box.GetAttribute, box, "chatType")
  if not ok or type(chatType) ~= "string" then
    return nil
  end
  local function attr(name)
    local fine, v = pcall(box.GetAttribute, box, name)
    v = fine and Compat.Plain(v) or nil
    return (type(v) == "string" or type(v) == "number") and tostring(v) or nil
  end
  if chatType == "CHANNEL" then
    local target = attr("channelTarget")
    return target and ("/" .. target) or nil
  end
  local slash = rawget(_G, "SLASH_" .. chatType .. "1")
  if type(slash) ~= "string" then
    return nil
  end
  if chatType == "WHISPER" then
    local target = attr("tellTarget")
    return target and (slash .. " " .. target) or nil
  end
  return slash
end

-- The client's check whether a slash command is secure (/cast, /use), or nil when it has none.
function Compat.SecureCmdCheck()
  local f = fn("IsSecureCmd")
  if not f then
    return nil
  end
  return function(cmd)
    local ok, v = pcall(f, cmd)
    return ok and v == true
  end
end

-- The client's chat lockdown (retail's encounters, where chat is secret): true while it holds;
-- false where the client has no such call.
function Compat.ChatLockdown()
  local f = fn("C_ChatInfo.InChatMessagingLockdown")
  if not f then
    return false
  end
  local ok, v = pcall(f)
  return ok and v == true
end

function Compat.AddFilter(event, filter)
  local add = fn("ChatFrame_AddMessageEventFilter") or fn("ChatFrameUtil.AddMessageEventFilter")
  if add then
    add(event, filter)
    return true
  end
  return false
end

function Compat.RemoveFilter(event, filter)
  local remove = fn("ChatFrame_RemoveMessageEventFilter") or fn("ChatFrameUtil.RemoveMessageEventFilter")
  if remove then
    remove(event, filter)
  end
end

-- The game's chat frames by name: ChatFrame1..N and the whisper windows it opened (CHAT_FRAMES).
function Compat.ChatFrameNames()
  local names, seen = {}, {}
  local function add(n)
    if not seen[n] and type(rawget(_G, n)) == "table" then
      seen[n] = true
      names[#names + 1] = n
    end
  end
  for i = 1, (tonumber(rawget(_G, "NUM_CHAT_WINDOWS")) or 10) do
    add("ChatFrame" .. i)
  end
  local list = rawget(_G, "CHAT_FRAMES")
  if type(list) == "table" then
    for _, n in ipairs(list) do
      add(n)
    end
  end
  return names
end

-- The frame of the combat log (its lines are not chat lines), or nil. COMBATLOG exists only once
-- Blizzard_CombatLog has loaded (on demand); ChatFrame2 is the combat log in the retail family before
-- that (IsCombatLog in FloatingChatFrame.lua, 12.1.5.70688).
function Compat.CombatLogFrame()
  return rawget(_G, "COMBATLOG") or rawget(_G, "ChatFrame2")
end

-- Every other part of the game's chat that the replacement hides.
Compat.CHAT_PARTS = {
  "GeneralDockManager",
  "ChatFrameMenuButton",
  "ChatFrameChannelButton",
  "QuickJoinToastButton",
  "ChatFrameToggleVoiceDeafenButton",
  "ChatFrameToggleVoiceMuteButton",
  "ChatAlertFrame",
}

-- C_ChatInfo.SendChatMessage on retail 12.x, the global before it.
function Compat.SendChat(text, chatType, target)
  local send = fn("C_ChatInfo.SendChatMessage") or fn("SendChatMessage")
  if not send then
    return false
  end
  send(text, chatType, nil, target)
  return true
end

-- Opens the game's bar with a text ("/w Name ").
function Compat.OpenChat(text)
  local open = fn("ChatFrame_OpenChat") or fn("ChatFrameUtil.OpenChat")
  if open then
    open(text)
  end
end

-- The game's bar on a Battle.net friend (their name is the client's protected string, so "/w" does
-- not take it): the client's own call; false when it has none.
function Compat.OpenBNetChat(name)
  local tell = fn("ChatFrame_SendBNetTell") or fn("ChatFrameUtil.SendBNetTell")
  if tell and name then
    pcall(tell, name)
    return true
  end
  return false
end

-- A link into the open bar (Shift+click); false when no bar is open.
function Compat.InsertLink(link)
  local insert = fn("ChatEdit_InsertLink") or fn("ChatFrameUtil.InsertLink")
  return insert ~= nil and insert(link) and true or false
end

-- The game's handling of a link click (tooltips for items, quests, spells).
function Compat.ItemRef(link, text, button, frame)
  local ref = fn("SetItemRef")
  if ref then
    ref(link, text, button, frame)
  end
end

-- The game's chat font object (ChatFontNormal), or the game's normal font.
function Compat.ChatFont()
  return rawget(_G, "ChatFontNormal") or rawget(_G, "GameFontNormal")
end

-- The game's first chat frame, where its chat sits on the screen.
function Compat.MainChatFrame()
  return rawget(_G, "ChatFrame1")
end

-- Shift+click on a link (the player's binding for chat links).
function Compat.IsLinkClick()
  local f = fn("IsModifiedClick")
  if f then
    return f("CHATLINK") and true or false
  end
  return IsShiftKeyDown() and true or false
end

function Compat.DeactivateChat(box)
  local f = fn("ChatEdit_DeactivateChat") or fn("ChatFrameUtil.DeactivateChat")
  if f then
    f(box)
  end
end

-- A post-hook on a global function of the game's chat, when the client has it. `name` may be a
-- path ("ChatFrameUtil.ActivateChat": retail 12.x calls that one, no longer ChatEdit_ActivateChat).
function Compat.HookGlobal(name, hook)
  if not fn(name) then
    return false
  end
  local owner, key = name:match("^(.+)%.([^%.]+)$")
  if owner then
    hooksecurefunc(rawget(_G, owner), key, hook)
  else
    hooksecurefunc(name, hook)
  end
  return true
end

-- A callback of the client's EventRegistry ("ChatFrame.OnEditBoxShow", retail 12.1.5 source),
-- when it has one. `cb` gets the callback's arguments as the registry passes them.
function Compat.OnRegistryEvent(event, cb, owner)
  local reg = rawget(_G, "EventRegistry")
  if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
    reg:RegisterCallback(event, cb, owner)
    return true
  end
  return false
end

-- The input bars of the game's chat frames (ChatFrameNEditBox).
function Compat.EditBoxes()
  local out = {}
  for _, name in ipairs(Compat.ChatFrameNames()) do
    local box = rawget(_G, name .. "EditBox")
    if type(box) == "table" then
      out[#out + 1] = box
    end
  end
  return out
end

-- The game's own channels, offered in the tab editor even where the player has not joined them
--.
Compat.GAME_CHANNELS = { "General", "Trade", "LocalDefense", "LookingForGroup", "Services" }

-- The channels the player has joined: { { id, name } }, the name without the zone ("Trade -
-- City" is "Trade"). GetChannelList answers id, name, disabled (and on some clients more per
-- channel): every number followed by a text is one channel.
function Compat.Channels()
  local out = {}
  local list = fn("GetChannelList")
  if not list then
    return out
  end
  local t = { list() }
  local i = 1
  while i < #t + 1 do
    if type(t[i]) == "number" and type(t[i + 1]) == "string" then
      out[#out + 1] = { id = t[i], name = ns.Model.ChannelBase(t[i + 1]) }
      i = i + 2
    else
      i = i + 1
    end
  end
  return out
end

-- The editor's channels: the joined ones with their numbers, then the game's own not joined.
function Compat.ChannelChoices()
  local out, seen = {}, {}
  for _, ch in ipairs(Compat.Channels()) do
    if not seen[ch.name] then
      seen[ch.name] = true
      out[#out + 1] = ch
    end
  end
  for _, name in ipairs(Compat.GAME_CHANNELS) do
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = { name = name }
    end
  end
  return out
end

function Compat.ItemIcon(id)
  local f = fn("C_Item.GetItemIconByID") or fn("GetItemIcon")
  if f and id then
    local ok, icon = pcall(f, id)
    return ok and icon or nil
  end
  return nil
end

-- The player's own name, "Name-Realm".
function Compat.PlayerName()
  local name = UnitName("player")
  local realm = fn("GetNormalizedRealmName") and GetNormalizedRealmName() or nil
  if name and realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

local function short(name)
  return type(name) == "string" and (name:match("^([^%-]+)") or name) or nil
end

-- How the player knows `name` (plan-chat-v3.md §2.2): "self", "friend", "guild", "group", or
-- "stranger" when none of the client's lists holds the name; nil without a name. A friend wins
-- over the guild, the guild over the group (the whisper order, §3.2).
function Compat.Relation(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local me = Compat.PlayerName()
  if name == me or short(name) == short(me) and not name:find("-", 1, true) then
    return "self"
  end
  local friend = fn("C_FriendList.GetFriendInfo")
  if friend then
    local ok, info = pcall(friend, name)
    if ok and info then
      return "friend"
    end
    ok, info = pcall(friend, short(name))
    if ok and info then
      return "friend"
    end
  end
  local guild = fn("C_GuildInfo.MemberExistsByName")
  if guild then
    local ok, yes = pcall(guild, name)
    if ok and yes then
      return "guild"
    end
  end
  for _, unitFn in ipairs({ "UnitInParty", "UnitInRaid" }) do
    local f = fn(unitFn)
    if f then
      local ok, yes = pcall(f, short(name))
      if ok and yes then
        return "group"
      end
    end
  end
  return "stranger"
end

-- The game's answer to a request from a card (plan-chat-v3.md §3.1, probe X3: whether addon code
-- may call these is assumed). yes/no name the calls, `both` takes the answer as its argument, the
-- popup is the game's own window, hidden after the answer. -> true when the call ran.
local ANSWERS = {
  invite = { yes = "AcceptGroup", no = "DeclineGroup", popup = "PARTY_INVITE" },
  duel = { yes = "AcceptDuel", no = "CancelDuel", popup = "DUEL_REQUESTED" },
  trade = { no = "CloseTrade" },
  ready = { both = "ConfirmReadyCheck" },
  summon = { yes = "C_SummonInfo.ConfirmSummon", no = "C_SummonInfo.CancelSummon", popup = "CONFIRM_SUMMON" },
  resurrect = { yes = "AcceptResurrect", no = "DeclineResurrect", popup = "RESURRECT" },
}
function Compat.AnswerRequest(kind, yes)
  local a = ANSWERS[kind]
  if not a then
    return false
  end
  if a.both then
    local f = fn(a.both)
    return f ~= nil and (pcall(f, yes and true or false)) == true
  end
  local f = fn(yes and a.yes or a.no or "")
  if not f then
    return false
  end
  local ok = pcall(f)
  local hide = a.popup and fn("StaticPopup_Hide")
  if ok and hide then
    pcall(hide, a.popup)
  end
  return ok
end

-- Who summons the player (CONFIRM_SUMMON), or nil.
function Compat.Summoner()
  local f = fn("C_SummonInfo.GetSummonConfirmSummoner")
  if not f then
    return nil
  end
  local ok, name = pcall(f)
  name = ok and Compat.Plain(name) or nil
  return type(name) == "string" and name ~= "" and name or nil
end

-- A unit's player name ("NPC": the trade partner), or nil.
function Compat.UnitPlayerName(unit)
  local f = fn("UnitName")
  if not f then
    return nil
  end
  local ok, name = pcall(f, unit)
  name = ok and Compat.Plain(name) or nil
  return type(name) == "string" and name ~= "" and name or nil
end

-- The proposed answers' facts (V12), each nil when the client gives none.
-- Where the player is: the zone, the part of it (nil when none), map percent x and y.
function Compat.Where()
  local zoneFn = fn("GetRealZoneText") or fn("GetZoneText")
  local subFn = fn("GetSubZoneText")
  local zone = zoneFn and Compat.Plain(zoneFn()) or nil
  local sub = subFn and Compat.Plain(subFn()) or nil
  if type(zone) ~= "string" or zone == "" then
    zone = nil
  end
  if type(sub) ~= "string" or sub == "" or sub == zone then
    sub = nil
  end
  local x, y
  local mapFn, posFn = fn("C_Map.GetBestMapForUnit"), fn("C_Map.GetPlayerMapPosition")
  if mapFn and posFn then
    local okMap, map = pcall(mapFn, "player")
    if okMap and map then
      local okPos, pos = pcall(posFn, map, "player")
      if okPos and pos and pos.GetXY then
        local px, py = pos:GetXY()
        px, py = Compat.Plain(px), Compat.Plain(py)
        if type(px) == "number" and type(py) == "number" and (px > 0 or py > 0) then
          x, y = px * 100, py * 100
        end
      end
    end
  end
  return zone, sub, x, y
end

-- The player's item level as the game counts it (the equipped one when it gives both; probe X9).
function Compat.ItemLevel()
  local f = fn("GetAverageItemLevel")
  if not f then
    return nil
  end
  local ok, overall, equipped = pcall(f)
  local v = ok and Compat.Plain(equipped or overall) or nil
  return type(v) == "number" and v > 0 and math.floor(v + 0.5) or nil
end

-- Whether the game marks the player AFK (V20, probe X12); nil when the client does not say.
function Compat.IsAFK()
  local f = fn("UnitIsAFK")
  if not f then
    return nil
  end
  local ok, v = pcall(f, "player")
  if not ok then
    return nil
  end
  v = Compat.Plain(v) -- not `ok and Plain(v) or nil`: that turns a false into nil
  if v == nil then
    return nil
  end
  return v and true or false
end

function Compat.PlayerLevel()
  local f = fn("UnitLevel")
  local v = f and Compat.Plain(f("player")) or nil
  return type(v) == "number" and v > 0 and v or nil
end

-- Is the player in a raid (the Group place's input line writes /ra, else /p)?
function Compat.InRaid()
  local raid = fn("IsInRaid")
  return raid ~= nil and Compat.Plain(raid()) == true
end

-- A bar's chat type and whisper target from its attributes (a person's draft, plan-chat-one-window
-- §3.1), nil each where the bar has none.
function Compat.BarTarget(box)
  local function attr(name)
    local ok, v = pcall(box.GetAttribute, box, name)
    v = ok and Compat.Plain(v) or nil
    return type(v) == "string" and v or nil
  end
  return attr("chatType"), attr("tellTarget")
end

-- Is `name` in the player's party or raid?
function Compat.Grouped(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  for _, unitFn in ipairs({ "UnitInParty", "UnitInRaid" }) do
    local f = fn(unitFn)
    if f then
      local ok, yes = pcall(f, short(name))
      if ok and Compat.Plain(yes) then
        return true
      end
    end
  end
  return false
end

-- How many are in the player's group, the player included; nil outside a group or where the
-- client does not say.
function Compat.GroupSize()
  local inGroup, count = fn("IsInGroup"), fn("GetNumGroupMembers")
  if inGroup and Compat.Plain(inGroup()) ~= true then
    return nil
  end
  local n = count and Compat.Plain(count()) or nil
  return type(n) == "number" and n > 0 and n or nil
end

-- Is the player's group full (5 in a party, 40 in a raid)? False outside a group.
function Compat.GroupFull()
  local count, raid = fn("GetNumGroupMembers"), fn("IsInRaid")
  local n = count and Compat.Plain(count()) or nil
  if type(n) ~= "number" then
    return nil
  end
  return n >= ((raid and raid()) and 40 or 5)
end

-- How many of an item the bags hold, or nil.
function Compat.ItemCount(itemID)
  local f = fn("C_Item.GetItemCount") or fn("GetItemCount")
  if not f then
    return nil
  end
  local ok, n = pcall(f, itemID)
  n = ok and Compat.Plain(n) or nil
  return type(n) == "number" and n or nil
end

-- The player's situation for the plates: { combat, dead, instance }.
function Compat.Situation()
  local dead = fn("UnitIsDeadOrGhost")
  local taxi = fn("UnitOnTaxi") -- V23, probe X12
  return {
    combat = InCombatLockdown() == true,
    dead = dead ~= nil and dead("player") == true,
    instance = Compat.InstanceKind() ~= nil,
    flight = taxi ~= nil and Compat.Plain(taxi("player")) == true,
  }
end

-- The player's guild, or nil outside one (or before the client knows it).
function Compat.GuildName()
  local f = fn("GetGuildInfo")
  if not f then
    return nil
  end
  local ok, name = pcall(f, "player")
  name = ok and Compat.Plain(name) or nil
  return type(name) == "string" and name ~= "" and name or nil
end

-- A sender the spam filter never touches (ADR 0042 §7, S2): the player, a friend, a guild
-- member, someone in the group. Unknown answers count as "not known", never as a friend.
function Compat.IsTrusted(name)
  local rel = Compat.Relation(name)
  return rel ~= nil and rel ~= "stranger"
end

-- A Battle.net whisper (C_BattleNet.SendWhisper on retail 12.x, BNSendWhisper before).
function Compat.SendBNet(accountID, text)
  local f = fn("C_BattleNet.SendWhisper") or fn("BNSendWhisper")
  if f and accountID then
    f(accountID, text)
    return true
  end
  return false
end

-- The game's sounds by our names (SOUNDKIT where the client has it; the numbers are retail's).
local SOUNDS = { whisper = 3081, bell = 18019, chime = 3175, alarm = 8959 }
local SOUNDKIT_NAMES = { whisper = "TELL_MESSAGE", alarm = "RAID_WARNING" }
Compat.SOUND_NAMES = { "none", "whisper", "bell", "chime", "alarm" }

-- Every sound to choose (V25): the chat's own, and LibSharedMedia's as "lsm:<name>".
function Compat.SoundChoices()
  local L = ns.L
  local out = {}
  for _, s in ipairs(Compat.SOUND_NAMES) do
    out[s] = L["sound: " .. s]
  end
  for _, name in ipairs(B.UI.Style.MediaNames("sound")) do
    out["lsm:" .. name] = name .. " (SharedMedia)"
  end
  return out
end

function Compat.PlaySound(name)
  if type(name) == "string" and name:sub(1, 4) == "lsm:" then
    local path = B.UI.Style.Media("sound", name:sub(5)) -- LibSharedMedia's (V25)
    local file = fn("PlaySoundFile")
    if path and file then
      pcall(file, path, "Master")
      return true
    end
    return false
  end
  local kit = rawget(_G, "SOUNDKIT")
  local id = type(kit) == "table" and SOUNDKIT_NAMES[name] and kit[SOUNDKIT_NAMES[name]] or SOUNDS[name]
  local play = fn("PlaySound")
  if id and play then
    pcall(play, id, "Master")
    return true
  end
  return false
end

-- Names in class colours in every player chat type (the client's own per-type setting).
Compat.CLASS_COLOR_TYPES = {
  "SAY",
  "YELL",
  "EMOTE",
  "WHISPER",
  "PARTY",
  "PARTY_LEADER",
  "RAID",
  "RAID_LEADER",
  "RAID_WARNING",
  "INSTANCE_CHAT",
  "INSTANCE_CHAT_LEADER",
  "GUILD",
  "OFFICER",
  "CHANNEL1",
  "CHANNEL2",
  "CHANNEL3",
  "CHANNEL4",
  "CHANNEL5",
  "CHANNEL6",
  "CHANNEL7",
  "CHANNEL8",
  "CHANNEL9",
  "CHANNEL10",
}

function Compat.SetClassColors(on)
  local f = fn("SetChatColorNameByClass")
  if not f then
    return false
  end
  for _, t in ipairs(Compat.CLASS_COLOR_TYPES) do
    pcall(f, t, on and true or false)
  end
  return true
end

-- Are names in class colours in every player chat type? Nil where the client does not say.
function Compat.ClassColors()
  local info = rawget(_G, "ChatTypeInfo")
  if type(info) ~= "table" then
    return nil
  end
  local known = false
  for _, t in ipairs(Compat.CLASS_COLOR_TYPES) do
    local e = info[t]
    if type(e) == "table" then
      known = true
      if Compat.Plain(e.colorNameByClass) ~= true then
        return false
      end
    end
  end
  return known and true or nil
end

-- "party", "raid" inside an instance of that kind, else nil.
function Compat.InstanceKind()
  local f = fn("IsInInstance")
  if not f then
    return nil
  end
  local inside, kind = f()
  if inside and (kind == "party" or kind == "raid") then
    return kind
  end
  return nil
end

-- Hyperlinks on a plain frame's font strings (retail family: every frame has it).
function Compat.EnableLinks(frame)
  if type(frame.SetHyperlinksEnabled) == "function" then
    pcall(frame.SetHyperlinksEnabled, frame, true)
    return true
  end
  return false
end

function Compat.Invite(name)
  local f = fn("C_PartyInfo.InviteUnit") or fn("InviteUnit")
  if f then
    f(name)
  end
end

function Compat.AddFriend(name)
  local f = fn("C_FriendList.AddFriend")
  if f then
    f(name)
  end
end

function Compat.Ignore(name)
  local f = fn("C_FriendList.AddIgnore")
  if f then
    f(name)
  end
end

function Compat.Who(name)
  local f = fn("C_FriendList.SendWho")
  if f then
    f('n-"' .. name .. '"')
  end
end

-- The class file name ("MAGE") of a player's GUID, nil when the client does not know it.
local function classOfGuid(guid)
  local f = fn("GetPlayerInfoByGUID")
  if not (f and type(guid) == "string" and guid ~= "") then
    return nil
  end
  local ok, localized, file = pcall(f, guid)
  if ok and type(file) == "string" and file ~= "" then
    return file, type(localized) == "string" and localized ~= "" and localized or nil
  end
  return nil
end

-- The unit a player is now, by name (V26: a face the game can draw): the group by name, the
-- target, the focus, the mouse over; nil when the game has no unit for them.
function Compat.UnitOf(name)
  local nameOf, exists = fn("GetUnitName"), fn("UnitExists")
  if type(name) ~= "string" or name == "" or not (nameOf and exists) then
    return nil
  end
  local want = short(name)
  local function same(unit)
    local ok, full = pcall(nameOf, unit, true)
    full = ok and Compat.Plain(full) or nil
    return type(full) == "string" and (full == name or short(full) == want)
  end
  for _, unit in ipairs({ "target", "focus", "mouseover" }) do
    local ok, there = pcall(exists, unit)
    if ok and Compat.Plain(there) and same(unit) then
      return unit
    end
  end
  for i = 1, 4 do
    local unit = "party" .. i
    local ok, there = pcall(exists, unit)
    if ok and Compat.Plain(there) and same(unit) then
      return unit
    end
  end
  for i = 1, 40 do
    local unit = "raid" .. i
    local ok, there = pcall(exists, unit)
    if ok and Compat.Plain(there) and same(unit) then
      return unit
    end
  end
  return nil
end

-- The unit's portrait drawn into a texture (the game's round 2D face); false when it cannot.
function Compat.Portrait(tex, unit)
  local f = fn("SetPortraitTexture")
  if not (f and unit) then
    return false
  end
  return (pcall(f, tex, unit))
end

-- A class's colour as the client gives it (r, g, b), nil when it does not.
function Compat.ClassColor(class)
  if type(class) ~= "string" then
    return nil
  end
  local get = fn("C_ClassColor.GetClassColor")
  if get then
    local ok, c = pcall(get, class)
    if ok and type(c) == "table" and tonumber(c.r) then
      return c.r, c.g, c.b
    end
  end
  local colors = rawget(_G, "RAID_CLASS_COLORS")
  local c = type(colors) == "table" and colors[class]
  if type(c) == "table" and tonumber(c.r) then
    return c.r, c.g, c.b
  end
  return nil
end

-- What the client knows about a whisper partner, for the Messenger's header and list (chat.md):
-- { class (file name), className, level, zone, guild, realm, online, friend }. A friend by the
-- friends list, a Battle.net friend by the account (`bnID`), a guild member by the roster, a group
-- member by the unit functions. Every part the client cannot tell stays nil, never 0 or "".
function Compat.PartnerInfo(name, bnID, guid)
  local out = {}
  local function take(level, className, zone, online, class)
    out.level = (tonumber(level) or 0) > 0 and tonumber(level) or out.level
    out.className = type(className) == "string" and className ~= "" and className or out.className
    out.zone = type(zone) == "string" and zone ~= "" and zone or out.zone
    if online ~= nil then
      out.online = online and true or false
    end
    out.class = type(class) == "string" and class ~= "" and class or out.class
  end
  if bnID then
    local f = fn("C_BattleNet.GetAccountInfoByID")
    local ok, acc = pcall(f or function() end, bnID)
    local g = ok and type(acc) == "table" and acc.gameAccountInfo or nil
    if type(g) == "table" then
      take(g.characterLevel, g.className, g.areaName, g.isOnline, classOfGuid(g.playerGuid))
      out.realm = type(g.realmName) == "string" and g.realmName ~= "" and g.realmName or nil
      out.friend = true
    end
    return out
  end
  if type(name) ~= "string" or name == "" then
    return out
  end
  local friend = fn("C_FriendList.GetFriendInfo")
  if friend then
    local ok, info = pcall(friend, name)
    if not (ok and type(info) == "table") then
      ok, info = pcall(friend, short(name))
    end
    if ok and type(info) == "table" then
      take(info.level, info.className, info.area, info.connected, classOfGuid(info.guid))
      out.friend = true
    end
  end
  local count, member = fn("GetNumGuildMembers"), fn("GetGuildRosterInfo")
  if not out.className and count and member then
    local okN, n = pcall(count)
    local wantShort = short(name)
    for i = 1, okN and tonumber(n) or 0 do
      local ok, mName, _, _, level, className, zone, _, _, online, _, class = pcall(member, i)
      if ok and type(mName) == "string" and (mName == name or short(mName) == wantShort) then
        take(level, className, zone, online, class)
        local gi = fn("GetGuildInfo")
        local okG, guild = pcall(gi or function() end, "player")
        out.guild = okG and type(guild) == "string" and guild ~= "" and guild or nil
        break
      end
    end
  end
  if not out.className then
    local okC, className, class = pcall(UnitClass, short(name)) -- a group member by name
    if okC and type(className) == "string" and (UnitExists == nil or UnitExists(short(name))) then
      take(UnitLevel and UnitLevel(short(name)) or nil, className, nil, nil, class)
    end
  end
  out.realm = out.realm or name:match("%-(.+)$")
  if not out.class and guid then -- a stranger: the class from their lines' GUID (V26)
    local class, className = classOfGuid(guid)
    out.class = class or out.class
    out.className = out.className or className
  end
  return out
end
