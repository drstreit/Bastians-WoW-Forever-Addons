-- The planner of Bastian's Campfire (campfire.md "The planner"): a view "Camping" in the suite's
-- window (the Browser) with the player's camp now, every feature with its benefit at the
-- character's level, the class buff it does not stack with, its profession, tier and source,
-- whether this character can place it and which other characters know it; the shared fires and
-- the camp log. A number the data does not give shows "unknown" (CLAUDE.md §4.2).
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Camp = ns.Camp
local Model = ns.Model

local Planner = {}
ns.Planner = Planner

Planner.VIEW = "campfire.planner"

local mod

-- The client's word for a profession (the locales carry the client's own names).
function Planner.SkillName(skill)
  return L[Camp.SKILLS[skill] or ""] or tostring(skill)
end

-- A benefit's value at the level as words, or "unknown".
function Planner.ValueText(benefit, values)
  if not benefit then
    return nil
  end
  if benefit.armor then
    if values.armor == nil then
      return L["unknown"]
    end
    local text = string.format(L["+%s armor"], values.armor)
    if (values.attributes or 0) > 0 then
      text = text .. ", " .. string.format(L["+%s all attributes"], values.attributes)
    end
    if (values.resistances or 0) > 0 then
      text = text .. ", " .. string.format(L["+%s resistances"], values.resistances)
    end
    return text
  end
  if values.main == nil then
    return L["unknown"]
  end
  return string.format(L[benefit.format], values.main)
end

local function context()
  local level = UnitLevel("player")
  local carried = {}
  for _, feature in ipairs(Camp.FEATURES) do
    local n = B.Compat.GetItemCount(feature.item)
    if n > 0 then
      carried[feature.item] = n
    end
  end
  local faction = UnitFactionGroup("player")
  return {
    level = type(level) == "number" and level > 0 and level or nil,
    professions = Model.Professions(B.Compat.GetProfessions(), Planner.SkillName),
    carried = carried,
    faction = faction == "Alliance" and "Alliance" or faction == "Horde" and "Horde" or nil,
  }
end

local function source(feature)
  if feature.blueprint then
    return string.format(L["Blueprint: %s"], L[feature.name])
  end
  return L["from the trainer or a quest"]
end

-- Other characters of the account that know the placement (Alts' `knowledge` service; a
-- blueprint teaches the placement, assumed until the probe).
local function others(feature)
  local knowledge = B:GetService("knowledge")
  local k = knowledge and knowledge:Known(feature.spell)
  if type(k) == "table" and type(k.alts) == "table" and #k.alts > 0 then
    return table.concat(k.alts, ", ")
  end
  return nil
end

