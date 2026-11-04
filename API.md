# Bastian's Suite: the API for addon authors

Your addon can ask Bastian's Suite for what it knows: item prices, quest states, the active route,
travel times. It can also hand Bastian's Route a target and listen to the suite's events. Everything
goes through one table, `Bastians.API`, version 1.

This page is the definition. Anything in `Bastians` that is not described here is internal and may
change without notice.

## Getting started

Bastian's Suite is optional for your addon. Load after it when it is there, and check before you
call:

```lua
## OptionalDeps: Bastians_Core
```

```lua
local api = Bastians and Bastians.API
if api and api.Price then
  local p = api.Price(2589) -- Linen Cloth
  if p and p.median then
    print("Linen Cloth:", GetCoinTextureString(p.median))
  end
end
```

The API exists as soon as Bastians_Core is loaded. Most answers need the suite's data, which
arrives after `PLAYER_LOGIN`: until then, and whenever an app is missing, the answer is `nil`.

## The rules

- **Versions.** `Bastians.API.VERSION` is `1`. It goes up only when a documented call or field
  changes or goes away. New calls and new fields keep the version, so test for a call before using
  it (`if api.Route then`).
- **Copies.** Every answer is a new table of strings, numbers and booleans, or a plain value. You
  may keep and change it; the suite never sees your changes.
- **Unknown is `nil`.** An app that is not installed or switched off, data that is not loaded, an
  invalid argument: the answer is `nil`, never a made-up 0. Any field of a table may be `nil` too.
- **No errors in your code.** If something fails inside the suite, the suite logs it
  (`/bastians log`) and your call gets `nil`.
- **Units.** Money is integer copper. Time is seconds. Map positions are `uiMapID, x, y` with `x`
  and `y` from 0 to 1, as `C_Map.GetPlayerMapPosition` gives them. World positions are
  `continent, wx, wy` in world yards.
- **Combat.** The calls that read touch no frame and can be used in combat. `RouteTo` does what
  the player's own "Route to" does, including showing the route.

## Calls

