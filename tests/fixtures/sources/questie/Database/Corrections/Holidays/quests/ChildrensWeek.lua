-- Trimmed from Questie 12.6.0.
local QuestieEvent = QuestieLoader:ImportModule("QuestieEvent")
local tinsert = table.insert
local eventQuests = QuestieEvent.eventQuests

tinsert(eventQuests, {"Children's Week", 172}) -- Children's Week
tinsert(eventQuests, {"Children's Week", 10960, nil, nil, nil, nil, Expansions.Current >= Expansions.Wotlk})
