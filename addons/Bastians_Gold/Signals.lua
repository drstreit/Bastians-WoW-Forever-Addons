-- Bastian's Gold: the market's signals as things and activities (W10 step 2, gold.md "Signals as
-- activities"): a sell or craft signal is the entity `signal:<market key>` placed at the nearest
-- auction house, with the activity facet Explore lists (route.md "Explore"); a farm signal stands
-- at its spot, an avoid signal is nothing to do.
local _, ns = ...
local B = Bastians
local L = ns.L
local Today = ns.Today

local Signals = {}
ns.Signals = Signals

Signals.ACTIVITY_KIND = { sell = "flip", craft = "craft" }
local ACTION_WORDS = { sell = "Sell %s", craft = "Craft %s", farm = "Farm %s", avoid = "Avoid %s" }

local function data()
  return B:GetService("data")
end

local function prices()
  return B:GetService("prices")
end

-- The signals of the player's market from the Market pack, as records with their ids; nil
-- without market data.
function Signals.Market()
  local d, service = data(), prices()
  local market = service and service:Market() or nil
  if not (d and market and d:PackLoaded("market")) then
    return nil
  end
  local out = {}
  for _, key in ipairs(d:Index("signal.byMarket", market.id) or {}) do
    local s = d:Get("signal", key)
    if s then
      out[#out + 1] = s
    end
  end
  return out
end

local function signal(id)
  local d = data()
  return d and d:Get("signal", id) or nil
end

local function itemName(itemID)
  if not itemID then
    return "?"
  end
  return B:Entity("item:" .. itemID):Name() or (L["Item"] .. " " .. tostring(itemID))
end

-- "Sell Linen Cloth", "Craft Light Armor Kit"
function Signals.Name(s)
  return string.format(L[ACTION_WORDS[s.action] or "%s"], itemName(s.item))
end

-- The Today context (capital, time, professions, now) from the window; the time alone without it.
local function context()
  if ns.Window and ns.Window.Context then
    return ns.Window.Context()
  end
  return { now = GetServerTime() }
end

-- The nearest auction house's places by straight line (the graph's Around needs no cache), the
-- place of a sell or a craft; {} where the data has none nearby.
function Signals.AuctionPlaces()
  local g = B:GetService("graph")
  local hits = g and g:Around("player", { roles = { "money.auction" } }, 1) or {}
  local hit = hits[1]
  if not hit then
    return {}
  end
  local out = {}
  for _, loc in ipairs(B:Entity(hit.ref):Locations()) do
    out[#out + 1] = loc
  end
  return out
end

-- The spot a farm signal points at ("spot:1" in its flags), or nil.
local function spotRef(s)
  for _, f in ipairs(s.flags or {}) do
    if f:find("^spot:") then
      return f
    end
  end
  return nil
end

function Signals.Locations(id)
  local s = signal(id)
  if not s then
    return {}
  end
  if s.action == "farm" then
    local ref = spotRef(s)
    return ref and B:Entity(ref):Locations() or {}
  end
  if Signals.ACTIVITY_KIND[s.action] then
    return Signals.AuctionPlaces()
  end
  return {}
end

-- The activity of a sell or craft signal: its minutes, its profit, the capital it binds, the day
-- it is good until; nil for farm (the spot is the activity) and avoid.
function Signals.Activity(ref)
  local _, id = B.Entity.Parse(ref)
  local s = id and signal(id)
  local kind = s and Signals.ACTIVITY_KIND[s.action]
  if not kind then
    return nil
  end
  return {
    kind = kind,
    takes = s.minutes and s.minutes * 60 or nil,
    gives = s.profit and { { kind = "copper", amount = s.profit } } or {},
    consumes = (s.capital or 0) > 0 and { { kind = "copper", amount = s.capital } } or nil,
    needs = { capital = s.capital },
    window = s.validUntil and { to = s.validUntil } or nil,
    confidence = s.confidence,
    src = s.src,
  }
end

-- The sell and craft signals Today would list for this character (not expired, affordable, the
-- profession known or unknown): what Explore asks about.
function Signals.Candidates()
  local out = {}
  local ctx = context()
  for _, s in ipairs(Signals.Market() or {}) do
    if Signals.ACTIVITY_KIND[s.action] and Today.line(s, ctx) then
      out[#out + 1] = "signal:" .. tostring(s.id)
    end
  end
  return out
end

function Signals.Register(mod)
  B:RegisterEntityType(mod, {
    type = "signal",
    priority = 100,
    name = function(id)
      local s = signal(id)
      return s and Signals.Name(s) or nil
    end,
    icon = function()
      return B.UI.IconTexture("gold")
    end,
    summary = function(id)
      local s = signal(id)
      if not s then
        return nil
      end
      local line = Today.line(s, context())
      return line and Today.reason(line) or s.rationale
    end,
    locations = Signals.Locations,
    fields = signal,
  })
  B:RegisterFacet(mod, {
    facet = "activity",
    types = { "signal" },
    priority = 100,
    invalidateOn = { "BASTIANS_PRICES_UPDATED", "BASTIANS_DATA_LOADED" },
    rule = Signals.Activity,
    list = Signals.Candidates,
  })
end
