local _, ns = ...

-- Where every quest can be PICKED UP, and the gates that decide whether it can be.
-- The client answers none of this for a quest that is not in the log, so it ships.
--
-- start  [questID] = { [uiMapID] = { packed, ... } }
--        packed = srcID*1e9 + kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)
--        kind 1=an NPC offers it, 2=an object offers it, 3=an item that starts it
--        drops here. These are SOURCES of the quest, not objective types.
--        srcID is the creature id when kind is 1 and the object id when kind is 2, for
--        the name the tooltip shows. It is 0 when kind is 3, because the dropper of a
--        starting item can be either and kind would not say which id space it is.
--        decode: srcID = floor(v/1e9), kind = floor(v/1e8)%10, rest = v%1e8,
--                x = floor(rest/1e4)/1e4, y = (rest%1e4)/1e4
--        A reader wanting only the coordinate can still take v%1e8 and ignore the rest.
--        Ordered densest first, so a reader's prefix keeps the best locations.
-- gates  [questID] = requiredLevel*1e11 + questLevel*1e9 + specialFlags*1e8
--                    + requiredRaces*1e4 + requiredClasses
--        specialFlags: 1 repeatable, 2 completed by exploring or by a script, 4
--        monthly reset. Bit 2 is NOT a holiday marker and must not be gated on as
--        one. See Modules/MapPOI/Holidays.lua for what actually decides a holiday.
--        A bitmask of 0 means no restriction, not 'no races allowed'.
-- names  [questID] = English title. The client is asked first and this is the fallback,
--        so a non-English client shows English only for quests it does not know.
-- pre    [questID] = { questID, ... }  ANY one completed satisfies it
-- preAll [questID] = { questID, ... }  ALL must be completed
-- excl   [questID] = { questID, ... }  any of these taken or completed rules it out
-- chain  [questID] = questID           that quest active or done rules this one out
-- parent [questID] = questID           must be in the log for this one to be offered
-- skill  [questID] = skillLineID*1e4 + requiredValue
-- minRep [questID] = factionID*1e6 + requiredStanding
-- maxRep [questID] = factionID*1e6 + maximumStanding
ns.CLASSIC_QUEST_AVAILABLE = {
  chain = {
    [62] = 76,
  },
  excl = {},
  gates = {
    [6] = 205000770000,
    [7] = 102000770000,
    [62] = 407200770000,
    [76] = 410200770000,
    [176] = 511000770000,
  },
  maxRep = {},
  minRep = {},
  names = {
    [6] = "Bounty on Garrick Padfoot",
    [7] = "Kobold Camp Cleanup",
    [62] = "The Fargodeep Mine",
    [76] = "The Jasperlode Mine",
    [176] = "Wanted:  \"Hogger\"",
  },
  parent = {},
  pre = {
    [6] = { 18 },
    [7] = { 783 },
    [76] = { 62 },
  },
  preAll = {},
  skill = {},
  start = {
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
      [1429] = { 68224557469, 156561224577823 },
    },
  },
}