| Call | Answer | Needs |
|---|---|---|
| `Apps()` | `{ { name, title, version, enabled } }`: the suite's installed apps, sorted by `name`. `name` is the stable English name (`"Quests"`, `"Gold"`, `"Route"`, ...), `title` the shown one, `version` the addon's TOC version | Core |
| `IsEnabled(name)` | `true` while the app `name` runs, else `false` | Core |
| `Price(itemID)` | `{ median, minBuyout, quantity, salesPerDay, median7d, median30d, low30d, high30d, age, source, stale, label }` or `nil`. Prices in copper. `age`: seconds since the data was taken. `source`: `"scan"` (the player's own auction house scan) or `"market"` (the market data shipped with Bastian's Data). `stale`: `true` when an old own scan is all there is. `label`: the market's name | Bastian's Gold |
| `Quest(questID)` | `{ done, inLog, ready }` (booleans; `ready`: in the log and can be turned in) or `nil` until Bastian's Quests has read the quest log | Bastian's Quests |
| `QuestLog()` | `{ count, ready }`: the quests in the log and how many can be turned in; or `nil` | Bastian's Quests |
| `Route()` | `{ goal, continent, wx, wy, seconds, step, steps }` of the active route: the goal's name and world position, the time left, the current step and the number of steps; or `nil` without a route | Bastian's Route |
| `TravelTime(uiMapID, x, y)` | `seconds, approx` from the character to that point (`approx` is `true` where part of the way is estimated), or `nil` when not known yet. It reads a cache and never starts a search: listen to `BASTIANS_GRAPH_TIMES` and ask again | Bastian's Data |
| `RouteTo(uiMapID, x, y, name)` | `true` when Bastian's Route started planning a route to that point, the same as the player choosing "Route to"; `nil` without Route or for a point it cannot place. `name` is optional | Bastian's Route |
| `Known(spellID)` | `{ me, others, names }`: whether this character knows the spell or recipe (`true`, `false`, or `nil` when the client does not say), how many other characters of the account know it, and their names (`"Marla, Tobb"`); or `nil` | Bastian's Alts |
| `Speak(text)` | `true` when the Orbiter spoke the text in the player's chosen voice; `false` when it did not (another line plays, the voice is off); `nil` without the Orbiter | Bastian's Orbiter |
| `Camp()` | `{ nearby, state, warmIn, left, buffs, readyIn, fires }`: whether a campfire is near the character, the state (`"away"`, `"near"`, `"warming"`, `"warm"`, `"fading"`), the seconds until warm and left of the camp's buffs (`nil` when unknown), how many camp buffs are on the character, the seconds until the character's camp features can be placed again (`nil` when unknown), how many fires shared by the group or guild (and the public channel when switched on) are on the map; or `nil` | Bastian's Campfire (Forever) |
| `Entity(ref)` | `{ ref, type, id, name, summary }` for any thing of the suite by its ref: `"npc:299"`, `"quest:7"`, `"item:2589"`, `"zone:1429"`, `"node:herb:2"`. The name is in the client's language where the data has it; `nil` for a ref nothing knows | Core (names from Bastian's Data) |
| `Where(ref, max)` | `{ { uiMapID, x, y } }` (`x`, `y` in 0..1): the places of the thing that matter now (an NPC's spawns, a quest's giver, a node's spots), at most `max` (10 by default); `nil` without a place | Core (places from Bastian's Data) |
| `NotesNear(uiMapID, x, y, yards)` | `{ { title, text, yards } }`, nearest first: the player's notes on a spot within `yards` (40 by default, at most 500) of that point; an empty table when there are none; `nil` without Notes | Bastian's Notes |
| `Income(days)` | `{ ah, loot, spent }` in copper over the last `days` days, today included (1 by default, at most 30): gold from the auction house, gold from everything else (loot, quests, vendor sales), and what was spent, for the whole account | Bastian's Gold |
| `Waypoint()` | `{ uiMapID, x, y, label }` (`x`, `y` in 0..1): the player's own waypoint on Bastian's Map; `nil` when there is none | Bastian's Map |
| `SetWaypoint(uiMapID, x, y, label)` | `true` when the Map set the waypoint there (it shows on the map and the minimap; it replaces the one before); `nil` without the Map or for a point on no known map | Bastian's Map |
| `ClearWaypoint()` | `true` when the waypoint is gone; `nil` without the Map | Bastian's Map |
| `AccountGold()` | `{ copper, characters }`: the money of the account's characters as last seen, and how many characters that covers; `nil` before any is known | Bastian's Alts |
| `ItemSets()` | `{ { id, label, kind } }` by `id`: the item sets the suite gives bag addons (`kind` `"category"`, `"junk"` or `"mark"`); an empty table when none is registered | Core (sets from the apps) |
| `ItemSet(id)` | `{ itemID, ... }` sorted: the items of that set now; `nil` for an unknown `id` | Core |
| `Play()` | the play preset: `"wanderer"`, `"scholar"`, `"everything"` or `"custom"`; what the player chose at the first start or on the Suite page, so your addon can follow the Wanderer (nearly no UI) or the Scholar | Core |
| `Open(name)` | `true` when the app `name` (as `Apps()` names it) opened its window, or its settings page when it has no window; `false` in combat; `nil` for an unknown or switched-off app | Core |
| `RegisterCallback(target, event, fn)` | calls `fn(event, ...)` on each `event` of `EVENTS`. With a method name instead of `fn`, it calls `target[method](target, event, ...)`. One registration per `target` and `event` (CallbackHandler-1.0) | Core |
| `UnregisterCallback(target, event)` | ends that registration | Core |
| `UnregisterAllCallbacks(target)` | ends every registration of `target` | Core |

## Events

`Bastians.API.EVENTS` lists them. Arguments are strings, numbers and booleans only.

