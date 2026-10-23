---@diagnostic disable: deprecated
local appName, _ = ...
local L = _.L;
_.AddEventHandler("OnBuildDataCache", function(categories)
local h,i,n,q=_.CreateCustomHeader,_.CreateItem,_.CreateNPC,_.CreateQuest;
local a={{"NYI"}}
categories.NeverImplemented=h(-1,{u=1,g={q(999999,{coords={[37]={{10,10}}}}),q(4641,{coords={[1]={{44.3,69.1}}},u=1}),n(999998,{coords={[37]={{11,11}}}}),n(-7,{coords={[37]={{12,12}}}})}})
end)
