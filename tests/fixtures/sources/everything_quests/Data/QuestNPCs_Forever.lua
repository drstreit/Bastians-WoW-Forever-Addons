local _, ns = ...

-- [questID] = { packed, ... }
-- packed = objIdx*1e8 + kind*1e7 + npcID.  kind 1=slay 2=object 3=loot
-- objIdx is 0 based WITHIN ITS OWN TYPE, matching the client's nth objective of that
-- type - a mob that drops one of four quest items must not claim the other three.
-- decode: objIdx = floor(v/1e8), kind = floor(v%1e8/1e7), npcID = v%1e7
ns.CLASSIC_QUEST_NPCS = {
  [6] = { 30000103 },
  [7] = { 10000006 },
  [176] = { 30000448 },
}
