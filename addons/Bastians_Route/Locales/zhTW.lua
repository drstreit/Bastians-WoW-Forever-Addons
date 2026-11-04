-- Traditional Chinese strings of Bastians_Route (zhTW). Keys are the English texts (Locale.lua); loaded after the German file.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
ns.L:Register("zhTW", {
  -- plan-second-wave.md S6 (01.11.2026)
  ["Route home"] = "回家的路線",
  -- Arrow.lua
  ["Next step"] = "下一步",
  ["position unknown"] = "位置未知",
  ["another continent"] = "另一塊大陸",

  -- Route.lua, Window.lua: home and the teleports (R26.7)
  ["Home"] = "回家",
  ["The way to your inn, with the hearthstone and every teleport you have ready."] = "前往你旅店的路線，使用爐石與你已備妥的每一種傳送。",
  ["No teleport table in the data."] = "資料中沒有傳送表。",
  ["unknown"] = "未知",
  ["not yours"] = "不屬於你",
  ["not castable now"] = "現在無法施放",
  ["cooldown unknown"] = "冷卻時間未知",
  ["landing learned"] = "已得知降落點",
  ["Teleport"] = "傳送",

  -- Explore (R26.11)
  ["Explore"] = "探索",
  ["what is worth doing nearby"] = "附近值得做的事",
  ["quest"] = "任務",
  ["farm spot"] = "打怪點",
  ["sale at the auction house"] = "在拍賣場出售",
  ["craft"] = "製作",
  ["%s away"] = "距離 %s",
  ["XP/h"] = "經驗值/小時",
  ["%d without price"] = "%d 項沒有價格",
  ["Explore needs Bastian's Data."] = "探索需要 Bastian's Data。",
  ["Timing the ways from here..."] = "正在計算從這裡出發的各條路線所需時間...",
  ["%d things to do within %d min"] = "%d 件事可在 %d 分鐘內完成",
  ["%d ways still being timed"] = "仍有 %d 條路線在計算時間",
  ["%d min"] = "%d 分鐘",
  ["XP per hour"] = "每小時經驗值",
  ["Gold per hour"] = "每小時金幣",
  ["Way"] = "路線",

  -- departures (R26.6)
  ["Learned when %s leaves; shared with your group and guild."] = "%s 離開時得知；與你的隊伍和公會共享。",
  ["No boat or zeppelin with departures in the data."] = "資料中沒有有出發時間的船或飛艇。",
  ["leaves in %s"] = "%s 後出發",

  -- a member of the group (R26.9)
  ["No member of your group called %s."] = "你的隊伍中沒有名為 %s 的成員。",
  ["%s has no map position for you (another zone or an instance)."] = "%s 對你沒有地圖位置（在另一個區域或副本中）。",

  -- Several stops (R26.4)
  ["Several stops need the route network of this continent."] = "有數個停靠點需要此大陸的路線網路。",
  ["Tour"] = "行程",
  ["No route through the stops (%s)."] = "通過這些停靠點沒有路線（%s）。",
  ["no way"] = "無路可走",
  ["%d stops left out: another continent, or no way there."] = "有 %d 個停靠點被排除：位於另一塊大陸，或無路可達。",
  ["%s: %d stops, %s"] = "%s：%d 個停靠點，%s",

  -- Route options (R26.5)
  ["Fastest"] = "最快",
  ["Safest"] = "最安全",
  ["No flights"] = "不搭飛行",
  ["Route by default"] = "預設路線",
  ["Switch to this kind of route; it stays the default."] = "切換到此種路線；並保持為預設。",
  ["Careful: level %d creatures"] = "小心：%d 級的生物",
  ["elite"] = "精英",

  -- Death.lua (R26.8)
  ["No corpse to go back to."] = "沒有可返回的屍體。",
  ["your corpse"] = "你的屍體",
  ["Your corpse"] = "你的屍體",
  ["Died here"] = "在此死亡",
  ["Died %s"] = "死於 %s",
  ["%d min ago"] = "%d 分鐘前",
  ["%d h ago"] = "%d 小時前",
  ["%d days ago"] = "%d 天前",
  ["Click for the way back"] = "點擊以取得返回的路線",
  ["Click for a route there"] = "點擊以取得前往該處的路線",
  ["the place of death"] = "死亡地點",
  ["Deaths"] = "死亡記錄",
  ["Where you died: your corpse, and the earlier deaths of this character."] = "你死亡的地點：你的屍體，以及此角色先前的死亡記錄。",
  ["Route back to the corpse after releasing"] = "釋放靈魂後規劃返回屍體的路線",

  -- Route.lua: messages
  ["Hearth: inn unknown. Type /broute hearth while standing at your inn."] = "爐石：旅店未知。站在你的旅店時輸入 /broute hearth。",
  ["Hearth: you are bound to %s now; type /broute hearth there."] = "爐石：你目前綁定在 %s；請在那裡輸入 /broute hearth。",
  ["Hearth: no Hearthstone in your bags."] = "爐石：背包中沒有爐石。",
  ["Hearth: ready in %s."] = "爐石：%s 後可用。",
  ["your inn"] = "你的旅店",
  ["No map position here (instance?)"] = "此處沒有地圖位置（副本？）",
  ["No route to %s"] = "沒有前往 %s 的路線",
  ["You are already there: %s"] = "你已經在那裡了：%s",
  ["Route to %s: %s, %d steps"] = "前往 %s 的路線：%s，%d 個步驟",
  ["the marked spot"] = "標記的地點",
  ["Could not re-route to %s from here; keeping the route."] = "無法從這裡重新規劃前往 %s 的路線；保留原路線。",
  ["You have arrived: %s"] = "你已抵達：%s",
  ["Hearth set: %s"] = "已設定爐石：%s",
  ["here"] = "此處",
  ["Hearth: %s, %s"] = "爐石：%s，%s",
  ["set"] = "已設定",
  ["ready"] = "就緒",
  ["ready in %s"] = "%s 後就緒",
  ["Hearth: inn unknown (/broute hearth at your inn)"] = "爐石：旅店未知（在你的旅店輸入 /broute hearth）",
  ["%d flight masters learned, %d flight times measured"] = "已得知 %d 位飛行管理員，已測量 %d 段飛行時間",

  -- Route.lua: settings and actions
  ["Route"] = "路線",
  ["Flight paths to use"] = "要使用的飛行路線",
  ["Known to this character"] = "此角色已知",
  ["Known to any of my characters"] = "我的任何角色已知",
  ["All flight masters"] = "所有飛行管理員",
  ["Open the step list when a route starts"] = "路線開始時開啟步驟清單",
  ["Show an arrow to the next step while a route is active"] = "路線進行中時，顯示指向下一步的箭頭",
  ["Route here"] = "在此規劃路線",
  ["Route to"] = "規劃路線前往",
  ["Open Bastian's Route"] = "開啟 Bastian's Route",

  -- Window.lua
  ["wait up to %s"] = "最多等待 %s",
  ["Time"] = "時間",
  ["Distance"] = "距離",
  ["yd"] = "碼",
  ["Estimate: a straight line or an unmeasured ride."] = "估計：直線或未經測量的行程。",
  ["Legs marked approx are straight lines or unmeasured rides; the time is an estimate."] = "標示為「約」的路段是直線或未經測量的行程；時間為估計值。",
  ["The map draws them dashed: they may cross water until the route graph knows the terrain."] = "地圖上以虛線繪製：在路線圖得知地形之前，它們可能會穿過水面。",
  ["No route. Right click anything with a place and choose Route to."] = "沒有路線。對任何有地點的東西按右鍵並選擇「規劃路線前往」。",
  ["the target"] = "目標",
  ["To %s: %s, %d steps"] = "前往 %s：%s，%d 個步驟",
  ["Clear"] = "清除",
  ["Clear the route."] = "清除路線。",
  ["Replan"] = "重新規劃",
  ["Plan the route again from where you stand."] = "從你所在的位置重新規劃路線。",
  ["Click a step to see its end on the map."] = "點擊步驟以在地圖上查看其終點。",

  -- Graph.lua: the words of a step ("Fly to X", "Go 380 yd SE to X (approx)")
  ["Go"] = "前往",
  ["Fly"] = "飛行",
  ["Take the boat"] = "搭船",
  ["Take the zeppelin"] = "搭飛艇",
  ["Take the tram"] = "搭地鐵",
  ["Take the portal"] = "使用傳送門",
  ["Hearth"] = "爐石",
  ["to"] = "至",
  ["approx"] = "約",
  -- the broker displays' feed (ADR 0043, 31.10.2026)
  ["%s, %s"] = "%s，%s",
  ["Click: the steps. Right click: clear the route."] = "點擊：步驟。右鍵點擊：清除路線。",
  ["and %d more"] = "還有 %d 個",

  -- Welcome, Suite page, Help page, app pages, Words (01.11.2026)
  ["Next: %s"] = "下一步：%s",
})
