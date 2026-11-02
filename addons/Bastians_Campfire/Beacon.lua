-- The beacon of Bastian's Campfire (campfire.md "The beacon", decision B): "Share the fire" sends
-- the fire's place to the group and the guild through Core's Comm (kind "camp",
-- docs/architecture/addon-messages.md); every Bastian's user in reach gets a fire pin on the map
-- and the minimap for an hour and a word through Words. A camp posted in chat with a map pin and
-- "camp" or "fire" becomes a faded pin. Positions only: no name is stored, the sender is never kept.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Model = ns.Model

local Beacon = {}
ns.Beacon = Beacon

local mod
local world = {} -- fire -> { continent, wx, wy } (RAM, worked out once)

local CHAT_EVENTS = {
  "CHAT_MSG_SAY",
  "CHAT_MSG_YELL",
  "CHAT_MSG_PARTY",
  "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_GUILD",
  "CHAT_MSG_CHANNEL",
}

local function fires()
  local list = mod.db.global.fires
  if type(list) ~= "table" then
    list = {}
    mod.db.global.fires = list
  end
  return list
end

local function mapName(map)
  local info = map and C_Map.GetMapInfo(map)
  return info and info.name or nil
end

-- The fires not expired, newest first (the saved list pruned in place).
function Beacon.Fires()
  local kept = Model.Prune(fires(), time())
  mod.db.global.fires = kept
  return kept
end

local function changed()
  B:Fire("BASTIANS_LAYER_CHANGED", "campfire.fires")
  B:Fire("BASTIANS_CAMP_CHANGED")
end

-- Keeps a fire (from a message, a chat line or our own share).
function Beacon.Add(fire)
  local list = fires()
  list[#list + 1] = fire
  mod.db.global.fires = Model.Prune(list, time())
  changed()
end

-- A `camp` value from another player of the suite (Comm hands it over put together and checked
-- for its form; the sender's name is not kept).
function Beacon.Receive(value)
  local fire = Model.CleanCamp(value, time())
  if not fire then
    return false
  end
  Beacon.Add(fire)
  if mod.db.profile.words then
    local zone = mapName(fire.map)
    B:Tell(
      mod,
      "reminder",
      zone and string.format(L["A friend lit a fire in %s."], zone) or L["A friend lit a fire."]
    )
  end
  B:Fire("BASTIANS_CAMP_SHARED", fire.map, fire.x, fire.y)
  return true
end

-- "Share the fire": the player's place to the group and the guild. -> the number of channels it
-- went to, or nil and why.
function Beacon.Share()
  if not mod.db.profile.beacon then
    return nil, "off"
  end
  local _, _, _, map, x, y = B.Coords.Player()
  if not (map and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then
    B:Say(L["Your place is unknown here: the fire cannot be shared."])
    return nil, "position"
  end
  local st = ns.Watch.State()
  local features = {}
  for key in pairs(st.features or {}) do
    features[#features + 1] = key
  end
  table.sort(features)
  local fire = { map = map, x = x, y = y, features = features, since = st.since }
  local payload = Model.Payload(fire, GetTime())
  local sent = 0
  local group = B.Compat.GroupChannel()
  if group and B.Comm.Send(Model.KIND, payload, group) then
    sent = sent + 1
  end
  if type(IsInGuild) == "function" and IsInGuild() and B.Comm.Send(Model.KIND, payload, "GUILD") then
    sent = sent + 1
  end
  local mine = Model.CleanCamp(payload, time())
  if mine then
    mine.mine = true
    Beacon.Add(mine)
  end
  if sent == 0 then
    B:Say(L["Nobody to share the fire with: you are in no group and no guild."])
    return nil, "nobody"
  end
  B:Say(L["You shared the fire with your group and guild."])
  return sent
end

-- The words that make a chat line with a map pin a camp.
function Beacon.Words()
  return { "camp", "fire", "campfire", L["camp"], L["fire"], L["campfire"] }
end

-- A chat line (the events above): a map pin and a camp word make a faded pin. -> true when kept.
function Beacon.OnChat(_, _, text)
  if not mod.db.profile.chatPickup then
    return false
  end
  local map, x, y = Model.ChatCamp(text, Beacon.Words())
  if not map then
    return false
  end
  Beacon.Add({ map = map, x = x, y = y, features = {}, at = time(), chat = true })
  return true
end

-- The map layer: one pin per fire on the shown continent.
local function query(view)
  local pins = {}
  for _, fire in ipairs(Beacon.Fires()) do
    local w = world[fire]
    if not w then
      local continent, wx, wy = B.Coords.ToWorld(fire.map, fire.x, fire.y)
      w = { continent, wx, wy }
      world[fire] = w
    end
    if w[1] and w[1] == view.continent then
      local minutes = math.max(0, math.floor((time() - (fire.at or 0)) / 60))
      local label = fire.chat and L["A camp posted in chat"]
        or (fire.mine and L["Your shared fire"])
        or string.format(L["A fire burns here (since %d min)"], minutes)
      pins[#pins + 1] = {
        wx = w[2],
        wy = w[3],
        icon = "campfire",
        size = fire.chat and 12 or 16,
        priority = 60,
        label = label,
        color = fire.chat and S.C.dim or nil,
      }
    end
  end
  return pins
end

function Beacon.Attach(m)
  mod = m
  world = setmetatable({}, { __mode = "k" })
  B.Comm.Register(m, Model.KIND, function(value)
    Beacon.Receive(value)
  end)
  for _, event in ipairs(CHAT_EVENTS) do
    m:RegisterEvent(event, Beacon.OnChat)
  end
  B:RegisterMapLayer(m, {
    id = "campfire.fires",
    label = L["Shared fires"],
    icon = "campfire",
    defaultOn = true,
    minLevel = 0,
    maxLevel = 8,
    query = query,
  })
end

function Beacon.Detach() end
