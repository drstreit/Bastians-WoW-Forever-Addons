local _, ns = ...

-- [questID] = { [uiMapID] = { packed, ... } }
-- packed = objMask*1e9 + kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)
-- kind 1=slay 2=object 3=loot, and the same +4 (5,6,7) for a DUNGEON ENTRANCE - the
-- objective is inside an instance whose interior coordinates nobody records, so the
-- pin marks the way in. Recover the real kind by subtracting 4.
-- objMask is a BITMASK of the objectives this location serves - bit i means the ith
-- objective OF THIS KIND'S TYPE, 0 based, the same numbering Data/QuestNPCs_Classic
-- uses. One location commonly serves several, which is why it is not a single index.
-- decode: objMask = floor(v/1e9), kind = floor(v%1e9/1e8), rest = v%1e8,
--         x = floor(rest/1e4)/1e4, y = (rest%1e4)/1e4
-- Each list is ordered densest first. The reader draws the first N, so the order is
-- what makes a pin limit keep the N best locations instead of N arbitrary ones.
-- Shipped as a long string, not a table. Reach it through Compat.ClassicSpawns(),
-- which builds it on first use. ns.HAS_CLASSIC_SPAWNS answers the flavor question.
ns.HAS_CLASSIC_SPAWNS = true
ns.CLASSIC_QUEST_SPAWNS_SRC = [==[return {
  [6] = {
    [1429] = { 1357524825 },
  },
  [7] = {
    [1429] = {
      1148893644,
      1149323581,
      1147653691,
      1149553606,
      1147583594,
      1150763747,
      1151303650,
      1151293743,
      1149273705,
      1148873514,
      1146933567,
      1147673492,
      1150043546,
      1151613568,
    },
  },
  [176] = {
    [1429] = { 1325029290, 1326838669, 1326439365, 1327369271, 1325788982 },
  },
}]==]
