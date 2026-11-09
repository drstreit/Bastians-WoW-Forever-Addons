-- Korean strings of Bastians_Route (koKR). Keys are the English texts (Locale.lua); loaded after the German file.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
ns.L:Register("koKR", {
  -- plan-second-wave.md S6 (01.11.2026)
  ["Route home"] = "집으로 가는 길",
  -- Arrow.lua
  ["Next step"] = "다음 단계",
  ["position unknown"] = "위치 알 수 없음",
  ["another continent"] = "다른 대륙",

  -- Route.lua, Window.lua: home and the teleports (R26.7)
  ["Home"] = "집",
  ["The way to your inn, with the hearthstone and every teleport you have ready."] = "귀환석과 사용 가능한 모든 순간이동을 활용해 여관으로 가는 길입니다.",
  ["No teleport table in the data."] = "데이터에 순간이동 표가 없습니다.",
  ["unknown"] = "알 수 없음",
  ["not yours"] = "보유하지 않음",
  ["not castable now"] = "지금은 시전 불가",
  ["cooldown unknown"] = "재사용 대기시간 알 수 없음",
  ["landing learned"] = "도착 지점 확인됨",
  ["Teleport"] = "순간이동",

  -- Explore (R26.11)
  ["Explore"] = "탐색",
  ["what is worth doing nearby"] = "근처에서 해 볼 만한 일",
  ["quest"] = "퀘스트",
  ["farm spot"] = "사냥터",
  ["sale at the auction house"] = "경매장 판매",
  ["craft"] = "제작",
  ["%s away"] = "%s 거리",
  ["XP/h"] = "시간당 경험치",
  ["%d without price"] = "가격 없음 %d개",
  ["Explore needs Bastian's Data."] = "탐색에는 Bastian's Data가 필요합니다.",
  ["Timing the ways from here..."] = "여기서 가는 길의 시간을 계산하는 중...",
  ["%d things to do within %d min"] = "할 일 %d개 (%d분 이내)",
  ["%d ways still being timed"] = "시간 계산 중인 길 %d개",
  ["%d min"] = "%d분",
  ["XP per hour"] = "시간당 경험치",
  ["Gold per hour"] = "시간당 골드",
  ["Way"] = "길",

  -- departures (R26.6)
  ["Learned when %s leaves; shared with your group and guild."] = "%s이(가) 출발할 때 기록되며, 파티와 길드에 공유됩니다.",
  ["No boat or zeppelin with departures in the data."] = "데이터에 출발 시간이 있는 배나 비행선이 없습니다.",
  ["leaves in %s"] = "%s 후 출발",

  -- a member of the group (R26.9)
  ["No member of your group called %s."] = "파티에 %s(이)라는 구성원이 없습니다.",
  ["%s has no map position for you (another zone or an instance)."] = "%s의 지도 위치를 알 수 없습니다 (다른 지역이거나 던전).",

  -- Several stops (R26.4)
  ["Several stops need the route network of this continent."] = "여러 경유지에는 이 대륙의 경로망이 필요합니다.",
  ["Tour"] = "순회",
  ["No route through the stops (%s)."] = "경유지를 잇는 경로가 없습니다 (%s).",
  ["no way"] = "길 없음",
  ["%d stops left out: another continent, or no way there."] = "경유지 %d곳 제외: 다른 대륙이거나 가는 길이 없습니다.",
  ["%s: %d stops, %s"] = "%s: 경유지 %d곳, %s",

  -- Route options (R26.5)
  ["Fastest"] = "가장 빠르게",
  ["Safest"] = "가장 안전하게",
  ["No flights"] = "비행 제외",
  ["Route by default"] = "기본 경로 방식",
  ["Switch to this kind of route; it stays the default."] = "이 경로 방식으로 전환하며, 기본값으로 유지됩니다.",
  ["Careful: level %d creatures"] = "주의: 레벨 %d 몬스터",
  -- the route's verdict (catalog review A4.3, 07.11.2026)
  ["Safe trip"] = "안전한 여정",
  ["Watch out"] = "주의",
  ["Risky trip"] = "위험한 여정",
  ["elite"] = "정예",

  -- Death.lua (R26.8)
  ["No corpse to go back to."] = "돌아갈 시체가 없습니다.",
  ["your corpse"] = "내 시체",
  ["Your corpse"] = "내 시체",
  ["Died here"] = "여기서 사망",
  ["Died %s"] = "%s 사망",
  ["%d min ago"] = "%d분 전",
  ["%d h ago"] = "%d시간 전",
  ["%d days ago"] = "%d일 전",
  ["Click for the way back"] = "클릭하면 돌아가는 길을 안내합니다",
  ["Click for a route there"] = "클릭하면 그곳으로 가는 경로를 안내합니다",
  ["the place of death"] = "사망 장소",
  ["Deaths"] = "사망 기록",
  ["Where you died: your corpse, and the earlier deaths of this character."] = "사망한 장소: 내 시체와 이 캐릭터의 이전 사망 기록.",
  ["Route back to the corpse after releasing"] = "영혼 해방 후 시체로 돌아가는 경로 표시",

  -- Route.lua: messages
  ["Hearth: inn unknown. Type /broute hearth while standing at your inn."] = "귀환: 여관을 알 수 없습니다. 여관에 서서 /broute hearth를 입력하세요.",
  ["Hearth: you are bound to %s now; type /broute hearth there."] = "귀환: 현재 %s에 귀환 지정되어 있습니다. 그곳에서 /broute hearth를 입력하세요.",
  ["Hearth: no Hearthstone in your bags."] = "귀환: 가방에 귀환석이 없습니다.",
  ["Hearth: ready in %s."] = "귀환: %s 후 사용 가능.",
  ["your inn"] = "내 여관",
  ["No map position here (instance?)"] = "여기에는 지도 위치가 없습니다 (던전인가요?)",
  ["No route to %s"] = "%s(으)로 가는 경로가 없습니다",
  ["You are already there: %s"] = "이미 도착했습니다: %s",
  ["Route to %s: %s, %d steps"] = "%s(으)로 가는 경로: %s, %d단계",
  ["the marked spot"] = "표시한 지점",
  ["Could not re-route to %s from here; keeping the route."] = "여기서 %s(으)로 경로를 다시 만들 수 없어 기존 경로를 유지합니다.",
  ["You have arrived: %s"] = "도착했습니다: %s",
  ["Hearth set: %s"] = "귀환 지정됨: %s",
  ["here"] = "여기",
  ["Hearth: %s, %s"] = "귀환: %s, %s",
  ["set"] = "지정됨",
  ["ready"] = "사용 가능",
  ["ready in %s"] = "%s 후 사용 가능",
  ["Hearth: inn unknown (/broute hearth at your inn)"] = "귀환: 여관 알 수 없음 (여관에서 /broute hearth)",
  ["%d flight masters learned, %d flight times measured"] = "비행 조련사 %d명 확인, 비행 시간 %d건 측정",

  -- Route.lua: settings and actions
  ["Route"] = "경로",
  ["Flight paths to use"] = "사용할 비행 경로",
  ["Known to this character"] = "이 캐릭터가 아는 곳",
  ["Known to any of my characters"] = "내 캐릭터 중 누구든 아는 곳",
  ["All flight masters"] = "모든 비행 조련사",
  ["Open the step list when a route starts"] = "경로가 시작되면 단계 목록 열기",
  ["Show an arrow to the next step while a route is active"] = "경로가 활성화된 동안 다음 단계를 가리키는 화살표 표시",
  -- Flight.lua: the flight bar (catalog review A4.1, 07.11.2026)
  ["Show a flight bar with the time left while flying"] = "비행 중 남은 시간을 보여주는 비행 막대 표시",
  ["%s to %s"] = "%s에서 %s",
  ["%s left"] = "%s 남음",
  ["Route here"] = "여기로 경로 만들기",
  ["Route to"] = "경로 목적지:",
  ["Open Bastian's Route"] = "Bastian's Route 열기",

  -- Window.lua
  ["wait up to %s"] = "최대 %s 대기",
  ["Time"] = "시간",
  ["Distance"] = "거리",
  ["yd"] = "야드",
  ["Estimate: a straight line or an unmeasured ride."] = "추정: 직선 또는 측정되지 않은 이동.",
  ["Legs marked approx are straight lines or unmeasured rides; the time is an estimate."] = '"약"으로 표시된 구간은 직선이거나 측정되지 않은 이동이며, 시간은 추정치입니다.',
  ["The map draws them dashed: they may cross water until the route graph knows the terrain."] = "지도에 점선으로 표시됩니다. 경로 그래프가 지형을 파악하기 전까지는 물을 가로지를 수 있습니다.",
  ["No route. Right click anything with a place and choose Route to."] = "경로가 없습니다. 장소가 있는 항목을 오른쪽 클릭하고 '경로 목적지'를 선택하세요.",
  ["the target"] = "대상",
  ["To %s: %s, %d steps"] = "%s까지: %s, %d단계",
  ["Clear"] = "지우기",
  ["Clear the route."] = "경로를 지웁니다.",
  ["Replan"] = "다시 계획",
  ["Plan the route again from where you stand."] = "현재 위치에서 경로를 다시 계획합니다.",
  ["Click a step to see its end on the map."] = "단계를 클릭하면 지도에서 그 끝 지점을 볼 수 있습니다.",

  -- Graph.lua: the words of a step ("Fly to X", "Go 380 yd SE to X (approx)")
  ["Go"] = "이동",
  ["Fly"] = "비행",
  ["Take the boat"] = "배 탑승",
  ["Take the zeppelin"] = "비행선 탑승",
  ["Take the tram"] = "지하철 탑승",
  ["Take the portal"] = "차원문 이용",
  ["Hearth"] = "귀환",
  ["to"] = "목적지:",
  ["approx"] = "약",
  -- the broker displays' feed (ADR 0043, 31.10.2026)
  ["%s, %s"] = "%s, %s",
  ["Click: the steps. Right click: clear the route."] = "클릭: 단계. 오른쪽 클릭: 경로 지우기.",
  ["and %d more"] = "외 %d개",

  -- Welcome, Suite page, Help page, app pages, Words (01.11.2026)
  ["Next: %s"] = "다음: %s",
  -- the /way command (ADR 0062, 08.11.2026)
  ["/way: %s"] = "/way: %s",
  ["New route"] = "새 경로",
  ["Add to route"] = "경로에 추가",
  ["Waypoints"] = "경유지",
  ["What /way does while a route runs: start a new route, or add the place to the route."] = "경로 진행 중 /way의 동작: 새 경로를 시작하거나 그 장소를 경로에 추가합니다.",
  ["Which addon answers /way: Bastian's Route, or the one that had it first."] = "/way에 응답할 애드온: Bastian's Route 또는 먼저 사용하던 애드온.",
  ["No zone called %s."] = "%s(이)라는 지역이 없습니다.",
  ["Several zones match %s: %s"] = "%s에 해당하는 지역이 여러 개입니다: %s",
})