local function featureRow(entry)
  local feature = entry.feature
  local meta = {
    string.format("%s %d", Planner.SkillName(feature.skill), feature.rank),
    string.format(L["tier %d"], feature.tier),
    source(feature),
  }
  if entry.canPlace == true then
    meta[#meta + 1] = L["you can place it"]
  end
  if entry.carried > 0 then
    meta[#meta + 1] = string.format(L["%d in your bags"], entry.carried)
  end
  local alts = others(feature)
  if alts then
    meta[#meta + 1] = string.format(L["known by %s"], alts)
  end
  local value = Planner.ValueText(entry.benefit, entry.amounts)
  if not entry.benefit then
    value = L[feature.service or "Service"]
  end
  local name = L[feature.name]
  local metaText = table.concat(meta, ", ")
  return {
    title = name,
    meta = metaText,
    text = name .. "  " .. S.H.muted .. metaText .. "|r",
    icon = B.Compat.ItemIcon(feature.item) or B.UI.IconTexture("campfire"),
    value = value,
    valueKind = "text",
  }
end

-- The camp's benefits as the group shows them (the player's own without a group).
local function campFeatures(card)
  local st = ns.Watch.State()
  local out = {}
  for key in pairs(st.features or {}) do
    out[#out + 1] = key
  end
  if #out == 0 then
    return card.have
  end
  return out
end

local function nowRows()
  local card = ns.Watch.Card()
  local rows = {}
  if #card.have > 0 then
    local left = card.left and Model.Clock(card.left) or L["unknown"]
    for _, key in ipairs(card.have) do
      rows[#rows + 1] =
        { text = ns.Card.Label(key), icon = B.UI.IconTexture("done"), value = left, valueKind = "text" }
    end
  else
    rows[#rows + 1] = { kind = "para", text = L["No camp buff on you now."] }
  end
  local ready = ns.Watch.ReadyIn()
  rows[#rows + 1] = {
    text = L["Your camp features"],
    icon = B.UI.IconTexture("waiting"),
    value = ready == nil and L["ready, or unknown"] or ready == 0 and L["ready"] or Model.Clock(ready),
    valueKind = "text",
  }
  local missing = Model.Missing(campFeatures(card))
  if #missing > 0 and #missing < #Camp.BENEFIT_ORDER - 1 then
    local words = {}
    for _, key in ipairs(missing) do
      words[#words + 1] = ns.Card.Label(key)
    end
    rows[#rows + 1] =
      { kind = "para", text = string.format(L["This camp still lacks: %s."], table.concat(words, ", ")) }
  end
  return rows
end

local function fireRows()
  local rows = {}
  local route = B:GetService("route")
  for _, fire in ipairs(ns.Beacon.Fires()) do
    local info = C_Map.GetMapInfo(fire.map)
    local zone = info and info.name or L["unknown"]
    local minutes = math.max(0, math.floor((time() - (fire.at or 0)) / 60))
    local row = {
      text = fire.chat and string.format(L["%s (posted in chat)"], zone) or zone,
      icon = B.UI.IconTexture("campfire"),
      value = string.format(L["%d min ago"], minutes),
      valueKind = "text",
    }
    if route then
      row.onClick = function()
        local continent, wx, wy = B.Coords.ToWorld(fire.map, fire.x, fire.y)
        if continent then
          route:ToPoint(continent, wx, wy, L["A fire"])
        end
      end
    end
    rows[#rows + 1] = row
  end
  return rows
end

local function logRows()
  local rows = {}
  for _, entry in ipairs(mod.db.char.log or {}) do
    local text = entry.zone or L["unknown"]
    if (entry.others or 0) > 0 then
      text = string.format(L["%s, with %d others"], text, entry.others)
    end
    rows[#rows + 1] = { text = text, value = entry.day, valueKind = "text" }
  end
  return rows
end

-- The planner's rows (tests read them without a window).
function Planner.Rows()
  local rows = {
    { kind = "section", text = L["My camp now"], children = nowRows() },
  }
  local ctx = context()
  local byBenefit, order = {}, {}
  for _, entry in ipairs(Model.Plan(ctx)) do
    local key = entry.feature.benefit or "service"
    if not byBenefit[key] then
      byBenefit[key] = {}
      order[#order + 1] = key
    end
    table.insert(byBenefit[key], featureRow(entry))
  end
  for _, key in ipairs(order) do
    local benefit = Camp.BENEFITS[key]
    local title = benefit and ns.Card.Label(key) or L["Services"]
    if benefit and benefit.exclusive then
      title = title .. "  " .. S.H.muted .. string.format(L["(not with %s)"], L[benefit.exclusive]) .. "|r"
    end
    rows[#rows + 1] = { kind = "section", text = title, children = byBenefit[key] }
  end
  local fires = fireRows()
  if #fires > 0 then
    rows[#rows + 1] = { kind = "section", text = L["Shared fires"], children = fires }
  end
  local log = logRows()
  if #log > 0 then
    rows[#rows + 1] = { kind = "section", text = L["Camp log"], children = log, collapsed = true }
  end
  return rows, ctx
end

local function render(host)
  if not mod.db.profile.planner then
    host:SetControls({})
    host:SetRows({ { kind = "para", text = L["The planner is off: switch it on on the Campfire page."] } })
    host:SetSummary("")
    return
  end
  local rows, ctx = Planner.Rows()
  host:SetControls({
    {
      kind = "label",
      text = ctx.level and string.format(L["Values at level %d"], ctx.level) or L["Level unknown"],
    },
  })
  host:SetRows(rows)
  host:SetSummary(
    string.format(
      L["Numbers from Campfire Tooltips (GPLv3), client build %s; not yet measured by us."],
      Camp.SOURCE_BUILD
    )
  )
end

function Planner.Open()
  return B:ShowView(Planner.VIEW)
end

-- Registers the view (Core removes it with the module); with the planner off it says so.
function Planner.Register()
  B:RegisterView(mod, {
    id = Planner.VIEW,
    title = L["Camping"],
    group = L["Campfire"],
    order = 10,
    render = render,
    summary = function()
      local card = ns.Watch.Card()
      return #card.have > 0 and L["you are warm"] or L["features, buffs, fires"]
    end,
    invalidateOn = { "BASTIANS_CAMP_CHANGED", "BASTIANS_PLAYER_MOVED_ZONE" },
  })
end

function Planner.Attach(m)
  mod = m
  Planner.Register()
end
