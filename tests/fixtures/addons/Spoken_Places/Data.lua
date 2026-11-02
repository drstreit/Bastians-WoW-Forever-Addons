-- Test double of a Spoken Places voice pack (the registry `SpokenPlacesAudioPacks[folder]`, format 1,
-- read 01.11.2026) and of Spoken's Data/Dungeons.lua: Elwynn Forest (1429) and Goldshire have a line,
-- the Deadmines' story is the area "deadmines" under Westfall (1436); Stormwind (1453) has none.
SpokenPlacesAudioPacks = SpokenPlacesAudioPacks or {}
SpokenPlacesAudioPacks.SpokenPlacesAudio = {
  version = 1,
  addon = "SpokenPlacesAudio",
  language = "enUS",
  quality = "standard",
  bitrate = 64,
  zones = {
    [1429] = { file = "1429/zone", len = 161, times = { 0, 0.4, 0.9 } },
    [1436] = { file = "1436/zone", len = 138 },
  },
  subzones = {
    [1429] = {
      goldshire = { file = "1429/goldshire", len = 72 },
      ["fargodeep mine"] = { file = "1429/fargodeep-mine", len = 58 },
    },
    [1436] = {
      deadmines = { file = "1436/deadmines", len = 185 },
    },
  },
}
SpokenDungeons = {
  dungeons = {
    [36] = { zone = 1436, story = { 1436, "deadmines" }, name = { enUS = "The Deadmines" } },
  },
  worldBosses = {},
}
