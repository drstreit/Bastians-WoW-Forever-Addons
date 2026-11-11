-- What's new of Bastian's Gold (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.2.0:1",
    date = "2026-11-11",
    version = "2.2.0",
    text = "Gold's ledger now books your auction house sales and purchases when you open the mailbox; it raised an error instead.",
  },
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Items whose cheapest listing is far under their 30-day median are marked as a bargain.",
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = '"Craft for gold" lists the recipes you know by profit, with the best way to sell each product.',
  },
  {
    id = "2.1.0:3",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A farm spot's page shows your own gold per hour there after twenty kills, beside the guide's figure.",
  },
  {
    id = "2.1.0:4",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A farm spot without a known gold rate says so once, and the text is no longer cut off.",
  },
  {
    id = "2.1.0:5",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Gold's new Bargains tab lists the items selling far under their usual price.",
  },
  {
    id = "2.0.0:1",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Gold finds the market prices on the live EU RP realm.",
  },
  {
    id = "2.0.0:2",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Gold shows craft margins, disenchant value, whether a price is high or low in its range, a ledger of your sales and purchases, the market's best hours, and prices from AHledger, Auctionator or TSM when you have them.",
  },
  {
    id = "1.4.0:1",
    date = "2026-11-04",
    version = "1.4.0",
    text = "An item's price page shows a small chart of the prices your own auction house scans saw over the last two weeks.",
  },
}