| Event | Arguments | Means |
|---|---|---|
| `BASTIANS_QUESTS_CHANGED` | none | the quest log changed: read `Quest` and `QuestLog` again |
| `BASTIANS_TRACKED_CHANGED` | `ref` (`"quest:123"`), `tracked` | a quest was tracked or untracked |
| `BASTIANS_ROUTE_CHANGED` | none | a route started, moved on a step, was planned again or ended: read `Route` again |
| `BASTIANS_PRICES_UPDATED` | `source` (`"scan"`, `"market"`, `"merchant"`) | prices changed: read `Price` again |
| `BASTIANS_NOTES_CHANGED` | none | a note or a list in Bastian's Notes changed |
| `BASTIANS_ALTS_CHANGED` | none | a character's record in Bastian's Alts changed |
| `BASTIANS_PLAYER_MOVED_ZONE` | `uiMapID`, `continent` | the character entered another map |
| `BASTIANS_MODULE_STATE` | `name`, `enabled` | an app (or a part of one, such as `"Quests.Spoken"`) was switched on or off |
| `BASTIANS_GRAPH_TIMES` | `generation` | travel times were worked out again: read `TravelTime` again |
| `BASTIANS_PLAY_CHANGED` | `id` | the player chose a play preset: read `Play` again |
| `BASTIANS_CHAT_UNREAD` | `count` | the number of whisper conversations with unread lines in Bastian's Chat changed |
| `BASTIANS_VOICE_CHANGED` | none | what the Orbiter plays, or its heard list, changed |
| `BASTIANS_CAMP_SHARED` | `uiMapID`, `x`, `y` | a player of the group or guild, or of the public channel when switched on, shared a campfire (Bastian's Campfire) |
| `BASTIANS_CAMP_WARMED` | `host` or `nil` | the camp's buffs landed on the character; `host` is the name of the one whose camp it is when the game says |
| `BASTIANS_CAMP_FADING` | `seconds` | the camp's buffs end in `seconds` (said ten minutes before) |
| `BASTIANS_WAYPOINT_CHANGED` | `uiMapID`, `x`, `y`, or nothing | the player's waypoint was set there, or cleared (no arguments) |

## Examples

A price line in your own tooltip:

```lua
local function addPrice(tooltip, itemID)
  local api = Bastians and Bastians.API
  local p = api and api.Price and api.Price(itemID)
  if p and p.median then
    tooltip:AddDoubleLine("Auction house", GetCoinTextureString(p.median))
  end
end
```

A guide addon hands its next stop to Bastian's Route:

```lua
local api = Bastians and Bastians.API
if api and api.RouteTo then
  api.RouteTo(1429, 0.42, 0.65, "Goldshire") -- Elwynn Forest
end
```

Following the quest log:

```lua
local api = Bastians and Bastians.API
if api and api.RegisterCallback then
  local listener = {}
  api.RegisterCallback(listener, "BASTIANS_QUESTS_CHANGED", function()
    local log = api.QuestLog()
    if log then
      print(log.count .. " quests, " .. log.ready .. " ready to turn in")
    end
  end)
end
```

## What each app offers

Every app of the suite has the same four doors: a LibDataBroker-1.1 data source (named
`Bastian's <App>`), a slash command, a page in the settings hub (`/bastians`) and `Open(name)`.
A test in the suite's repository fails when a new app forgets one.

| App (`name`) | Data source | Slash | Calls and events |
|---|---|---|---|
| Quests | Bastian's Quests | `/bq` | `Quest`, `QuestLog`; `BASTIANS_QUESTS_CHANGED`, `BASTIANS_TRACKED_CHANGED` |
| Map | Bastian's Map | `/bmap` | `Waypoint`, `SetWaypoint`, `ClearWaypoint`; `BASTIANS_WAYPOINT_CHANGED`, `BASTIANS_PLAYER_MOVED_ZONE` (Core) |
| Browser | Bastian's Browser | `/bb` | `Open("Browser")` |
| Gold | Bastian's Gold | `/bgold` | `Price`, `Income`; `BASTIANS_PRICES_UPDATED` |
| Route | Bastian's Route | `/broute` | `Route`, `RouteTo`; `BASTIANS_ROUTE_CHANGED` |
| Strategies | Bastian's Strategies | `/bbook` | `Open("Strategies")` |
| Notes | Bastian's Notes | `/bnotes` | `NotesNear`; `BASTIANS_NOTES_CHANGED` |
| Alts | Bastian's Alts | `/balts` | `Known`, `AccountGold`; `BASTIANS_ALTS_CHANGED` |
| Helpers | Bastian's Helpers | `/bhelp` | `Open("Helpers")` |
| Voice (the Orbiter) | Bastian's Orbiter | `/bv` | `Speak`; `BASTIANS_VOICE_CHANGED` |
| Chat | Bastian's Chat | `/bchat` | `BASTIANS_CHAT_UNREAD` |
| Gestures | Bastian's Gestures | `/bgest` | `Open("Gestures")` |
| Campfire (Forever) | Bastian's Campfire | `/bcamp` | `Camp`; `BASTIANS_CAMP_SHARED`, `BASTIANS_CAMP_WARMED`, `BASTIANS_CAMP_FADING`; the `camp` message |
| Data | none (no window) | none | `TravelTime`; `BASTIANS_GRAPH_TIMES` |

## Messages

The suite's addons talk to each other's players through addon messages with the prefix
`Bastians`: `<version>|<id>|<part>/<parts>|<kind>|<chunk>`, version `1`, at most 200 characters of
payload per message, one message per 0.25 s, to `PARTY`, `RAID`, `GUILD` or a whispered player,
~~never to a public channel~~ and, for `camp` only, the custom channel `BastiansCamp` when the player switched Campfire's public beacon on (04.11.2026). The payload is a plain value (strings, numbers, booleans, tables of
them) in a serialization without code: `s<len>:<text>`, `n<number>;`, `T`, `F`, `t <key> <value>
... e`, keys sorted. Your addon can read a kind the suite put together, already deserialized:

