-- What's new of the suite as a whole (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.4.0:1",
    date = "2026-11-04",
    version = "1.4.0",
    text = "The session plan (what fits into the next 30 to 180 minutes) moved from Route's Explore to Bastian's Gold and is off until you switch it on in Gold's settings.",
  },
  {
    id = "1.4.0:2",
    date = "2026-11-04",
    version = "1.4.0",
    text = "Other addons can ask Bastian's for any thing's name and places, your notes near a spot and your gold income through Bastians.API.",
  },
  {
    id = "1.4.0:3",
    date = "2026-11-04",
    version = "1.4.0",
    text = "When Bastian's Helpers restocks an item, it tells you if another vendor sells it cheaper and where.",
  },
  {
    id = "1.4.0:4",
    date = "2026-11-04",
    version = "1.4.0",
    text = "What's new speaks your language: German, French, Spanish, Korean and Chinese.",
  },
  {
    id = "1.4.0:5",
    date = "2026-11-04",
    version = "1.4.0",
    text = "Campfire can share your fire on a public channel and show everyone's fires (off by default, with a block list).",
  },
  {
    id = "1.4.0:6",
    date = "2026-11-04",
    version = "1.4.0",
    text = "Bastian's Suite now speaks Russian and Brazilian Portuguese.",
  },
  {
    id = "1.4.0:7",
    date = "2026-11-04",
    version = "1.4.0",
    text = "Other addons can now read and set Bastian's waypoint, read the account's gold and the suite's item sets through Bastians.API.",
  },
  {
    id = "1.4.0:8",
    date = "2026-11-04",
    version = "1.4.0",
    text = "Spoken 3.8.0, the launch client's copy, is now the version the suite was tested with; the hub no longer flags it as newer.",
  },
  {
    id = "1.3.0:1",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Bastian's apps show in Titan Panel, Bazooka, EllesmereUI's data bars and every other LibDataBroker display, in the addon compartment, and sort your bags in BetterBags, Baganator and AdiBags.",
  },
  {
    id = "1.3.0:2",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Wide buttons in the WoW look keep the game's rounded ends instead of stretching them.",
  },
  {
    id = "1.3.0:3",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Other addons can ask Bastian's for prices, quest state, the active route and travel times, start a route, and listen to its events through Bastians.API.",
  },
  {
    id = "1.3.0:4",
    date = "2026-11-02",
    version = "1.3.0",
    text = "The map's layer bar names each icon the moment you point at it.",
  },
  {
    id = "1.3.0:5",
    date = "2026-11-02",
    version = "1.3.0",
    text = 'The colour picker opens in front of the settings, and no "blocked" message appears in combat.',
  },
  {
    id = "1.3.0:6",
    date = "2026-11-02",
    version = "1.3.0",
    text = 'Bastian\'s Helpers also writes its notices into a chat tab named "Addons" when you have one.',
  },
  {
    id = "1.3.0:7",
    date = "2026-11-02",
    version = "1.3.0",
    text = 'one search syntax in every box (words, "phrases", OR, -not, field:value, level>30), the text keys Ctrl+Backspace/Delete/Left/Right, a key that clears the screen for role play, a lock on every window, and the new look engine behind Modern and WoW.',
  },
  {
    id = "1.3.0:8",
    date = "2026-11-02",
    version = "1.3.0",
    text = "the Browser's filter pills use the pane's width and the first row is never hidden, the Mobs search works again, zones appear once, a preview needs Shift, and a note saved on a page shows at once.",
  },
  {
    id = "1.3.0:9",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Seven looks to pick from, including Night, Glass and Parchment; every button of the suite shows a pictogram; every colour scheme is checked for readable text.",
  },
  {
    id = "1.3.0:10",
    date = "2026-11-02",
    version = "1.3.0",
    text = "The Orbiter's bubbles glide to their places and the one that plays is coloured; Show on map always draws what you chose; the junk filter also cleans the lines already on screen; the game's voice is found once the client lists it.",
  },
  {
    id = "1.3.0:11",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Every app offers a data-broker feed (Titan, Bazooka, ElvUI and the like), the Addon Compartment lists the suite, bag addons get the suite's item sets, and other addons can read the suite through Bastians.API.",
  },
  {
    id = "1.3.0:12",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Trainers say what they train on the map and on their page, and their list of spells shows who of your characters knows each one; item lists filter by who owns an item; the Orbiter hides with the clear-screen key and drags by its hub; the Browser's hover preview is a setting.",
  },
  {
    id = "1.3.0:13",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Every button shows its pictogram again and the words sit where they belong; chat tabs and buttons are easy to tell apart; the Orbiter's controls click with a creature shown, its hub drags it, and its answers are symbols; an item's page says which of your characters has it.",
  },
  {
    id = "1.3.0:14",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Choose how you play at the first start: the Wanderer hears Azeroth with nearly no UI, the Scholar has every quest, creature, item and place one click away; Bastian's Gestures brings emote rings and courtesy; the hub explains every app and key.",
  },
  {
    id = "1.3.0:15",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Every app wears its own mark on the minimap, in the hub, on broker displays and in the AddOns list: a compass star for the suite, a scroll for Quests, a pin for the Map, a lens for the Browser, a balance for Gold, a signpost for Route, a quill for Notes, two characters for Alts, a wrench for Helpers, bubbles for Chat, a hand for Gestures.",
  },
  {
    id = "1.3.0:16",
    date = "2026-11-02",
    version = "1.3.0",
    text = "The Orbiter says when your Spoken is newer or older than the suite was tested with, never talks over Spoken or Spoken Players, and Bastian's Helpers, Chat and the Orbiter show up on broker displays; other addons can ask who knows a recipe, let the Orbiter speak, read your play preset and open any app.",
  },
  {
    id = "1.3.0:17",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Gestures' Route home, Mark heard and Toggle the tracker wedges light up.",
  },
  {
    id = "1.3.0:18",
    date = "2026-11-02",
    version = "1.3.0",
    text = "When someone challenges, trades or invites you, Gestures offers a bow, a wave or a polite decline; Chat's + menu has a Roleplay tab.",
  },
  {
    id = "1.3.0:19",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Build your Gestures rings as you like: name them, pick any emote, your own lines, commands, the suite's and the game's controls through one filter; the wheel turns the right way; a conversation's choices no longer overlap on the Orbiter.",
  },
  {
    id = "1.3.0:20",
    date = "2026-11-02",
    version = "1.3.0",
    text = "The Korean and Chinese texts of the suite read naturally and use the game's own terms.",
  },
  {
    id = "1.3.0:21",
    date = "2026-11-02",
    version = "1.3.0",
    text = "A Gestures wedge can run one of your own macros with a click, and runs the game's own commands such as /reload; Quests' item buttons work with \"cast on key down\".",
  },
  {
    id = "1.3.0:22",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Emotes in Bastian's Chat now show in the colour scheme's own emote colour, for roleplay.",
  },
}
