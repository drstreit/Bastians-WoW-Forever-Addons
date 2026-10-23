local _, ns = ...

-- [questID] = category bitmask
--   1 instance    the quest is sorted into a dungeon or raid area
--   2 repeatable  specialFlags bit 0
--   4 event       specialFlags bit 1, which marks a quest completed by exploring
--                 or by a script. It is NOT a holiday marker.
--   8 class       the quest carries a required class mask
--  16 profession  the quest carries a required skill
-- A quest with no category at all is left out, so absence means ordinary quest.
-- Derived entirely from the dump. The client's own GetQuestTagInfo answers only for
-- quests it already knows, which is why it cannot drive a filter for unaccepted ones.
ns.CLASSIC_QUEST_CATEGORY = {
  [62] = 4,
  [76] = 4,
}
