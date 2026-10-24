+++
title = "The Bandage Bargain"
scene = "Over Nixie's shoulder at her corner table in the Salty Sailor Tavern in Booty Bay: across the table Bastian proudly presents a huge armful of bandages (soft, frayed rolls of white linen cloth, not paper scrolls), chin up, expecting praise, while Nixie's quill hovers over her ledger beside the abacus and teapot; candlelight."
order = 10
levels = [1, 60]
meta = ["First Aid", "any level", "best in launch week", "no fighting at all"]
added = "2026-10-23"
updated = "2026-10-24"

[[rumours]]
claim = 214701097011033
stamp = "half"
why = "True for Mageweave and Silk. Linen and Wool bandages fetch less than their cloth."

[[rumours]]
claim = 74994738448601
stamp = "true"
why = "Both vendor prices match the item data."

[[rumours]]
claim = 160453389578959
stamp = "true"
why = "It works whenever the cloth costs less than the bandage pays."

[[rumours]]
claim = 209406339947168
stamp = "true"
why = "Simple arithmetic: buying costs no deposit and no cut."

[plate]
kind = "flow"
nodes = [
  { glyph = "cloth", title = "Silk Cloth", note = "buy below 2s" },
  { glyph = "bandage", title = "Silk Bandage", note = "First Aid 150", tint = "good" },
  { glyph = "vendor", title = "any vendor", note = "pays 2s each", tint = "gold" },
]
foot = { text = "Linen and Wool: the vendor pays less for the bandage than for the cloth" }

[table]
kind = "vendorpairs"
rows = [[2589, 1251], [2592, 3530], [4306, 6450], [4338, 8544]]

[live]
kind = "flip"
buy = 4306
sell = 6450
+++

Nixie Brassbottom sold me this one in Booty Bay for two silver. She runs the rumour trade from a table at the back of the Salty Sailor and she's better at gold than anyone I know. She said cloth makes more money as bandages than as cloth. I spent an evening at the inn in Ironforge turning a bank slot of Linen into bandages, sold them to a vendor and made less than the Linen would have made on its own. When I complained, Nixie charged me another silver to explain what I'd done wrong, and wrote it under the other ten. She has promised me a good place at the unveiling of my statue, so I think of the eleven silver as a ticket.

## Why it pays, and when it doesn't
A vendor pays a fixed price for each item and doesn't care how many you bring. For Linen and Wool the bandage sells for less than the cloth you made it from, so each one loses a few copper. From Silk upwards it goes the other way.

{table}

So the trick works with Silk and Mageweave, and only while the cloth is cheap on the auction house. When {item:4306} sells there for less than {vendor:6450}, every {item:6450} you make from it sells to a vendor for {vendor:6450}. That happens when a server is new and everyone empties their bags on the same day.

{plate}

## What you need
First Aid 150 for Silk Bandages, which any First Aid trainer teaches. Mageweave Bandages need First Aid 210, the Expert First Aid book for one gold and the manual for fifty silver. {npc:2805} in the Arathi Highlands sells both to the Alliance, {npc:13476} in Dustwallow Marsh to the Horde. You also need money for the cloth and a lot of patience. A second character who waits in town is better. I've stood guard on a grain barge and this is duller.

## How
1. Watch {item:4306} on the auction house. Today it sells for {price:4306}. Anything under {vendor:6450} a piece is worth buying.
2. Buy it. The auction house charges the buyer no deposit and no cut.
3. Make all the bandages in one go and do something else while it runs.
4. Sell them to any vendor.
5. With your own Silk, look at the auction house first. After the cut, Silk that sells for more than about 2s 10c makes more as cloth.

{live}

## What can go wrong
Other people watch the same videos, and in launch week the cheap Silk goes early in the day. Linen and Wool bandages lose money at the vendor. Keep them for levelling First Aid or for staying alive. I sold three stacks of Linen Bandages before I understood that.

## Verdict
A trick for the first week of a new server and nothing more. It's also the one page in this book where nothing can kill you.
