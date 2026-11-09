"""The pricing rules, the ledger and the market's hours (gold.md "Pricing rules", "The ledger")."""

from harness import WowRuntime
from test_prices import boot

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"
MOD = "Bastians:GetModule('Gold')"
P = f"{MOD}.Pricing"
LEDGER = f"{MOD}.Ledger"
HISTORY = f"{MOD}.History"
ADV = f"{MOD}.Advisor"


def expose(wow: WowRuntime) -> WowRuntime:
    boot(wow, CORE, DATA, GOLD)
    return wow


def test_a_price_sits_in_its_range(wow: WowRuntime):
    expose(wow)
    assert (
        wow.eval(f"{P}.Position({{ median = 110, low30d = 100, high30d = 200 }})").signal == "buy"
    )
    assert (
        wow.eval(f"{P}.Position({{ median = 150, low30d = 100, high30d = 200 }})").signal == "hold"
    )
    assert (
        wow.eval(f"{P}.Position({{ median = 195, low30d = 100, high30d = 200 }})").signal == "sell"
    )
    # outside the range is its end, not an error
    assert wow.eval(f"{P}.Position({{ median = 300, low30d = 100, high30d = 200 }})").at == 1
    assert wow.eval(f"{P}.Position({{ median = 105, low30d = 100, high30d = 110 }})") is None
    assert wow.eval(f"{P}.Position({{ median = 105 }})") is None  # unknown stays unknown
    assert wow.eval(f"{P}.Position(nil)") is None


def test_a_bargain_is_a_lowest_listing_far_under_the_30_day_median(wow: WowRuntime):
    # catalog review A5.3 (07.11.2026): the buyer's side, against the 30-day median, not today's
    expose(wow)
    assert wow.eval(f"{P}.Bargain({{ median30d = 100, minBuyout = 60 }})") is True
    assert wow.eval(f"{P}.Bargain({{ median30d = 100, minBuyout = 70 }})") is False
    assert wow.eval(f"{P}.Bargain({{ median = 100, minBuyout = 60 }})") is None  # no 30-day median
    assert wow.eval(f"{P}.Bargain({{ median30d = 100 }})") is None  # no listing: unknown
    assert wow.eval(f"{P}.Bargain({{ median30d = 0, minBuyout = 1 }})") is None
    assert wow.eval(f"{P}.Bargain(nil)") is None


def test_a_dump_and_the_floor(wow: WowRuntime):
    expose(wow)
    assert wow.eval(f"{P}.Dumped({{ median = 100, minBuyout = 60 }})") is True
    assert wow.eval(f"{P}.Dumped({{ median = 100, minBuyout = 80 }})") is False
    assert wow.eval(f"{P}.Dumped({{ median = 100 }})") is False
    assert wow.eval(f"{P}.Floor(95)") == 100  # 100 less the 5 % cut brings 95 back
    assert wow.eval(f"{P}.Floor(nil)") is None


def test_a_craft_counts_what_it_does_not_know(wow: WowRuntime):
    expose(wow)
    wow.execute("price = { [1] = 10, [2] = 30, [9] = 100 }; of = function(i) return price[i] end")
    known = wow.eval(
        f"{P}.Craft({{ item = 9, count = 2, reagents = {{ {{ 1, 3 }}, {{ 2, 1 }} }} }}, of)"
    )
    assert (known.cost, known.missing, known.net, known.profit, known.unit) == (60, 0, 190, 130, 30)
    open_ = wow.eval(f"{P}.Craft({{ item = 9, reagents = {{ {{ 1, 1 }}, {{ 7, 1 }} }} }}, of)")
    assert open_.cost == 10 and open_.missing == 1 and open_.profit is None
    nobody = wow.eval(f"{P}.Craft({{ item = 8, reagents = {{ {{ 1, 1 }} }} }}, of)")
    assert nobody.net is None and nobody.profit is None
    # a proc gives more than the recipe's count
    proc = wow.eval(
        f"{P}.Craft({{ item = 9, reagents = {{ {{ 1, 1 }} }} }}, of, {{ yield = 1.4 }})"
    )
    assert proc.net == 133


def test_disenchanting_is_the_materials_expected_value(wow: WowRuntime):
    expose(wow)
    wow.execute("price = { [1] = 100, [2] = 200 }; of = function(i) return price[i] end")
    wow.execute(
        f"V, M = {P}.Disenchant({{ {{ 1, 50, 1, 3 }}, {{ 2, 25, 1, 1 }}, {{ 3, 5, 1, 1 }} }}, of)"
    )
    assert wow.eval("V") == 143  # (0.5 * 2 * 100 + 0.25 * 200) * 0.95, rounded
    assert wow.eval("M") == 1  # item 3 has no price


