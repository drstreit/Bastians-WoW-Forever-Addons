-- Craft for gold (gold.md "Craft for gold", catalog review A5.1, 07.11.2026): the view of every
-- recipe this character knows, best profit first, with the three ways to sell the product (the
-- auction house after the cut, a vendor, disenchanting) from Pricing.Ways (pure). A reagent
-- without a price makes the cost "at least" and the profit unknown: unknown is not zero.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Craft = {}
ns.Craft = Craft

Craft.VIEW = "gold.craft"
Craft.WAY_WORDS = { ah = "the auction house", vendor = "a vendor", disenchant = "disenchanting" }

local mod

-- Whether the character knows the recipe (its id is the spell id): the spell book once when the
-- client gives it, else one ask per recipe; nil when the client cannot tell.
local function knownSet()
  local known = B.Compat.KnownSpells and B.Compat.KnownSpells() or nil
  if type(known) == "table" then
    return function(id)
      return known[id] == true
    end
  end
  return function(id)
    return B.Compat.IsSpellKnown(id) == true
  end
end

-- The rows and the summary. -> rows (nil without Data), summary.
function Craft.Rows()
  local d = B:GetService("data")
  if not d then
    return nil, L["Craft for gold needs Bastian's Data."]
  end
  local Sections, Pricing = ns.Sections, ns.Pricing
  local knows = knownSet()
  local rows, withProfit = {}, 0
  for _, id in ipairs(d:Each("recipe") or {}) do
    if knows(id) then
      local recipe = d:Get("recipe", id)
      if recipe and recipe.reagents then
        local ways = Pricing.Ways(recipe, function(itemID)
          return itemID == recipe.item and Sections.MedianOf(itemID) or Sections.CostOf(itemID)
        end, Sections.SellPrice, Sections.DisenchantValue)
        local e = B:Entity("recipe:" .. id)
        local name = e:Name() or recipe.name or ("recipe:" .. id)
        local meta
        if ways.missing > 0 or not ways.best then
          meta = string.format(
            ways.missing > 0 and L["Costs at least %s; profit unknown"]
              or L["Costs %s; no price for the product"],
            B.UI.Money(ways.cost)
          )
        else
          meta = string.format(
            L["Costs %s; %s brings %s"],
            B.UI.Money(ways.cost),
            L[Craft.WAY_WORDS[ways.way]],
            B.UI.Money(ways.best)
          )
          if ways.profit and ways.profit <= 0 then
            meta = meta .. ", " .. string.format(L["loses %s"], B.UI.Money(-ways.profit))
          end
        end
        if ways.profit and ways.profit > 0 then
          withProfit = withProfit + 1
        end
        rows[#rows + 1] = {
          ref = "recipe:" .. id,
          title = name,
          icon = e:Icon(),
          meta = meta,
          text = name .. "  " .. S.H.muted .. meta .. "|r",
          value = ways.profit and ways.profit > 0 and ways.profit or nil,
          valueKind = "money",
          profit = ways.profit,
        }
      end
    end
  end
  table.sort(rows, function(a, b)
    if (a.profit ~= nil) ~= (b.profit ~= nil) then
      return a.profit ~= nil -- a known profit before an unknown one
    end
    if a.profit ~= nil and a.profit ~= b.profit then
      return a.profit > b.profit
    end
    return a.title < b.title
  end)
  local summary
  if #rows == 0 then
    summary = L["You know none of the recipes the data lists."]
  else
    summary = string.format(L["%d recipes known, %d with a profit"], #rows, withProfit)
  end
  return rows, summary
end

local function render(host)
  host:SetControls({})
  local rows, summary = Craft.Rows()
  host:SetRows(rows or {})
  host:SetSummary(summary)
end

function Craft.Open()
  return B:ShowView(Craft.VIEW)
end

function Craft.Register(module)
  mod = module
  B:RegisterView(mod, {
    id = Craft.VIEW,
    title = L["Craft for gold"],
    group = L["Gold"],
    rail = "gold", -- the Atlas's rail entry (ADR 0058)
    order = 45,
    render = render,
    summary = function()
      return L["your recipes by profit"]
    end,
    invalidateOn = { "BASTIANS_PRICES_UPDATED", "BASTIANS_DATA_LOADED" },
  })
end
