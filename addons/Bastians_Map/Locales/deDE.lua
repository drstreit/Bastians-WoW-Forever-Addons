-- German strings of Bastians_Map (deDE). Keys are the English texts (Locale.lua); loaded before the
-- addon's other files so load-time labels are translated too.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
ns.L:Register("deDE", {
  -- Focus.lua
  ["Follow"] = "Folgen",
  ["While on, the map flies to what you open or focus in the other windows."] = "Wenn an, fliegt die Karte zu dem, was du in den anderen Fenstern öffnest oder fokussierst.",
  ["Dock"] = "Andocken",
  ["Dock the Browser"] = "Den Browser andocken",
  ["Opens the Browser beside the map at its height; both move together. Click again to undock."] = "Öffnet den Browser neben der Karte in ihrer Höhe; beide bewegen sich zusammen. Klicke erneut, um ihn zu lösen.",

  -- Imagery.lua, Map.lua
  ["Level"] = "Stufe",
  ["zoom"] = "Zoom",
  ["Map"] = "Karte",
  ["Player"] = "Spieler",
  ["Centre the map on you."] = "Die Karte auf dich zentrieren.",
  ["No map position here (instance?)"] = "Hier keine Kartenposition (Instanz?)",
  ["Full"] = "Voll",
  ["Full screen, and back."] = "Vollbild und zurück.",
  ["Back"] = "Zurück",
  ["Zoom in (or the mouse wheel)."] = "Hineinzoomen (oder das Mausrad).",
  ["Zoom out (or the mouse wheel)."] = "Herauszoomen (oder das Mausrad).",
  ["Imagery"] = "Kartenbild",
  ["Native minimap tiles at close zoom"] = "Originale Minimap-Kacheln bei naher Ansicht",
  ["Overview textures from Bastian's Map Art"] = "Übersichtstexturen aus Bastian's Map Art",
  ["The minimap"] = "Die Minimap",
  ["Show the map's layers on the minimap (the nearest pins, arrows at the rim)"] = "Die Ebenen der Karte auf der Minimap zeigen (die nächsten Markierungen, Pfeile am Rand)",
  ["Pins on the minimap at most"] = "Höchstens so viele Markierungen auf der Minimap",
  ["The game's map"] = "Die Karte des Spiels",
  ["Open Bastian's map instead of the game's (instances and caves stay on the game's map)"] = "Bastians Karte statt der des Spiels öffnen (Instanzen und Höhlen bleiben auf der Karte des Spiels)",
  ["Draw Bastian's map art over the game's map"] = "Bastians Kartenbild über die Karte des Spiels zeichnen",
  ["Open Bastian's Map"] = "Bastians Karte öffnen",
  ["Usage: /bmap [player | ek | kalimdor | stats]"] = "Verwendung: /bmap [player | ek | kalimdor | stats]",
  ["The map has not been opened yet."] = "Die Karte wurde noch nicht geöffnet.",
  ["Minimap tiles"] = "Minimap-Kacheln",
  ["Overview cells"] = "Übersichtszellen",
  ["Zone art"] = "Zonenbilder",
  ["textures"] = "Texturen",
  ["zones"] = "Zonen",
  ["labels"] = "Beschriftungen",
  ["first"] = "erste",
  ["art tiles"] = "Bildkacheln",
  ["Pins"] = "Markierungen",
  ["pins"] = "Markierungen",
  ["clusters"] = "Gruppen",
  ["areas"] = "Gebiete",
  ["lines"] = "Linien",

  -- Overview.lua
  ["The overview textures were built for %s; zone art is shown at low zoom instead."] = "Die Übersichtstexturen wurden für %s erstellt; stattdessen werden bei kleinem Zoom Zonenbilder gezeigt.",
  ["Bastian's Map Art is not installed: zone art is shown at low zoom."] = "Bastian's Map Art ist nicht installiert: Bei kleinem Zoom werden Zonenbilder gezeigt.",
  ["Bastian's Map Art has no overview textures: run the pipeline command mapart --overview."] = "Bastian's Map Art hat keine Übersichtstexturen: Führe den Pipeline-Befehl mapart --overview aus.",
  ["Bastian's Map Art could not be loaded; zone art is shown at low zoom."] = "Bastian's Map Art konnte nicht geladen werden; bei kleinem Zoom werden Zonenbilder gezeigt.",
  ["Bastian's Map Art loads when the map opens."] = "Bastian's Map Art lädt, wenn die Karte geöffnet wird.",
  ["Overview cells: %s"] = "Übersichtszellen: %s",

  -- Pins.lua
  ["Reward"] = "Belohnung",
  ["Click to open"] = "Klicken zum Öffnen",
  ["worth"] = "Wert",
  ["%d pins"] = "%d Markierungen",
  ["Click to zoom in"] = "Klicken zum Hineinzoomen",
  ["Layers"] = "Ebenen",
  ["Which layers the map shows: quests, NPCs, nodes, routes and more."] = "Welche Ebenen die Karte zeigt: Quests, NPCs, Sammelpunkte, Routen und mehr.",

  -- Search.lua
  ["Route"] = "Route",
  ["Plan a route there."] = "Eine Route dorthin planen.",
  ["No matches."] = "Keine Treffer.",
  ["Search the world ..."] = "Die Welt durchsuchen ...",

  -- Tiles.lua
  ["No minimap tile table: run the pipeline command mapart (map.md). Zone art is shown instead."] = "Keine Minimap-Kachelliste: Führe den Pipeline-Befehl mapart aus (map.md). Stattdessen werden Zonenbilder gezeigt.",
  ["The minimap tile table was built for %s; zone art is shown instead."] = "Die Minimap-Kachelliste wurde für %s erstellt; stattdessen werden Zonenbilder gezeigt.",
  ["Minimap tiles: %s"] = "Minimap-Kacheln: %s",

  -- Waypoints.lua
  ["Waypoint"] = "Wegpunkt",
  ["Show on map"] = "Auf der Karte zeigen",
  ["TomTom waypoint"] = "TomTom-Wegpunkt",
  ["Copy /way"] = "/way kopieren",

  -- continents (the footer and the continent list)
  ["Eastern Kingdoms"] = "Östliche Königreiche",
  ["Kalimdor"] = "Kalimdor",
  ["Outland"] = "Scherbenwelt",
  ["Northrend"] = "Nordend",
  ["?"] = "?",

  -- entity type words (the search results' type)
  ["npc"] = "NPC",
  ["item"] = "Gegenstand",
  ["quest"] = "Quest",
  ["zone"] = "Zone",
  ["object"] = "Objekt",
  ["node"] = "Sammelpunkt",
  ["spot"] = "Farmplatz",
  ["strategy"] = "Strategie",
  ["recipe"] = "Rezept",
  ["flightpath"] = "Flugroute",
  ["transport"] = "Transport",
})
