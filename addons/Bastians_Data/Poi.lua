-- Bastian's Data: the point-of-interest facet (ADR 0026, data.md "Points of interest"): the roles
-- a place has for a player, by rule from NPC services, object and node kinds, and the travel types.
local _, ns = ...
local B = Bastians
local Data = ns.Data

local Poi = {}
Data.Poi = Poi

local NPC_ROLES = {
  questgiver = "quest.giver",
  trainer = "trainer",
  vendor = "vendor",
  repair = "money.repair",
  flightmaster = "travel.flightmaster",
  innkeeper = "rest.inn",
  banker = "money.bank",
  auctioneer = "money.auction",
  stablemaster = "rest.stable",
  battlemaster = "pvp.battlemaster",
}

local OBJECT_ROLES = {
  mailbox = "money.mailbox",
  ["auction house"] = "money.auction",
  ["meeting stone"] = "travel.meetingstone",
  portal = "travel.portal",
  ["fishing pool"] = "gather.fish",
}

local NODE_ROLES =
  { herb = "gather.herb", ore = "gather.ore", fish = "gather.fish", treasure = "gather.treasure" }

-- "fire and forge" objects are spell foci; their names tell which (English names, both clients)
local FOCUS_WORDS = { { "anvil", "craft.anvil" }, { "forge", "craft.forge" }, { "fire", "craft.fire" } }

local function add(roles, role)
  for _, r in ipairs(roles) do
    if r == role then
      return
    end
  end
  roles[#roles + 1] = role
end

-- "Alchemy Trainer" -> "Alchemy", "First Aid Trainer" -> "First Aid"; nil otherwise (what a
-- trainer trains, for the map's labels and the summary; "I see the
-- trainer names - but not what they train").
function Poi.TrainerWords(subname)
  local words = type(subname) == "string" and subname:match("^(.-)%s+[Tt]rainer$")
  if not words or words == "" then
    return nil
  end
  return words
end

-- What a trainer or a vendor's card says it is: "Enchanter", "Alchemy Supplies" (owner, Forever
-- 08.11.2026: "we do not say what kind of trainer or vendors these are, even when we have the
-- info"); nil for anyone else, and for one without a subname.
function Poi.ServiceWords(r)
  if type(r) ~= "table" or type(r.subname) ~= "string" or r.subname == "" then
    return nil
  end
  for _, role in ipairs(Poi.Roles("npc", r)) do
    if role == "trainer" or role == "vendor" then
      return r.subname
    end
  end
  return nil
end

-- "Alchemy Trainer" -> "trainer.alchemy", "First Aid Trainer" -> "trainer.first-aid"; nil otherwise
local function trainerKind(subname)
  local words = Poi.TrainerWords(subname)
  if not words then
    return nil
  end
  return "trainer." .. words:lower():gsub("%s+", "-")
end

-- The roles of a record of the type, as an array (empty when it has none).
function Poi.Roles(typ, r)
  local roles = {}
  if not r then
    return roles
  end
  if typ == "npc" then
    local flags = r.flags -- a list, or one word (older packs, the fixture)
    if type(flags) ~= "table" then
      flags = flags and { flags } or {}
    end
    for _, flag in ipairs(flags) do
      local role = NPC_ROLES[flag]
      if role then
        add(roles, role)
      end
    end
    local kind = trainerKind(r.subname)
    if kind then
      add(roles, "trainer")
      add(roles, kind)
    end
  elseif typ == "object" then
    local role = OBJECT_ROLES[r.kind]
    if role then
      add(roles, role)
    elseif r.kind == "fire and forge" and type(r.name) == "string" then
      local name = r.name:lower()
      for _, w in ipairs(FOCUS_WORDS) do
        if name:find(w[1], 1, true) then
          add(roles, w[2])
          break
        end
      end
    end
  elseif typ == "node" then
    local role = NODE_ROLES[r.kind]
    if role then
      add(roles, role)
    end
  elseif typ == "flightpath" or typ == "taxinode" then
    add(roles, "travel.flightmaster")
  elseif typ == "transport" then
    add(roles, r.kind == "portal" and "travel.portal" or "travel.dock")
  elseif typ == "entrance" then
    add(roles, "travel.entrance")
  end
  return roles
end

local TYPES = { "npc", "object", "node", "flightpath", "transport", "entrance" }

function Poi.Attach(module)
  B:RegisterFacet(module, {
    facet = "poi",
    types = TYPES,
    priority = 100,
    invalidateOn = { "BASTIANS_DATA_LOADED" },
    rule = function(ref)
      local typ, id = B.Entity.Parse(ref)
      local data = B:GetService("data")
      local roles = Poi.Roles(typ, data and data:Get(typ, id))
      if #roles == 0 then
        return nil
      end
      return { roles = roles }
    end,
  })
end
