-- Test double of Spoken Readables' globals (read 01.11.2026): SpokenReadablesData (the corpus: an
-- index by title, page number and checksum to the page id; the books; the pages), SpokenReadablesPlaces
-- (where each readable is) and a voice pack in SpokenReadablesAudioPacks. The Wanted Poster of Elwynn
-- (our object 1734) has two pages, both recorded; "A Careworn Note" has no recording.
SpokenReadablesData = {
  version = 1,
  index = {
    ["Wanted Poster"] = {
      [1] = { [1881155820] = 501 },
      [2] = { [1643615386] = 502, [1643615387] = 503 },
    },
    ["A Careworn Note"] = {
      [1] = { [883437829] = 601 },
    },
  },
  books = {
    [41] = { title = "Wanted Poster", pages = { 501, 502 } },
    [42] = { title = "A Careworn Note", pages = { 601 } },
  },
  pages = {
    [501] = { book = 41, number = 1 },
    [502] = { book = 41, number = 2 },
    [503] = { book = 41, number = 2 },
    [601] = { book = 42, number = 1 },
  },
}
SpokenReadablesPlaces = {
  version = 1,
  books = {
    [41] = { kind = "world", type = "plaque", zones = { 1429 } },
    [42] = { kind = "carried", type = "note", zones = { 1429, 1436 } },
  },
}
SpokenReadablesAudioPacks = SpokenReadablesAudioPacks or {}
SpokenReadablesAudioPacks.SpokenReadablesAudio = {
  version = 1,
  addon = "SpokenReadablesAudio",
  language = "enUS",
  pages = {
    [501] = { file = "41/1", len = 12, text = "WANTED: Hogger. The gnoll known as Hogger terrorises Elwynn." },
    [502] = { file = "41/2", len = 0, text = "A reward is offered by Marshal Dughan of Goldshire." },
  },
}
