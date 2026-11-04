-- Spanish strings of Bastians_Route (esES, esMX). Keys are the English texts (Locale.lua); loaded after the German file.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local strings = {
  -- plan-second-wave.md S6 (01.11.2026)
  ["Route home"] = "Ruta a casa",
  -- Arrow.lua
  ["Next step"] = "Siguiente paso",
  ["position unknown"] = "posición desconocida",
  ["another continent"] = "otro continente",

  -- Route.lua, Window.lua: home and the teleports (R26.7)
  ["Home"] = "Hogar",
  ["The way to your inn, with the hearthstone and every teleport you have ready."] = "El camino a tu posada, con la piedra de hogar y cada teletransporte que tengas listo.",
  ["No teleport table in the data."] = "No hay tabla de teletransportes en los datos.",
  ["unknown"] = "desconocido",
  ["not yours"] = "no es tuyo",
  ["not castable now"] = "no se puede lanzar ahora",
  ["cooldown unknown"] = "tiempo de reutilización desconocido",
  ["landing learned"] = "punto de llegada aprendido",
  ["Teleport"] = "Teletransporte",

  -- Explore (R26.11)
  ["Explore"] = "Explorar",
  ["what is worth doing nearby"] = "lo que merece la pena hacer cerca",
  ["quest"] = "misión",
  ["farm spot"] = "lugar de farmeo",
  ["sale at the auction house"] = "venta en la casa de subastas",
  ["craft"] = "fabricación",
  ["%s away"] = "a %s",
  ["XP/h"] = "PX/h",
  ["%d without price"] = "%d sin precio",
  ["Explore needs Bastian's Data."] = "Explorar requiere Bastian's Data.",
  ["Timing the ways from here..."] = "Calculando los trayectos desde aquí...",
  ["%d things to do within %d min"] = "%d cosas por hacer en %d min como máximo",
  ["%d ways still being timed"] = "%d trayectos aún se están calculando",
  ["%d min"] = "%d min",
  ["XP per hour"] = "PX por hora",
  ["Gold per hour"] = "Oro por hora",
  ["Way"] = "Trayecto",

  -- departures (R26.6)
  ["Learned when %s leaves; shared with your group and guild."] = "Se aprende cuando %s zarpa; compartido con tu grupo y tu hermandad.",
  ["No boat or zeppelin with departures in the data."] = "No hay barcos ni zepelines con salidas en los datos.",
  ["leaves in %s"] = "sale en %s",

  -- a member of the group (R26.9)
  ["No member of your group called %s."] = "Ningún miembro de tu grupo se llama %s.",
  ["%s has no map position for you (another zone or an instance)."] = "%s no tiene posición en el mapa para ti (otra zona o una instancia).",

  -- Several stops (R26.4)
  ["Several stops need the route network of this continent."] = "Varias paradas requieren la red de rutas de este continente.",
  ["Tour"] = "Recorrido",
  ["No route through the stops (%s)."] = "No hay ruta por las paradas (%s).",
  ["no way"] = "sin camino",
  ["%d stops left out: another continent, or no way there."] = "%d paradas excluidas: otro continente o sin camino hasta allí.",
  ["%s: %d stops, %s"] = "%s: %d paradas, %s",

  -- Route options (R26.5)
  ["Fastest"] = "La más rápida",
  ["Safest"] = "La más segura",
  ["No flights"] = "Sin vuelos",
  ["Route by default"] = "Ruta por defecto",
  ["Switch to this kind of route; it stays the default."] = "Cambiar a este tipo de ruta; sigue siendo la predeterminada.",
  ["Careful: level %d creatures"] = "Cuidado: criaturas de nivel %d",
  ["elite"] = "élite",

  -- Death.lua (R26.8)
  ["No corpse to go back to."] = "No hay cadáver al que volver.",
  ["your corpse"] = "tu cadáver",
  ["Your corpse"] = "Tu cadáver",
  ["Died here"] = "Muerto aquí",
  ["Died %s"] = "Muerto %s",
  ["%d min ago"] = "hace %d min",
  ["%d h ago"] = "hace %d h",
  ["%d days ago"] = "hace %d días",
  ["Click for the way back"] = "Haz clic para el camino de vuelta",
  ["Click for a route there"] = "Haz clic para una ruta hasta allí",
  ["the place of death"] = "el lugar de la muerte",
  ["Deaths"] = "Muertes",
  ["Where you died: your corpse, and the earlier deaths of this character."] = "Dónde moriste: tu cadáver y las muertes anteriores de este personaje.",
  ["Route back to the corpse after releasing"] = "Trazar la ruta al cadáver tras liberar el espíritu",

  -- Route.lua: messages
  ["Hearth: inn unknown. Type /broute hearth while standing at your inn."] = "Hogar: posada desconocida. Escribe /broute hearth mientras estás en tu posada.",
  ["Hearth: you are bound to %s now; type /broute hearth there."] = "Hogar: ahora estás vinculado a %s; escribe /broute hearth allí.",
  ["Hearth: no Hearthstone in your bags."] = "Hogar: no hay piedra de hogar en tus bolsas.",
  ["Hearth: ready in %s."] = "Hogar: lista en %s.",
  ["your inn"] = "tu posada",
  ["No map position here (instance?)"] = "Sin posición en el mapa aquí (¿instancia?)",
  ["No route to %s"] = "No hay ruta a %s",
  ["You are already there: %s"] = "Ya estás allí: %s",
  ["Route to %s: %s, %d steps"] = "Ruta a %s: %s, %d pasos",
  ["the marked spot"] = "el punto marcado",
  ["Could not re-route to %s from here; keeping the route."] = "No se pudo recalcular la ruta a %s desde aquí; se mantiene la ruta.",
  ["You have arrived: %s"] = "Has llegado: %s",
  ["Hearth set: %s"] = "Hogar establecido: %s",
  ["here"] = "aquí",
  ["Hearth: %s, %s"] = "Hogar: %s, %s",
  ["set"] = "establecido",
  ["ready"] = "lista",
  ["ready in %s"] = "lista en %s",
  ["Hearth: inn unknown (/broute hearth at your inn)"] = "Hogar: posada desconocida (/broute hearth en tu posada)",
  ["%d flight masters learned, %d flight times measured"] = "%d maestros de vuelo aprendidos, %d tiempos de vuelo medidos",

  -- Route.lua: settings and actions
  ["Route"] = "Ruta",
  ["Flight paths to use"] = "Rutas de vuelo a usar",
  ["Known to this character"] = "Conocidas por este personaje",
  ["Known to any of my characters"] = "Conocidas por alguno de mis personajes",
  ["All flight masters"] = "Todos los maestros de vuelo",
  ["Open the step list when a route starts"] = "Abrir la lista de pasos al empezar una ruta",
  ["Show an arrow to the next step while a route is active"] = "Mostrar una flecha al siguiente paso mientras haya una ruta activa",
  ["Route here"] = "Ruta hasta aquí",
  ["Route to"] = "Ruta a",
  ["Open Bastian's Route"] = "Abrir Bastian's Route",

  -- Window.lua
  ["wait up to %s"] = "esperar hasta %s",
  ["Time"] = "Tiempo",
  ["Distance"] = "Distancia",
  ["yd"] = "m",
  ["Estimate: a straight line or an unmeasured ride."] = "Estimación: una línea recta o un trayecto sin medir.",
  ["Legs marked approx are straight lines or unmeasured rides; the time is an estimate."] = 'Los tramos marcados "aprox." son líneas rectas o trayectos sin medir; el tiempo es una estimación.',
  ["The map draws them dashed: they may cross water until the route graph knows the terrain."] = "El mapa los dibuja con línea discontinua: pueden cruzar agua hasta que el grafo de rutas conozca el terreno.",
  ["No route. Right click anything with a place and choose Route to."] = "Sin ruta. Haz clic derecho en cualquier cosa con un lugar y elige Ruta a.",
  ["the target"] = "el destino",
  ["To %s: %s, %d steps"] = "A %s: %s, %d pasos",
  ["Clear"] = "Borrar",
  ["Clear the route."] = "Borrar la ruta.",
  ["Replan"] = "Recalcular",
  ["Plan the route again from where you stand."] = "Volver a planificar la ruta desde donde estás.",
  ["Click a step to see its end on the map."] = "Haz clic en un paso para ver su final en el mapa.",

  -- Graph.lua: the words of a step ("Fly to X", "Go 380 yd SE to X (approx)")
  ["Go"] = "Ir",
  ["Fly"] = "Volar",
  ["Take the boat"] = "Toma el barco",
  ["Take the zeppelin"] = "Toma el zepelín",
  ["Take the tram"] = "Toma el tranvía",
  ["Take the portal"] = "Toma el portal",
  ["Hearth"] = "Piedra de hogar",
  ["to"] = "a",
  ["approx"] = "aprox.",
  -- the broker displays' feed (ADR 0043, 31.10.2026)
  ["%s, %s"] = "%s, %s",
  ["Click: the steps. Right click: clear the route."] = "Clic: los pasos. Clic derecho: borrar la ruta.",
  ["and %d more"] = "y %d más",

  -- Welcome, Suite page, Help page, app pages, Words (01.11.2026)
  ["Next: %s"] = "Siguiente: %s",
}
ns.L:Register("esES", strings)
ns.L:Register("esMX", strings)
