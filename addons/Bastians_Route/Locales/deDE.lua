-- German strings of Bastians_Route (deDE). Keys are the English texts (Locale.lua); loaded before the
-- addon's other files so load-time labels are translated too.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
ns.L:Register("deDE", {
  -- Arrow.lua
  ["Next step"] = "Nächster Schritt",
  ["position unknown"] = "Position unbekannt",
  ["another continent"] = "anderer Kontinent",

  -- Route.lua: messages
  ["Hearth: inn unknown. Type /broute hearth while standing at your inn."] = "Ruhestein: Gasthaus unbekannt. Gib /broute hearth ein, während du an deinem Gasthaus stehst.",
  ["Hearth: you are bound to %s now; type /broute hearth there."] = "Ruhestein: Du bist jetzt an %s gebunden; gib dort /broute hearth ein.",
  ["Hearth: no Hearthstone in your bags."] = "Ruhestein: Kein Ruhestein in deinen Taschen.",
  ["Hearth: ready in %s."] = "Ruhestein: bereit in %s.",
  ["your inn"] = "dein Gasthaus",
  ["No map position here (instance?)"] = "Hier keine Kartenposition (Instanz?)",
  ["No route to %s"] = "Keine Route nach %s",
  ["You are already there: %s"] = "Du bist schon dort: %s",
  ["Route to %s: %s, %d steps"] = "Route nach %s: %s, %d Schritte",
  ["the marked spot"] = "der markierte Ort",
  ["Could not re-route to %s from here; keeping the route."] = "Von hier konnte keine neue Route nach %s berechnet werden; die Route bleibt.",
  ["You have arrived: %s"] = "Du bist angekommen: %s",
  ["Hearth set: %s"] = "Ruhestein gesetzt: %s",
  ["here"] = "hier",
  ["Hearth: %s, %s"] = "Ruhestein: %s, %s",
  ["set"] = "gesetzt",
  ["ready"] = "bereit",
  ["ready in %s"] = "bereit in %s",
  ["Hearth: inn unknown (/broute hearth at your inn)"] = "Ruhestein: Gasthaus unbekannt (/broute hearth an deinem Gasthaus)",
  ["%d flight masters learned, %d flight times measured"] = "%d Flugmeister gelernt, %d Flugzeiten gemessen",

  -- Route.lua: settings and actions
  ["Route"] = "Route",
  ["Flight paths to use"] = "Zu nutzende Flugrouten",
  ["Known to this character"] = "Diesem Charakter bekannt",
  ["Known to any of my characters"] = "Einem meiner Charaktere bekannt",
  ["All flight masters"] = "Alle Flugmeister",
  ["Open the step list when a route starts"] = "Die Schrittliste öffnen, wenn eine Route beginnt",
  ["Show an arrow to the next step while a route is active"] = "Einen Pfeil zum nächsten Schritt zeigen, solange eine Route aktiv ist",
  ["Use TomTom's arrow when TomTom is installed"] = "Den Pfeil von TomTom nutzen, wenn TomTom installiert ist",
  ["Route here"] = "Route hierher",
  ["Route to"] = "Route zu",
  ["Open Bastian's Route"] = "Bastian's Route öffnen",

  -- Window.lua
  ["wait up to %s"] = "bis zu %s warten",
  ["Time"] = "Zeit",
  ["Distance"] = "Entfernung",
  ["yd"] = "Yd.",
  ["Estimate: a straight line or an unmeasured ride."] = "Schätzung: eine gerade Linie oder eine ungemessene Fahrt.",
  ["Legs marked approx are straight lines or unmeasured rides; the time is an estimate."] = 'Etappen mit "ca." sind gerade Linien oder ungemessene Fahrten; die Zeit ist eine Schätzung.',
  ["The map draws them dashed: they may cross water until the route graph knows the terrain."] = "Die Karte zeichnet sie gestrichelt: Sie können über Wasser führen, bis der Routengraph das Gelände kennt.",
  ["No route. Right click anything with a place and choose Route to."] = "Keine Route. Klicke etwas mit einem Ort rechts an und wähle Route zu.",
  ["the target"] = "das Ziel",
  ["To %s: %s, %d steps"] = "Nach %s: %s, %d Schritte",
  ["Clear"] = "Löschen",
  ["Clear the route."] = "Die Route löschen.",
  ["Replan"] = "Neu planen",
  ["Plan the route again from where you stand."] = "Die Route von deinem Standort aus neu planen.",
  ["Click a step to see its end on the map."] = "Klicke auf einen Schritt, um sein Ende auf der Karte zu sehen.",

  -- Graph.lua: the words of a step ("Fly to X", "Go 380 yd SE to X (approx)")
  ["Go"] = "Gehe",
  ["Fly"] = "Fliege",
  ["Take the boat"] = "Nimm das Schiff",
  ["Take the zeppelin"] = "Nimm den Zeppelin",
  ["Take the tram"] = "Nimm die Tram",
  ["Take the portal"] = "Nimm das Portal",
  ["Hearth"] = "Ruhestein",
  ["to"] = "zu",
  ["approx"] = "ca.",
})
