+++
title = "Commodities and their delay"
scene = "Wide view across a rainy Stormwind street at dusk: small in the middle distance, Bastian stands slumped beside a mailbox, soaked and bored, water dripping from his hair, people with umbrellas hurrying past, lamps glowing in the windows."
order = 20
levels = [1, 30]
meta = ["any auctioneer", "any level", "stacks, the queue and the payout", "alone"]
added = "2026-10-23"
updated = "2026-10-23"

[[rumours]]
claim = 116253762191202
stamp = "half"
why = "The Forever client's commodity buy list shows a price and a quantity and no seller, and the buyer only chooses how many (UI source, build 70450). Which listings the house fills first we could not see."

[[rumours]]
claim = 129211732426848

[[rumours]]
claim = 83900881488642

[[rumours]]
claim = 263972737147556

[[rumours]]
claim = 83519129064757

[plate]
kind = "flow"
nodes = [
  { glyph = "item", title = "the whole pile", note = "one post, one deposit" },
  { glyph = "auctioneer", title = "one queue", note = "match the cheapest" },
  { glyph = "waiting", title = "about an hour", note = "then the gold", tint = "warn" },
]
foot = { glyph = "gold", text = "a single weapon paid out in two minutes", tint = "good" }

[live]
kind = "prices"
items = [2840, 2589, 3848]
+++

I sold two stacks of {item:2840} one afternoon and waited at the mailbox for the gold. It started to rain. After an hour the gold came, and by then I'd also had time to sell a knife, which paid me while I was still standing there. Nixie Brassbottom heard the story in Booty Bay. She said anyone who waits at a mailbox has too little to do, and went back to her ledger.

## Why it pays
Forever's auction house treats anything that stacks in your bags as a commodity, as far as the travellers can tell, so cloth, bars, herbs and dust all count. A commodity doesn't sell as separate auctions. Every listing of one item goes into one queue, a buyer says how many he wants, and the house sells him the cheapest. The buyer never sees who he buys from. Weapons, armour and anything else that doesn't stack still sell one auction at a time.

Three things follow, and each one is worth money. You post the whole pile at once, and one post costs one deposit, so a stack of cheap dust costs the same silver as a single one. You never need to undercut by a copper. One traveller found that among listings at the same price the newest one sells first, so matching the cheapest price puts you at the front of the line, and going a copper under only costs you a copper on every item. And the gold comes at different speeds. In the beta, commodity gold took about an hour to arrive, and a single {item:3848} paid out in about two minutes.

{plate}

## How
1. Put everything you have of one item into a single post.
2. Look at the cheapest price in the queue and match it. Go lower only when you want your whole pile gone before everybody else at that price.
3. Sell, then go and do something useful. Commodity gold arrives about an hour later.
4. When you need gold back quickly to buy the next lot, sell single items. A weapon or a piece of armour pays in minutes.
5. Buying works the same way backwards. Ask for the number you need and look at the total before you click.

{live}

## What can go wrong
The hour and the two minutes come from one traveller in September, early in the beta, and he wondered himself whether the fast payout was a mistake. The order of the queue comes from the same man. The market is large and quick, too. The export counts thousands of Copper Bars sold a day on a single market, so the cheapest price you matched at noon may be gone by the time you've walked to the auctioneer.

## Verdict
Match the cheapest price, post the whole pile at once and come back for the gold in an hour.
