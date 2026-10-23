local _, ns = ...

-- Names for the creatures and objects that START or FINISH a quest, so a start or
-- turn-in pin can say WHO is standing there and not only where.
--
-- npc  [creatureID] = name
-- obj  [objectID]   = name
--
-- TWO sub-tables under one global, because creature and object ids OVERLAP. 261 is both
-- Guard Thomas and Damaged Crate, so no test on the id itself can tell them apart.
-- The point's KIND is what says which of the two to read, and reading the wrong one
-- returns a real name for the wrong thing rather than nil.
--
-- Holds exactly the ids the srcID slot of Data/QuestAvailable_*.lua's start table and
-- Data/QuestTurnIn_*.lua actually reference, so nothing is orphaned and nothing is
-- missing. A quest started by an ITEM stores no source and needs no name here.
--
-- English. The client cannot name a creature it has never seen and offers no way to
-- ask by id on this flavor, so unlike a quest title there is nothing to prefer over it.
-- 112 creature(s) and 9 object(s) used only by Forever supplement quests have no name yet, so their pins and Quest Browser lines show none.
ns.CLASSIC_QUEST_SOURCES = {
  npc = {
    [197] = "Marshal McBride",
    [240] = "Marshal Dughan",
    [823] = "Deputy Willem",
  },
  obj = {
    [68] = "Wanted Poster",
    [156561] = "Wanted Poster",
  },
}
