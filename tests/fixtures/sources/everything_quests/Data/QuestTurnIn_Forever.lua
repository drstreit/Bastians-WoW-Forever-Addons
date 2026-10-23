local _, ns = ...

-- [questID] = { [uiMapID] = { packed, ... } }
-- packed = srcID*1e9 + kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)
-- kind 1=an NPC takes it, 2=an object does, and the same +4 (5,6) for a DUNGEON
-- ENTRANCE - the turn-in is inside an instance whose interior coordinates nobody
-- records, so the pin marks the way in. Recover the real kind by subtracting 4.
-- srcID is the creature id when kind is 1 and the object id when kind is 2, for the
-- name the tooltip shows. It is 0 for an entrance, where nobody is standing.
-- KIND is what says which id space srcID belongs to. The two overlap numerically.
-- decode: srcID = floor(v/1e9), kind = floor(v/1e8)%10, rest = v%1e8,
--         x = floor(rest/1e4)/1e4, y = (rest%1e4)/1e4
-- A reader that wants only the coordinate can still take v%1e8 and ignore the rest.
-- Ordered densest first, so a reader's prefix keeps the best locations.
--
-- Deliberately NOT ns.CLASSIC_QUEST_COORDS. That table answers where a quest is
-- ADVANCED and both would load into one name, silently keeping whichever came second.
ns.CLASSIC_QUEST_TURNIN = {
  [6] = {
    [1429] = { 823148174294 },
  },
  [7] = {
    [1429] = { 197148924161 },
  },
  [62] = {
    [1429] = { 240142116593 },
  },
  [76] = {
    [1429] = { 240142116593 },
  },
  [176] = {
    [1429] = { 240142116593 },
  },
}
