-- What's new of Bastian's Chat (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.5.0:1",
    date = "2026-11-15",
    version = "2.5.0",
    text = "Bastian's Chat has a new window with two decks: what you want to know above (loot, fights, Trade, groups, the world), your people, your group and your guild below, with a people list you can search, a level per place (everything, your name and watches, or nothing), the game's chat settings, emotes and channels one click away, and a one-line summary after each fight. /bchat tabs brings the tabs back with nothing lost.",
  },
  {
    id = "2.5.0:2",
    date = "2026-11-15",
    version = "2.5.0",
    text = "Whispers live in the chat window: each person has a chip with an unread count and a conversation that marks what is new, the people list shows their face or their class's symbol, and what you half typed waits for them. Hover a name to see what that person said this session. Drag a chip or a whole deck out into a window of its own and back; a person's window has its own input line.",
  },
  {
    id = "2.5.0:3",
    date = "2026-11-15",
    version = "2.5.0",
    text = "Invites, duels, trades, ready checks, summons, resurrections, raid warnings and mentions of your name wait in a bar over the chat's input line, where you can answer them.",
  },
  {
    id = "2.5.0:4",
    date = "2026-11-15",
    version = "2.5.0",
    text = "The chat's Trade shows offers as cards with the price for one against the market price and how many of the item you have, and also catches crafting and service offers (enchants, lockboxes, portals) that are said, yelled or written in General. Group searches show as a card per dungeon with its levels and the roles wanted, the dungeons for your level first, each with a button to whisper the poster. Offers, group searches and questions are read in every client language.",
  },
  {
    id = "2.5.0:5",
    date = "2026-11-15",
    version = "2.5.0",
    text = 'Whispers come with answers to click: where you are, your item level, whether you can craft something, "On a flight to Ironforge, there in 2 min." on a flight, and replies to thanks, congratulations and greetings, one of them a line from Bastian\'s Courtesy. Reword them on the settings page and keep your own lines as answers; the ones you use most come first.',
  },
  {
    id = "2.5.0:6",
    date = "2026-11-15",
    version = "2.5.0",
    text = "/bchat away answers whispers with your own text while you are away and ends when you move; when you are back, and after a cutscene or a long loading screen, the chat shows what came meanwhile.",
  },
  {
    id = "2.5.0:7",
    date = "2026-11-15",
    version = "2.5.0",
    text = "A watch list: items your quests still need, and items or dungeons you add with /bchat watch or a right click, ping when someone sells them or forms a group. The chat's find line searches in plain words (names, items, dungeons; wts also finds the other languages' offers) with suggestions, and its star keeps a search as a watch.",
  },
  {
    id = "2.5.0:8",
    date = "2026-11-15",
    version = "2.5.0",
    text = "Right click works everywhere in the chat window: copy a line or every line, select text with the mouse, mute a sender in a channel, and Shift+click a line's time to quote it.",
  },
  {
    id = "2.5.0:9",
    date = "2026-11-15",
    version = "2.5.0",
    text = "The chat's Combat log button opens the game's combat log in a window of its own that you can move, size and close.",
  },
  {
    id = "2.5.0:10",
    date = "2026-11-15",
    version = "2.5.0",
    text = "Chat: the Up and Down keys walk your sent lines again instead of moving your character, and a line comes back with the channel it was sent to.",
  },
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The chat's copy window has a scroll bar.",
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The chat input bar no longer disappears behind the window, and a reload no longer takes the keyboard.",
  },
  {
    id = "1.6.0:1",
    date = "2026-11-05",
    version = "1.6.0",
    text = "Chat: the Up and Down keys recall your sent lines on Forever too (Alt+Up stays the game's).",
  },
  {
    id = "1.3.0:1",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Bastian's Chat gets a live tab filter, tab windows that dock back, a Messenger of the WhatsApp kind with class icons and a search, and a lock on every chat window.",
  },
}
