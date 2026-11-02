-- Test double of Spoken NPCs' globals (read 01.11.2026): SpokenBossCreatures[map][key] = { creature,
-- display } and SpokenBossStories[map][key] = the words. The Deadmines (36): Edwin VanCleef has a
-- story, Sneed none; Hogger (448, Elwynn) is a world boss with a story.
SpokenBossCreatures = {
  [36] = {
    ["edwin vancleef"] = { creature = 639, display = 2140 },
    ["sneed"] = { creature = 643, display = 2103 },
  },
  [1429] = {
    ["hogger"] = { creature = 448, display = 383 },
  },
}
SpokenBossStories = {
  [36] = {
    ["edwin vancleef"] = "Edwin VanCleef was the guildmaster of the Stonemasons who rebuilt Stormwind. "
      .. "Unpaid by the House of Nobles, he led his followers out of the city and made them the Defias Brotherhood.",
  },
  [1429] = {
    ["hogger"] = "Hogger leads the Riverpaw gnolls at the edge of Elwynn Forest.",
  },
}
