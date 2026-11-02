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

-- A sender the spam filter never touches (ADR 0042 §7, S2): the player, a friend, a guild
-- member, someone in the group. Unknown answers count as "not known", never as a friend.
function Compat.IsTrusted(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  local me = Compat.PlayerName()
  if name == me or short(name) == short(me) and not name:find("-", 1, true) then
    return true
  end
  local friend = fn("C_FriendList.GetFriendInfo")
  if friend then
    local ok, info = pcall(friend, name)
    if ok and info then
      return true
    end
    ok, info = pcall(friend, short(name))
    if ok and info then
      return true
    end
  end
  local guild = fn("C_GuildInfo.MemberExistsByName")
  if guild then
    local ok, yes = pcall(guild, name)
    if ok and yes then
      return true
    end
  end
  for _, unitFn in ipairs({ "UnitInParty", "UnitInRaid" }) do
    local f = fn(unitFn)
    if f then
      local ok, yes = pcall(f, short(name))
      if ok and yes then
        return true
      end
    end
  end
  return false
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

function Compat.PlaySound(name)
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

function Compat.ClassColorsEverywhere()
  local f = fn("SetChatColorNameByClass")
  if not f then
    return false
  end
  for _, t in ipairs(Compat.CLASS_COLOR_TYPES) do
    pcall(f, t, true)
  end
  return true
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
  local ok, _, file = pcall(f, guid)
  if ok and type(file) == "string" and file ~= "" then
    return file
  end
  return nil
end

-- What the client knows about a whisper partner, for the Messenger's header and list (chat.md):
-- { class (file name), className, level, zone, guild, realm, online, friend }. A friend by the
-- friends list, a Battle.net friend by the account (`bnID`), a guild member by the roster, a group
-- member by the unit functions. Every part the client cannot tell stays nil, never 0 or "".
function Compat.PartnerInfo(name, bnID)
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
  return out
end
