-- Simplified Chinese strings of Bastians_Route (zhCN). Keys are the English texts (Locale.lua); loaded after the German file.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
ns.L:Register("zhCN", {
  -- plan-second-wave.md S6 (01.11.2026)
  ["Route home"] = "回家的路线",
  -- Arrow.lua
  ["Next step"] = "下一步",
  ["position unknown"] = "位置未知",
  ["another continent"] = "另一块大陆",

  -- Route.lua, Window.lua: home and the teleports (R26.7)
  ["Home"] = "家",
  ["The way to your inn, with the hearthstone and every teleport you have ready."] = "前往你的旅店的路线,使用炉石和你已就绪的所有传送。",
  ["No teleport table in the data."] = "数据中没有传送表。",
  ["unknown"] = "未知",
  ["not yours"] = "不属于你",
  ["not castable now"] = "现在无法施放",
  ["cooldown unknown"] = "冷却时间未知",
  ["landing learned"] = "已记录落点",
  ["Teleport"] = "传送",

  -- Explore (R26.11)
  ["Explore"] = "探索",
  ["what is worth doing nearby"] = "附近值得做的事",
  ["quest"] = "任务",
  ["farm spot"] = "刷怪点",
  ["sale at the auction house"] = "在拍卖行出售",
  ["craft"] = "制造",
  ["%s away"] = "距离%s",
  ["XP/h"] = "经验/小时",
  ["%d without price"] = "%d项无价格",
  ["Explore needs Bastian's Data."] = "探索需要 Bastian's Data。",
  ["Timing the ways from here..."] = "正在计算从这里出发的路线耗时...",
  ["%d things to do within %d min"] = "%d分钟内可做%d件事",
  ["%d ways still being timed"] = "还有%d条路线正在计时",
  ["%d min"] = "%d分钟",
  ["XP per hour"] = "每小时经验",
  ["Gold per hour"] = "每小时金币",
  ["Way"] = "路线",

  -- departures (R26.6)
  ["Learned when %s leaves; shared with your group and guild."] = "%s出发时记录;与你的队伍和公会共享。",
  ["No boat or zeppelin with departures in the data."] = "数据中没有带出发时刻的船或飞艇。",
  ["leaves in %s"] = "%s后出发",

  -- a member of the group (R26.9)
  ["No member of your group called %s."] = "你的队伍中没有名为%s的成员。",
  ["%s has no map position for you (another zone or an instance)."] = "%s对你没有地图位置(在另一区域或副本中)。",

  -- Several stops (R26.4)
  ["Several stops need the route network of this continent."] = "多个站点需要这块大陆的路线网络。",
  ["Tour"] = "巡游",
  ["No route through the stops (%s)."] = "无法经过这些站点(%s)。",
  ["no way"] = "无路",
  ["%d stops left out: another continent, or no way there."] = "有%d个站点被略过: 在另一块大陆,或无路可达。",
  ["%s: %d stops, %s"] = "%s: %d个站点,%s",

  -- Route options (R26.5)
  ["Fastest"] = "最快",
  ["Safest"] = "最安全",
  ["No flights"] = "不乘飞行",
  ["Route by default"] = "默认路线类型",
  ["Switch to this kind of route; it stays the default."] = "切换到这种路线类型;它将保持为默认。",
  ["Careful: level %d creatures"] = "小心: %d级生物",
  -- the route's verdict (catalog review A4.3, 07.11.2026)
  ["Safe trip"] = "安全旅程",
  ["Watch out"] = "小心",
  ["Risky trip"] = "危险旅程",
  ["elite"] = "精英",

  -- Death.lua (R26.8)
  ["No corpse to go back to."] = "没有可回去的尸体。",
  ["your corpse"] = "你的尸体",
  ["Your corpse"] = "你的尸体",
  ["Died here"] = "死于此处",
  ["Died %s"] = "死于%s",
  ["%d min ago"] = "%d分钟前",
  ["%d h ago"] = "%d小时前",
  ["%d days ago"] = "%d天前",
  ["Click for the way back"] = "点击获取返回的路线",
  ["Click for a route there"] = "点击获取前往那里的路线",
  ["the place of death"] = "死亡地点",
  ["Deaths"] = "死亡记录",
  ["Where you died: your corpse, and the earlier deaths of this character."] = "你的死亡地点: 你的尸体,以及此角色之前的死亡。",
  ["Route back to the corpse after releasing"] = "释放灵魂后规划返回尸体的路线",

  -- Route.lua: messages
  ["Hearth: inn unknown. Type /broute hearth while standing at your inn."] = "炉石: 旅店未知。站在你的旅店时输入 /broute hearth。",
  ["Hearth: you are bound to %s now; type /broute hearth there."] = "炉石: 你现在绑定在%s;请在那里输入 /broute hearth。",
  ["Hearth: no Hearthstone in your bags."] = "炉石: 背包里没有炉石。",
  ["Hearth: ready in %s."] = "炉石: %s后就绪。",
  ["your inn"] = "你的旅店",
  ["No map position here (instance?)"] = "此处没有地图位置(副本?)",
  ["No route to %s"] = "没有前往%s的路线",
  ["You are already there: %s"] = "你已经在那里了: %s",
  ["Route to %s: %s, %d steps"] = "前往%s的路线: %s,%d步",
  ["the marked spot"] = "标记的地点",
  ["Could not re-route to %s from here; keeping the route."] = "无法从这里重新规划前往%s的路线;保留原路线。",
  ["You have arrived: %s"] = "你已到达: %s",
  ["Hearth set: %s"] = "已设置炉石: %s",
  ["here"] = "此处",
  ["Hearth: %s, %s"] = "炉石: %s,%s",
  ["set"] = "已设置",
  ["ready"] = "就绪",
  ["ready in %s"] = "%s后就绪",
  ["Hearth: inn unknown (/broute hearth at your inn)"] = "炉石: 旅店未知(在你的旅店输入 /broute hearth)",
  ["%d flight masters learned, %d flight times measured"] = "已记录%d位飞行管理员,测得%d段飞行时间",

  -- Route.lua: settings and actions
  ["Route"] = "路线",
  ["Flight paths to use"] = "可使用的飞行路线",
  ["Known to this character"] = "此角色已知",
  ["Known to any of my characters"] = "我的任一角色已知",
  ["All flight masters"] = "所有飞行管理员",
  ["Open the step list when a route starts"] = "路线开始时打开步骤列表",
  ["Show an arrow to the next step while a route is active"] = "路线进行时显示指向下一步的箭头",
  -- Flight.lua: the flight bar (catalog review A4.1, 07.11.2026)
  ["Show a flight bar with the time left while flying"] = "飞行时显示带剩余时间的飞行条",
  ["%s to %s"] = "%s 到 %s",
  ["%s left"] = "剩余 %s",
  ["Route here"] = "前往此处的路线",
  ["Route to"] = "路线前往",
  ["Open Bastian's Route"] = "打开 Bastian's Route",

  -- Window.lua
  ["wait up to %s"] = "最多等待%s",
  ["Time"] = "时间",
  ["Distance"] = "距离",
  ["yd"] = "码",
  ["Estimate: a straight line or an unmeasured ride."] = "估算: 直线或未测量的行程。",
  ["Legs marked approx are straight lines or unmeasured rides; the time is an estimate."] = "标有“约”的路段是直线或未测量的行程;时间为估算。",
  ["The map draws them dashed: they may cross water until the route graph knows the terrain."] = "地图用虚线画出它们: 在路线图了解地形之前,它们可能穿过水面。",
  ["No route. Right click anything with a place and choose Route to."] = "没有路线。右键点击任何有位置的东西并选择“路线前往”。",
  ["the target"] = "目标",
  ["To %s: %s, %d steps"] = "前往%s: %s,%d步",
  ["Clear"] = "清除",
  ["Clear the route."] = "清除路线。",
  ["Replan"] = "重新规划",
  ["Plan the route again from where you stand."] = "从你站的位置重新规划路线。",
  ["Click a step to see its end on the map."] = "点击一个步骤,在地图上查看它的终点。",

  -- Graph.lua: the words of a step ("Fly to X", "Go 380 yd SE to X (approx)")
  ["Go"] = "前往",
  ["Fly"] = "飞行",
  ["Take the boat"] = "乘船",
  ["Take the zeppelin"] = "乘飞艇",
  ["Take the tram"] = "乘电车",
  ["Take the portal"] = "使用传送门",
  ["Hearth"] = "炉石",
  ["to"] = "前往",
  ["approx"] = "约",
  -- the broker displays' feed (ADR 0043, 31.10.2026)
  ["%s, %s"] = "%s，%s",
  ["Click: the steps. Right click: clear the route."] = "点击: 步骤。右键: 清除路线。",
  ["and %d more"] = "还有 %d 个",

  -- Welcome, Suite page, Help page, app pages, Words (01.11.2026)
  ["Next: %s"] = "下一步：%s",
  -- the /way command (ADR 0062, 08.11.2026)
  ["/way: %s"] = "/way：%s",
  ["New route"] = "新路线",
  ["Add to route"] = "添加到路线",
  ["Waypoints"] = "路径点",
  ["What /way does while a route runs: start a new route, or add the place to the route."] = "路线进行中 /way 的作用：开始新路线，或把该地点添加到路线中。",
  ["Which addon answers /way: Bastian's Route, or the one that had it first."] = "由哪个插件响应 /way：Bastian's Route，或最先占用它的插件。",
  ["No zone called %s."] = "没有名为 %s 的区域。",
  ["Several zones match %s: %s"] = "有多个区域匹配 %s：%s",
})
