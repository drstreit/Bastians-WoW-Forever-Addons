+++
title = "The Leather Trick"
order = 5
levels = [1, 60]
meta = ["any level"]
added = "2026-10-22"
shelf = "back"

[plate]
kind = "flow"
nodes = [
  { glyph = "cloth", title = "Linen Cloth", note = "buy cheap" },
  { glyph = "vendor", title = "a vendor", note = "pays 25c" },
]
foot = { text = "Only when the cloth is cheap." }

[table]
kind = "vendorpairs"
rows = [[2589, 2318]]

[live]
kind = "flip"
buy = 2589
sell = 2318
+++

Nixie said it works.

{table}

{plate}

{live}
