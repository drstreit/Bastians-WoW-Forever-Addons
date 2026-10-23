+++
title = "The deposit, the cut and the post"
order = 10
levels = [1, 30]
meta = ["any auctioneer", "any level", "what selling costs", "alone"]
added = "2026-10-23"
updated = "2026-10-23"

[[rumours]]
claim = 254221152054585

[[rumours]]
claim = 113621013321601

[[rumours]]
claim = 271789902381933
stamp = "half"
why = "The cut is taken from the sale price, so 5 % on top falls a little short. Getting 10 gold back takes 10g 53s."

[[rumours]]
claim = 5856676141194

[[rumours]]
claim = 42923752870477

[plate]
kind = "flow"
nodes = [
  { glyph = "auctioneer", title = "post it", note = "deposit, 1s at least" },
  { glyph = "done", title = "it sells", note = "deposit back, 5 % cut", tint = "good" },
  { glyph = "gold", title = "by post", note = "95 in every 100", tint = "gold" },
]
foot = { glyph = "never", text = "unsold, the deposit stays with the house", tint = "bad" }

[live]
kind = "prices"
items = [247789, 2589, 17056, 2835]
+++

The first thing I ever put on the auction house was a ring I took off a gnoll in Redridge. The auctioneer wanted a silver before he would take it, and two hours later the ring came back to me in the post without the silver. I've been more careful since, mostly because I haven't had many silvers to spare.

## Why it pays
The house takes money from a seller twice. When you post, it keeps a deposit, which the travellers say grows with what a vendor would pay for the item. If the item sells, you get the deposit back and the house keeps 5 % of the price instead. If it doesn't sell, you get the item back and the house keeps the deposit.

The deposit also has a floor. In the middle of October one traveller posted his wands without paying any deposit. A week later the travellers who tested it found every small deposit rounded up to a full silver a post. Today a {item:247789} fetches {price:247789} on your market. Post one on its own and the house holds a silver of yours until somebody buys it, and keeps it if nobody does.

The cut comes off the sale price, so a resale needs a little more than 5 % on top. When I pay 10 gold for something, I have to sell it for 10g 53s to see my 10 gold again.

{plate}

## Where
Every auctioneer in your capital sells into your own faction's market. The neutral auctioneers, such as {npc:9858} in Booty Bay, take listings from both factions and are the only place where the Horde and the Alliance trade. One traveller says the cut works differently there and doesn't say how. I haven't checked. Booty Bay sits at the bottom of {zone:1434}, past creatures of level 30 and more.

## How
1. Look at the tooltip for what a vendor pays. A big vendor price means a big deposit.
2. Take one twentieth off the price on the auction house. If what's left is less than the vendor pays, sell to the vendor.
3. At low level, sell anything that fetches only a silver or two to the vendor as well. One unsold round at the floor eats most of it.
4. Price a resale at what you paid plus a little more than one twentieth.
5. Go to a mailbox afterwards. The gold comes by post with the cut taken off, and so does anything you bought.

{live}

## What can go wrong
The floor arrived in the middle of the beta and it can change again. Most travellers put the cut at 5 %. One guessed fifteen and said he wasn't sure. Every unsold round costs the deposit again, so a high price you keep reposting can cost more than a fair one that sells on the first day.

## Verdict
Both costs are small and both are easy to forget. I add them to every price now and sell the small stuff to the vendor.
