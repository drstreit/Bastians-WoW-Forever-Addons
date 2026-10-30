-- Data: ForeverDB.net (https://foreverdb.net), build fixture. Reuse requires this credit: see NOTICE.txt (GPL-3.0 section 7(b)).
-- Test fixture in the shape of ForeverDB 0.44.0's Dungeons.lua: two dungeons and a raid.
local _, ns = ...
ns.dungeons = {
[36]={n="The Deadmines",kind="dungeon",size=5,lv="15:25:10",ent="nabc12",zone="Elwynn Forest",boss="1:644:Rhahk'Zor|2:646:Mr. Smite|3:639:Edwin VanCleef",npc="",loot="872:1:s 1185:1:s 5443:2:s 2169:3:c 5187:0:c",q="6 166",guide=""},
[34]={n="Stormwind Stockade",kind="dungeon",size=5,lv="24:32:23",ent="nmwoic o1dndi",zone="Nowhere Known",boss="1:2756:Targorr the Dread",npc="",loot="",q="",guide=""},
[249]={n="Onyxia's Lair",kind="raid",size=40,lv="60:60:60",ent="nwmpwx",zone="Dustwallow Marsh",boss="1:1084:Onyxia",npc="",loot="16914:1:c",q="",guide=""},
}
