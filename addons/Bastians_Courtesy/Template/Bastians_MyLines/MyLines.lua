-- Your own lines for Bastian's Courtesy. Updates of the suite never touch this folder.
--
-- INSTALL  Copy this whole folder (Bastians_MyLines) to Interface/AddOns and restart the game once.
--          After that a /reload is enough when you change this file.
-- CHECK    /bcourtesy mine  says how many of your lines work, and what is wrong with the others.
-- TRY      /bcourtesy try   prints invented moments to your own chat; nothing is sent.
--          /bcourtesy try 20 rez snarky rain night dwarf f   asks for one exact moment.
-- SWITCH   The suite's settings, page Courtesy: "Use my own lines". Off: the lines of the suite.
--
-- You can start small: where none of your lines fits a moment, one of the suite's is used.
--
-- A LINE    { situation, mood, text, act = "...", when = { ... }, emote = "..." }
--
--   situation  buff, buff.mind, buff.stamina, buff.nature, buff.blessing, rez, emote.friendly,
--              emote.rude, invite.accepted, invite.declined, duel.declined, trade.gift, camp
--              (a line for "buff" also serves buff.mind and the other kinds of buff)
--   mood       polite, roleplay, snarky, philosophic, cheerful, weary
--   text       What your character says. false for a line without words; then it needs an act.
--   act        Optional. What your character does, without the name: "bows to %t."
--   when       Optional. The line is used only then: race, class (in capitals: "MAGE"), sex ("m", "f"),
--              mine (your race), mysex, time (morning, afternoon, evening, night),
--              weather (clear, rain, snow, sandstorm), kin (true: same race as you).
--              A list works too: when = { time = { "evening", "night" } }.
--              Races: Human, Dwarf, NightElf, Gnome, Orc, Troll, Scourge, Tauren.
--   emote      Optional. A game emote played with the line: "BOW", "WAVE", "SALUTE", ...
--
-- IN A TEXT  %t name   %r race   %c class   %h time of day   %w the weather   %z zone   %n my name
--            %m my race   %p my his/her   %o sir or my lady   %y lad or lass
--
-- Every line ends with a comma. A missing comma or quote stops the whole file: /bcourtesy mine then
-- finds no lines at all. Keep a line under about 200 characters.

Bastians:AddCourtesyLines({
  { "buff", "polite", "Thank you, %t. I will not forget it." },
  { "buff", "roleplay", "May your road stay dry, %t.", act = "tips %p hat." },
  { "buff.mind", "snarky", "Finally, someone thinks I need to think. Thanks, %t." },
  { "buff", "cheerful", "Oh, lovely! Good %h to you, %t!", emote = "WAVE" },
  { "buff", "weary", "One more step, then. Thank you, %t.", when = { time = "night" } },
  { "rez", "philosophic", "So the road goes on after all. My thanks, %t." },
  { "emote.friendly", "polite", false, act = "smiles back at %t." },
  { "invite.declined", "polite", "Another time, %t. Good %h to you." },
})
