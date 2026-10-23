-- Compat layer "retail": where retail 12.x restricts or changes what we call (ADR 0010). Empty until the
-- retail probe (roadmap B1.6) shows a deviation from the modern layer; the file keeps the layer order.
local _, ns = ...
local B = ns.B

if B.Client ~= "retail" then
  return
end

-- No overrides yet. Add `define("retail", name, fn)` entries here with the measured reason and date.
