local _, ns = ...

-- Which world event each quest belongs to, for the quests EQ can pin. Generated.
-- Without this the map pins every holiday quest all year: nothing in the base gate data
-- identifies a holiday, and the flag that looked like it did marks exploration quests.
--
-- event  [questID] = event index into ns.EQ_HOLIDAY_NAMES, below.
-- window [questID] = "D/M-D/M", a narrower run INSIDE its event. Winter Veil only, where
--        the gift and Winter's Veil quests open on their own days rather than with the event.
--
-- Dates for the events themselves are NOT here. They live beside the code that reads them,
-- in Modules/MapPOI/Holidays.lua, because the lunar festival moves every year.
ns.EQ_HOLIDAY_NAMES = {
  "Brewfest",
  "Children's Week",
  "Darkmoon Faire",
  "Day of the Dead",
  "Hallow's End",
  "Harvest Festival",
  "Love is in the Air",
  "Lunar Festival",
  "Midsummer",
  "Noblegarden",
  "Pilgrim's Bounty",
  "Winter Veil",
}
ns.CLASSIC_QUEST_HOLIDAY = {
  event = {},
  window = {},
}
