-- French strings of Bastians_Route (frFR). Keys are the English texts (Locale.lua); loaded after the German file.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
ns.L:Register("frFR", {
  -- plan-second-wave.md S6 (01.11.2026)
  ["Route home"] = "Route vers le foyer",
  -- Arrow.lua
  ["Next step"] = "Étape suivante",
  ["position unknown"] = "position inconnue",
  ["another continent"] = "autre continent",

  -- Route.lua, Window.lua: home and the teleports (R26.7)
  ["Home"] = "Foyer",
  ["The way to your inn, with the hearthstone and every teleport you have ready."] = "Le chemin vers votre auberge, avec la pierre de foyer et chaque téléportation que vous avez de prête.",
  ["No teleport table in the data."] = "Aucune table de téléportation dans les données.",
  ["unknown"] = "inconnu",
  ["not yours"] = "pas à vous",
  ["not castable now"] = "impossible à lancer maintenant",
  ["cooldown unknown"] = "temps de recharge inconnu",
  ["landing learned"] = "point d'arrivée appris",
  ["Teleport"] = "Téléportation",

  -- Explore (R26.11)
  ["Explore"] = "Explorer",
  ["what is worth doing nearby"] = "ce qui vaut la peine à proximité",
  ["quest"] = "quête",
  ["farm spot"] = "lieu de farm",
  ["sale at the auction house"] = "vente à l'hôtel des ventes",
  ["craft"] = "fabrication",
  ["%s away"] = "à %s",
  ["XP/h"] = "XP/h",
  ["%d without price"] = "%d sans prix",
  ["Explore needs Bastian's Data."] = "Explorer nécessite Bastian's Data.",
  ["Timing the ways from here..."] = "Calcul des trajets depuis ici...",
  ["%d things to do within %d min"] = "%d choses à faire en %d min maximum",
  ["%d ways still being timed"] = "%d trajets encore en cours de calcul",
  ["%d min"] = "%d min",
  ["XP per hour"] = "XP par heure",
  ["Gold per hour"] = "Or par heure",
  ["Way"] = "Trajet",

  -- departures (R26.6)
  ["Learned when %s leaves; shared with your group and guild."] = "Appris quand %s part ; partagé avec votre groupe et votre guilde.",
  ["No boat or zeppelin with departures in the data."] = "Aucun bateau ni zeppelin avec des départs dans les données.",
  ["leaves in %s"] = "part dans %s",

  -- a member of the group (R26.9)
  ["No member of your group called %s."] = "Aucun membre de votre groupe ne s'appelle %s.",
  ["%s has no map position for you (another zone or an instance)."] = "%s n'a pas de position sur la carte pour vous (autre zone ou instance).",

  -- Several stops (R26.4)
  ["Several stops need the route network of this continent."] = "Plusieurs étapes nécessitent le réseau d'itinéraires de ce continent.",
  ["Tour"] = "Tournée",
  ["No route through the stops (%s)."] = "Aucun itinéraire passant par les étapes (%s).",
  ["no way"] = "aucun chemin",
  ["%d stops left out: another continent, or no way there."] = "%d étapes exclues : autre continent ou aucun chemin pour y aller.",
  ["%s: %d stops, %s"] = "%s : %d étapes, %s",

  -- Route options (R26.5)
  ["Fastest"] = "Le plus rapide",
  ["Safest"] = "Le plus sûr",
  ["No flights"] = "Sans vols",
  ["Route by default"] = "Itinéraire par défaut",
  ["Switch to this kind of route; it stays the default."] = "Passer à ce type d'itinéraire ; il reste celui par défaut.",
  ["Careful: level %d creatures"] = "Attention : créatures de niveau %d",
  ["elite"] = "élite",

  -- Death.lua (R26.8)
  ["No corpse to go back to."] = "Aucun cadavre où retourner.",
  ["your corpse"] = "votre cadavre",
  ["Your corpse"] = "Votre cadavre",
  ["Died here"] = "Mort ici",
  ["Died %s"] = "Mort %s",
  ["%d min ago"] = "il y a %d min",
  ["%d h ago"] = "il y a %d h",
  ["%d days ago"] = "il y a %d jours",
  ["Click for the way back"] = "Cliquez pour le chemin du retour",
  ["Click for a route there"] = "Cliquez pour un itinéraire jusque là",
  ["the place of death"] = "le lieu du décès",
  ["Deaths"] = "Décès",
  ["Where you died: your corpse, and the earlier deaths of this character."] = "Où vous êtes mort : votre cadavre et les décès précédents de ce personnage.",
  ["Route back to the corpse after releasing"] = "Tracer l'itinéraire vers le cadavre après avoir libéré l'esprit",

  -- Route.lua: messages
  ["Hearth: inn unknown. Type /broute hearth while standing at your inn."] = "Foyer : auberge inconnue. Tapez /broute hearth en vous tenant dans votre auberge.",
  ["Hearth: you are bound to %s now; type /broute hearth there."] = "Foyer : vous êtes maintenant lié à %s ; tapez /broute hearth là-bas.",
  ["Hearth: no Hearthstone in your bags."] = "Foyer : aucune pierre de foyer dans vos sacs.",
  ["Hearth: ready in %s."] = "Foyer : prête dans %s.",
  ["your inn"] = "votre auberge",
  ["No map position here (instance?)"] = "Aucune position sur la carte ici (instance ?)",
  ["No route to %s"] = "Aucun itinéraire vers %s",
  ["You are already there: %s"] = "Vous y êtes déjà : %s",
  ["Route to %s: %s, %d steps"] = "Itinéraire vers %s : %s, %d étapes",
  ["the marked spot"] = "le point marqué",
  ["Could not re-route to %s from here; keeping the route."] = "Impossible de recalculer l'itinéraire vers %s depuis ici ; l'itinéraire est conservé.",
  ["You have arrived: %s"] = "Vous êtes arrivé : %s",
  ["Hearth set: %s"] = "Foyer défini : %s",
  ["here"] = "ici",
  ["Hearth: %s, %s"] = "Foyer : %s, %s",
  ["set"] = "défini",
  ["ready"] = "prête",
  ["ready in %s"] = "prête dans %s",
  ["Hearth: inn unknown (/broute hearth at your inn)"] = "Foyer : auberge inconnue (/broute hearth dans votre auberge)",
  ["%d flight masters learned, %d flight times measured"] = "%d maîtres de vol appris, %d durées de vol mesurées",

  -- Route.lua: settings and actions
  ["Route"] = "Itinéraire",
  ["Flight paths to use"] = "Trajets aériens à utiliser",
  ["Known to this character"] = "Connus de ce personnage",
  ["Known to any of my characters"] = "Connus de l'un de mes personnages",
  ["All flight masters"] = "Tous les maîtres de vol",
  ["Open the step list when a route starts"] = "Ouvrir la liste des étapes au début d'un itinéraire",
  ["Show an arrow to the next step while a route is active"] = "Afficher une flèche vers l'étape suivante tant qu'un itinéraire est actif",
  ["Route here"] = "Itinéraire jusqu'ici",
  ["Route to"] = "Itinéraire vers",
  ["Open Bastian's Route"] = "Ouvrir Bastian's Route",

  -- Window.lua
  ["wait up to %s"] = "attendre jusqu'à %s",
  ["Time"] = "Durée",
  ["Distance"] = "Distance",
  ["yd"] = "m",
  ["Estimate: a straight line or an unmeasured ride."] = "Estimation : une ligne droite ou un trajet non mesuré.",
  ["Legs marked approx are straight lines or unmeasured rides; the time is an estimate."] = 'Les tronçons marqués "env." sont des lignes droites ou des trajets non mesurés ; la durée est une estimation.',
  ["The map draws them dashed: they may cross water until the route graph knows the terrain."] = "La carte les trace en pointillés : ils peuvent traverser l'eau tant que le graphe d'itinéraires ne connaît pas le terrain.",
  ["No route. Right click anything with a place and choose Route to."] = "Aucun itinéraire. Faites un clic droit sur tout ce qui a un lieu et choisissez Itinéraire vers.",
  ["the target"] = "la cible",
  ["To %s: %s, %d steps"] = "Vers %s : %s, %d étapes",
  ["Clear"] = "Effacer",
  ["Clear the route."] = "Effacer l'itinéraire.",
  ["Replan"] = "Recalculer",
  ["Plan the route again from where you stand."] = "Recalculer l'itinéraire depuis l'endroit où vous vous trouvez.",
  ["Click a step to see its end on the map."] = "Cliquez sur une étape pour voir son extrémité sur la carte.",

  -- Graph.lua: the words of a step ("Fly to X", "Go 380 yd SE to X (approx)")
  ["Go"] = "Aller",
  ["Fly"] = "Voler",
  ["Take the boat"] = "Prendre le bateau",
  ["Take the zeppelin"] = "Prendre le zeppelin",
  ["Take the tram"] = "Prendre le métro",
  ["Take the portal"] = "Prendre le portail",
  ["Hearth"] = "Pierre de foyer",
  ["to"] = "vers",
  ["approx"] = "env.",
  -- the broker displays' feed (ADR 0043, 31.10.2026)
  ["%s, %s"] = "%s, %s",
  ["Click: the steps. Right click: clear the route."] = "Clic : les étapes. Clic droit : effacer l'itinéraire.",
  ["and %d more"] = "et %d de plus",

  -- Welcome, Suite page, Help page, app pages, Words (01.11.2026)
  ["Next: %s"] = "Suivant : %s",
})
