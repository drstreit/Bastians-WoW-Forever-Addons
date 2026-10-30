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

  -- Route.lua, Window.lua: home and the teleports (R26.7)
  ["Home"] = "Heim",
  ["The way to your inn, with the hearthstone and every teleport you have ready."] = "Der Weg zu deinem Gasthaus, mit dem Ruhestein und jedem Teleport, den du bereit hast.",
  ["No teleport table in the data."] = "Keine Teleport-Tabelle in den Daten.",
  ["unknown"] = "unbekannt",
  ["not yours"] = "nicht deiner",
  ["not castable now"] = "gerade nicht wirkbar",
  ["cooldown unknown"] = "Abklingzeit unbekannt",
  ["landing learned"] = "Landeplatz gelernt",
  ["Teleport"] = "Teleport",

  -- Explore (R26.11)
  ["Explore"] = "Erkunden",
  ["what is worth doing nearby"] = "was sich in der Nähe lohnt",
  ["quest"] = "Quest",
  ["farm spot"] = "Farmspot",
  ["sale at the auction house"] = "Verkauf im Auktionshaus",
  ["craft"] = "Herstellen",
  ["%s away"] = "%s entfernt",
  ["XP/h"] = "EP/h",
  ["%d without price"] = "%d ohne Preis",
  ["Explore needs Bastian's Data."] = "Erkunden braucht Bastian's Data.",
  ["Timing the ways from here..."] = "Die Wege von hier werden berechnet ...",
  ["%d things to do within %d min"] = "%d Dinge in höchstens %d min Weg",
  ["%d ways still being timed"] = "%d Wege werden noch berechnet",
  ["%d min"] = "%d min",
  ["XP per hour"] = "EP pro Stunde",
  ["Gold per hour"] = "Gold pro Stunde",
  ["Way"] = "Weg",
  -- the session plan (W10 step 3)
  ["List"] = "Liste",
  ["Plan %d min"] = "Plan %d min",
  ["arrive in %s, %s there, +%s"] = "Ankunft in %s, %s dort, +%s",
  ["(way estimated)"] = "(Weg geschätzt)",
  ["Nothing fits into %d min from here."] = "Von hier passt nichts in %d min.",
  ["Plan for %d min: %d stops, %s, %s"] = "Plan für %d min: %d Stationen, %s, %s",
  ["Route the plan"] = "Plan als Route",
  ["A route through the plan's stops, in order."] = "Eine Route durch die Stationen des Plans, der Reihe nach.",
  ["My plan"] = "Mein Plan",
  ["XP"] = "EP",

  -- departures (R26.6)
  ["Learned when %s leaves; shared with your group and guild."] = "Gelernt, wann %s ablegt; mit Gruppe und Gilde geteilt.",
  ["No boat or zeppelin with departures in the data."] = "Kein Schiff und kein Zeppelin mit Abfahrten in den Daten.",
  ["leaves in %s"] = "legt ab in %s",

  -- a member of the group (R26.9)
  ["No member of your group called %s."] = "Kein Mitglied deiner Gruppe heißt %s.",
  ["%s has no map position for you (another zone or an instance)."] = "%s hat für dich keine Kartenposition (andere Zone oder Instanz).",

  -- Several stops (R26.4)
  ["Several stops need the route network of this continent."] = "Mehrere Stopps brauchen das Wegenetz dieses Kontinents.",
  ["Tour"] = "Tour",
  ["No route through the stops (%s)."] = "Keine Route durch die Stopps (%s).",
  ["no way"] = "kein Weg",
  ["%d stops left out: another continent, or no way there."] = "%d Stopps ausgelassen: anderer Kontinent oder kein Weg dorthin.",
  ["%s: %d stops, %s"] = "%s: %d Stopps, %s",

  -- Route options (R26.5)
  ["Fastest"] = "Schnellste",
  ["Safest"] = "Sicherste",
  ["No flights"] = "Ohne Flüge",
  ["Route by default"] = "Route standardmäßig",
  ["Switch to this kind of route; it stays the default."] = "Zu dieser Art Route wechseln; sie bleibt die Vorgabe.",
  ["Careful: level %d creatures"] = "Vorsicht: Kreaturen der Stufe %d",
  ["elite"] = "Elite",

  -- Death.lua (R26.8)
  ["No corpse to go back to."] = "Keine Leiche, zu der du zurück könntest.",
  ["your corpse"] = "deiner Leiche",
  ["Your corpse"] = "Deine Leiche",
  ["Died here"] = "Hier gestorben",
  ["Died %s"] = "Gestorben %s",
  ["%d min ago"] = "vor %d Min.",
  ["%d h ago"] = "vor %d Std.",
  ["%d days ago"] = "vor %d Tagen",
  ["Click for the way back"] = "Klicken für den Weg zurück",
  ["Click for a route there"] = "Klicken für eine Route dorthin",
  ["the place of death"] = "dem Sterbeort",
  ["Deaths"] = "Sterbeorte",
  ["Where you died: your corpse, and the earlier deaths of this character."] = "Wo du gestorben bist: deine Leiche und die früheren Tode dieses Charakters.",
  ["Route back to the corpse after releasing"] = "Nach dem Freilassen des Geistes die Route zur Leiche planen",

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