def test_the_advisor_keeps_below_cost_and_waits_out_a_dump(wow: WowRuntime):
    expose(wow)
    below = wow.eval(f"{ADV}.Advise({{ count = 1, cost = 200, price = {{ median = 100 }} }})")
    assert below.verdict == "keep" and "you paid" in below.reason
    dump = wow.eval(f"{ADV}.Advise({{ count = 1, price = {{ median = 100, minBuyout = 50 }} }})")
    assert dump.verdict == "keep" and "wait" in dump.reason
    stale = wow.eval(
        f"{ADV}.Advise({{ count = 1, price = {{ median = 100, minBuyout = 50, stale = true }} }})"
    )
    assert stale.verdict == "post"  # an old scan's lowest listing says nothing about today


def inbox(wow: WowRuntime, *rows: str) -> None:
    wow.execute("Mock.inbox = { " + ", ".join(rows) + " }")


SOLD = "{ invoice = { kind = 'seller', item = 'Linen Cloth', buyer = 'Someone', bid = 100, consignment = 5, deposit = 7, count = 20 } }"
BOUGHT = "{ invoice = { kind = 'buyer', item = 'Linen Cloth', buyer = 'Someone', bid = 40, count = 10 } }"
PENDING = (
    "{ invoice = { kind = 'seller_temp_invoice', item = 'Linen Cloth', bid = 100, count = 20 } }"
)


def test_an_invoice_is_booked_once_and_alike_sales_are_each_booked(wow: WowRuntime):
    expose(wow)
    inbox(wow, SOLD, SOLD, BOUGHT, PENDING, "{ money = 5 }")
    assert wow.eval(f"{LEDGER}.Scan(1000000)") == 3
    assert wow.eval(f"{LEDGER}.Scan(1000000)") == 0  # the mails still wait
    assert wow.eval(f"{LEDGER}.AvgBuy('Linen Cloth')") == 4
    it = next(iter(wow.eval(f"{LEDGER}.Items()").values()))
    assert (it.figures.sold, it.figures.bought) == (40, 10)
    assert it.figures.avgSell == 4.75 and it.figures.profit == 30  # 190 earned, 40 units at 4
    wow.execute(f"E, S = {LEDGER}.Totals()")
    assert (wow.eval("E"), wow.eval("S")) == (190, 40)
    assert "Someone" not in str(wow.eval(f"{MOD}.db.global.ledger"))
    book = wow.eval(f"{MOD}.db.global.ledger[{HISTORY}.Key()]")
    assert all("Someone" not in str(k) for k in book.seen)
    assert wow.errors == []


def test_looted_goods_have_no_cost_of_zero(wow: WowRuntime):
    expose(wow)
    inbox(wow, SOLD)
    wow.execute(f"{LEDGER}.Scan(1000000)")
    assert wow.eval(f"{LEDGER}.AvgBuy('Linen Cloth')") is None
    it = next(iter(wow.eval(f"{LEDGER}.Items()").values()))
    assert it.figures.profit is None and it.figures.avgSell == 4.75


def test_the_market_level_needs_enough_shared_items(wow: WowRuntime):
    expose(wow)
    wow.execute(
        """
        items, parts = {}, {}
        for i = 1, 20 do
          items[i] = { median = 110 }
          parts[i] = i .. ":100"
        end
        line = ";" .. table.concat(parts, ";") .. ";"
        """
    )
    assert abs(wow.eval(f"{HISTORY}.Level(items, line)") - 1.1) < 1e-9
    assert wow.eval(f"{HISTORY}.Level(items, ';1:100;')") is None


def test_the_hours_show_from_two_scans_and_name_the_best(wow: WowRuntime):
    expose(wow)
    wow.execute(
        f"""
        local h = {{ days = {{ [10] = "" }}, ts = {{}} }}
        local g = {MOD}.db.global
        g.history = g.history or {{}}
        g.history[{HISTORY}.Key()] = h
        h.hours = {{ [25] = {{ n = 2, sum = 2.2 }}, [26] = {{ n = 2, sum = 2.0 }},
          [50] = {{ n = 2, sum = 1.9 }}, [51] = {{ n = 1, sum = 5 }} }}
        """
    )
    hours = list(wow.eval(f"{HISTORY}.Hours()").values())
    assert [h.slot for h in hours] == [25, 26, 50]  # one scan is no pattern
    rows = list(wow.eval(f"{HISTORY}.HourRows()").values())
    assert "Mon 01:00 (+10 %)" in rows[0].text
    assert wow.errors == []