```lua
Bastians.Comm.Register(yourTable, "notes.pin", function(value, sender, channel)
  -- value = { name, continent, wx, wy, ref }: a place a player shared
end)
```

| Kind | Value | Sent when |
|---|---|---|
| `notes.list` | a shared list of Bastian's Notes: `{ v, id, name, notes = { ... }, bookmarks = { ... } }` | a player shares a list |
| `notes.pin` | one place: `{ name, continent, wx, wy, ref }` (world yards on that continent; `ref` the entity when there is one) | "Send my spot" |
| `route.ferry` | a measured ferry loop: `{ v, id, cycle0, at }` | a ferry's time was measured |
| `camp` | a campfire's place: `{ v = 1, map, x, y, size, features, age }`: `map` the uiMapID, `x` and `y` in 0..1, `size` 3, 5 or 10 features or `nil`, `features` the camp's buffs by name (`"stamina"`, `"fish"`, `"mana"`, `"strength"`, `"lute"`, `"intellect"`, `"attack"`, `"chair"`, `"spirit"`, `"tent"`), `age` the seconds since the sender first saw the fire (players' clocks differ); no names | "Share the fire" in Bastian's Campfire, to the group and the guild, and to the channel `BastiansCamp` when the player switched the public beacon on (join it with `JoinTemporaryChannel("BastiansCamp")` to read it; one fire per player in five minutes) |

A kind's value may gain fields (ignore what you do not know); a field that changes meaning bumps
the value's `v`. New kinds are listed here before they are sent.

## Other ways in

- **Data broker displays.** Each app has a LibDataBroker-1.1 data source named `Bastian's <App>`
  (`Bastian's Quests`, `Bastian's Gold`, ...), so Titan Panel, Bazooka, ElvUI, EllesmereUI's data
  bars and other displays show it. The suite's launcher is the data source `Bastians`.
- **WeakAuras and ForeverAuras.** The events above also reach custom triggers through
  `WeakAuras.ScanEvents`: use the event name in a trigger of type "Custom - Event".
- **Bag addons.** BetterBags gets the categories "Bastian's: sell on AH", "Bastian's: vendor" and
  "Bastian's: quest items"; Baganator a junk plugin and corner marks; AdiBags filters.

## Questions and requests

Open an [issue](https://github.com/drstreit/Bastians-WoW-Forever-Addons/issues/new/choose).
Requests for new calls are welcome: the API grows with what other addons need.
