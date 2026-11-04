-- Russian strings of Bastians_Route (ruRU). Keys are the English texts (Locale.lua); loaded after the German file.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
ns.L:Register("ruRU", {
  -- plan-second-wave.md S6 (01.11.2026)
  ["Route home"] = "Маршрут домой",
  -- Arrow.lua
  ["Next step"] = "Следующий шаг",
  ["position unknown"] = "позиция неизвестна",
  ["another continent"] = "другой континент",

  -- Route.lua, Window.lua: home and the teleports (R26.7)
  ["Home"] = "Дом",
  ["The way to your inn, with the hearthstone and every teleport you have ready."] = "Путь к вашей таверне с помощью камня возвращения и всех готовых к использованию телепортов.",
  ["No teleport table in the data."] = "В данных нет таблицы телепортов.",
  ["unknown"] = "неизвестно",
  ["not yours"] = "не ваш",
  ["not castable now"] = "сейчас нельзя применить",
  ["cooldown unknown"] = "время восстановления неизвестно",
  ["landing learned"] = "точка прибытия изучена",
  ["Teleport"] = "Телепорт",

  -- Explore (R26.11)
  ["Explore"] = "Обзор",
  ["what is worth doing nearby"] = "что стоит сделать поблизости",
  ["quest"] = "задание",
  ["farm spot"] = "место фарма",
  ["sale at the auction house"] = "продажа на аукционе",
  ["craft"] = "изготовление",
  ["%s away"] = "в %s отсюда",
  ["XP/h"] = "опыт/ч",
  ["%d without price"] = "без цены: %d",
  ["Explore needs Bastian's Data."] = "Для обзора нужен Bastian's Data.",
  ["Timing the ways from here..."] = "Расчет времени путей отсюда...",
  ["%d things to do within %d min"] = "Дел: %d в пределах %d мин.",
  ["%d ways still being timed"] = "Путей, время которых еще рассчитывается: %d",
  ["%d min"] = "%d мин.",
  ["XP per hour"] = "Опыта в час",
  ["Gold per hour"] = "Золота в час",
  ["Way"] = "Путь",
  -- the session plan (W10 step 3)

  -- departures (R26.6)
  ["Learned when %s leaves; shared with your group and guild."] = "Узнается при отправлении: %s; передается вашей группе и гильдии.",
  ["No boat or zeppelin with departures in the data."] = "В данных нет кораблей и дирижаблей с расписанием.",
  ["leaves in %s"] = "отправляется через %s",

  -- a member of the group (R26.9)
  ["No member of your group called %s."] = "В вашей группе нет участника по имени %s.",
  ["%s has no map position for you (another zone or an instance)."] = "У игрока %s нет для вас позиции на карте (другая зона или подземелье).",

  -- Several stops (R26.4)
  ["Several stops need the route network of this continent."] = "Для нескольких остановок нужна сеть маршрутов этого континента.",
  ["Tour"] = "Обход",
  ["No route through the stops (%s)."] = "Нет маршрута через остановки (%s).",
  ["no way"] = "нет пути",
  ["%d stops left out: another continent, or no way there."] = "Пропущено остановок: %d (другой континент или нет пути).",
  ["%s: %d stops, %s"] = "%s: остановок: %d, %s",

  -- Route options (R26.5)
  ["Fastest"] = "Самый быстрый",
  ["Safest"] = "Самый безопасный",
  ["No flights"] = "Без полетов",
  ["Route by default"] = "Маршрут по умолчанию",
  ["Switch to this kind of route; it stays the default."] = "Переключиться на этот вид маршрута; он останется по умолчанию.",
  ["Careful: level %d creatures"] = "Осторожно: существа уровня %d",
  ["elite"] = "элита",

  -- Death.lua (R26.8)
  ["No corpse to go back to."] = "Нет тела, к которому можно вернуться.",
  ["your corpse"] = "ваше тело",
  ["Your corpse"] = "Ваше тело",
  ["Died here"] = "Погибли здесь",
  ["Died %s"] = "Гибель: %s",
  ["%d min ago"] = "%d мин. назад",
  ["%d h ago"] = "%d ч. назад",
  ["%d days ago"] = "%d дн. назад",
  ["Click for the way back"] = "Щелкните, чтобы найти путь назад",
  ["Click for a route there"] = "Щелкните, чтобы проложить туда маршрут",
  ["the place of death"] = "место гибели",
  ["Deaths"] = "Смерти",
  ["Where you died: your corpse, and the earlier deaths of this character."] = "Где вы погибли: ваше тело и прежние смерти этого персонажа.",
  ["Route back to the corpse after releasing"] = "Прокладывать маршрут к телу после выхода из тела",

  -- Route.lua: messages
  ["Hearth: inn unknown. Type /broute hearth while standing at your inn."] = "Камень возвращения: таверна неизвестна. Введите /broute hearth, находясь в своей таверне.",
  ["Hearth: you are bound to %s now; type /broute hearth there."] = "Камень возвращения: сейчас вы привязаны к месту: %s; введите там /broute hearth.",
  ["Hearth: no Hearthstone in your bags."] = "Камень возвращения: в ваших сумках нет камня возвращения.",
  ["Hearth: ready in %s."] = "Камень возвращения: будет готов через %s.",
  ["your inn"] = "ваша таверна",
  ["No map position here (instance?)"] = "Здесь нет позиции на карте (подземелье?)",
  ["No route to %s"] = "Нет маршрута к цели: %s",
  ["You are already there: %s"] = "Вы уже на месте: %s",
  ["Route to %s: %s, %d steps"] = "Маршрут к цели %s: %s, шагов: %d",
  ["the marked spot"] = "отмеченное место",
  ["Could not re-route to %s from here; keeping the route."] = "Не удалось перепрокладить маршрут к цели %s отсюда; прежний маршрут сохранен.",
  ["You have arrived: %s"] = "Вы прибыли: %s",
  ["Hearth set: %s"] = "Камень возвращения привязан: %s",
  ["here"] = "здесь",
  ["Hearth: %s, %s"] = "Камень возвращения: %s, %s",
  ["set"] = "привязан",
  ["ready"] = "готов",
  ["ready in %s"] = "будет готов через %s",
  ["Hearth: inn unknown (/broute hearth at your inn)"] = "Камень возвращения: таверна неизвестна (/broute hearth в вашей таверне)",
  ["%d flight masters learned, %d flight times measured"] = "Изучено распорядителей полетов: %d, измерено времен полета: %d",

  -- Route.lua: settings and actions
  ["Route"] = "Маршрут",
  ["Flight paths to use"] = "Используемые пути полета",
  ["Known to this character"] = "Известные этому персонажу",
  ["Known to any of my characters"] = "Известные любому из моих персонажей",
  ["All flight masters"] = "Все распорядители полетов",
  ["Open the step list when a route starts"] = "Открывать список шагов при начале маршрута",
  ["Show an arrow to the next step while a route is active"] = "Показывать стрелку к следующему шагу, пока маршрут активен",
  ["Route here"] = "Маршрут сюда",
  ["Route to"] = "Маршрут к",
  ["Open Bastian's Route"] = "Открыть Bastian's Route",

  -- Window.lua
  ["wait up to %s"] = "ждать до %s",
  ["Time"] = "Время",
  ["Distance"] = "Расстояние",
  ["yd"] = "ярд.",
  ["Estimate: a straight line or an unmeasured ride."] = "Оценка: прямая линия или неизмеренная поездка.",
  ["Legs marked approx are straight lines or unmeasured rides; the time is an estimate."] = 'Участки с пометкой "прим." - это прямые линии или неизмеренные поездки; время указано приблизительно.',
  ["The map draws them dashed: they may cross water until the route graph knows the terrain."] = "Карта рисует их пунктиром: они могут пересекать воду, пока граф маршрутов не знает местность.",
  ["No route. Right click anything with a place and choose Route to."] = 'Маршрута нет. Щелкните правой кнопкой по чему угодно с местом и выберите "Маршрут к".',
  ["the target"] = "цель",
  ["To %s: %s, %d steps"] = "К цели %s: %s, шагов: %d",
  ["Clear"] = "Сбросить",
  ["Clear the route."] = "Сбросить маршрут.",
  ["Replan"] = "Перепланировать",
  ["Plan the route again from where you stand."] = "Спланировать маршрут заново с того места, где вы стоите.",
  ["Click a step to see its end on the map."] = "Щелкните шаг, чтобы увидеть его конец на карте.",

  -- Graph.lua: the words of a step ("Fly to X", "Go 380 yd SE to X (approx)")
  ["Go"] = "Идти",
  ["Fly"] = "Лететь",
  ["Take the boat"] = "Сесть на корабль",
  ["Take the zeppelin"] = "Сесть на дирижабль",
  ["Take the tram"] = "Сесть на трамвай",
  ["Take the portal"] = "Войти в портал",
  ["Hearth"] = "Камень возвращения",
  ["to"] = "к",
  ["approx"] = "прим.",
  -- the broker displays' feed (ADR 0043, 31.10.2026)
  ["%s, %s"] = "%s, %s",
  ["Click: the steps. Right click: clear the route."] = "Щелчок: шаги. Правый щелчок: сбросить маршрут.",
  ["and %d more"] = "и еще %d",

  -- Welcome, Suite page, Help page, app pages, Words (01.11.2026)
  ["Next: %s"] = "Далее: %s",
})
