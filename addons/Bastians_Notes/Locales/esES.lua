-- Spanish strings of Bastians_Notes (esES). Keys are the English texts (Locale.lua); loaded after the German file.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local strings = {
  -- Notes.lua
  ["Notes"] = "Notas",
  ["Note"] = "Nota",
  ["My notes"] = "Mis notas",
  ["a spot"] = "un lugar",
  ["Click to edit"] = "Haz clic para editar",
  ["Add note"] = "Añadir nota",
  ["Add note here"] = "Añadir nota aquí",
  ["Your notes on spots; notes on NPCs and quests show on their tooltips."] = "Tus notas sobre lugares; las notas sobre PNJ y misiones aparecen en sus descripciones emergentes.",
  ["Reminders: say a note when near it or when its NPC is targeted"] = "Recordatorios: decir una nota cuando estás cerca o cuando se selecciona su PNJ",
  ["No map position here (instance?)"] = "Sin posición de mapa aquí (¿instancia?)",
  ["Note kept: %s"] = "Nota guardada: %s",

  -- Editor.lua
  ["On %s"] = "En: %s",
  ["Title"] = "Título",
  ["List"] = "Lista",
  ["Private"] = "Privado",
  ["Goes with its list"] = "Va con su lista",
  ["Never"] = "Nunca",
  ["When near"] = "Al estar cerca",
  ["When I target it"] = "Al seleccionarlo",
  ["Save"] = "Guardar",
  ["(right click: open it)"] = "(clic derecho: abrir)",
  ["Cancel"] = "Cancelar",
  ["Remove"] = "Quitar",
  ["A note needs a title."] = "Una nota necesita un título.",
  ["The note could not be kept (%s)."] = "No se pudo guardar la nota (%s).",

  -- Lists.lua
  ["List name"] = "Nombre de la lista",
  ["New list"] = "Nueva lista",
  ["Rename"] = "Renombrar",
  ["Remove list"] = "Eliminar la lista",
  ["on"] = "activado",
  ["off"] = "desactivado",
  ["Bookmarks"] = "Marcadores",

  -- Share.lua, sharing (N3)
  ["Share"] = "Compartir",
  ["Import"] = "Importar",
  ["Party"] = "Grupo",
  ["Raid"] = "Banda",
  ["Guild"] = "Hermandad",
  ["Whisper"] = "Susurrar",
  ["Player name"] = "Nombre del jugador",
  ["Or copy this text (Ctrl+C) for a forum, Discord or another account:"] = "O copia este texto (Ctrl+C) para un foro, Discord u otra cuenta:",
  ["Type the name of the player to whisper to."] = "Escribe el nombre del jugador al que susurrar.",
  ["Not sent (%s)."] = "No enviado (%s).",
  ["Nothing to share: every note of this list is private."] = "Nada que compartir: todas las notas de esta lista son privadas.",
  ["%s: %d notes, %d bookmarks go along."] = "%s: se incluyen %d notas y %d marcadores.",
  ["%d private notes stay here."] = "%d notas privadas se quedan aquí.",
  ["A list for you"] = "Una lista para ti",
  ["Accept"] = "Aceptar",
  ["Decline"] = "Rechazar",
  ['%s shares the list "%s" with %d notes and %d bookmarks. Nothing is kept without your click.'] = '%s comparte la lista "%s" con %d notas y %d marcadores. No se guarda nada sin tu clic.',
  ["Import a list"] = "Importar una lista",
  ["Paste the text (Ctrl+V), then Read."] = "Pega el texto (Ctrl+V) y pulsa Leer.",
  ["Read"] = "Leer",
  ["This text holds no list (%s)."] = "Este texto no contiene ninguna lista (%s).",
  ["Sent: %s (%d notes, %d bookmarks)."] = "Enviado: %s (%d notas, %d marcadores).",
  ["%d private notes stayed here."] = "%d notas privadas se quedaron aquí.",
  ["a pasted text"] = "un texto pegado",
  ["Kept: %s (%d notes, %d bookmarks)."] = "Guardado: %s (%d notas, %d marcadores).",

  -- location sharing (R26.9, N4)
  ["You are not in a group."] = "No estás en un grupo.",
  ["Sent to your group: %s"] = "Enviado a tu grupo: %s",
  ["[%s] %s: %s (on your map)"] = "[%s] %s: %s (en tu mapa)",
  ["%s is here"] = "%s está aquí",
  ["From %s, %d min ago"] = "De %s, hace %d min",
  ["Click for a route there"] = "Haz clic para una ruta hasta allí",
  ["From others"] = "De otros",
  ["Places your group, your guild or a friend sent you, for half an hour."] = "Lugares que te enviaron tu grupo, tu hermandad o un amigo, durante media hora.",
  ["Sent to your guild: %s"] = "Enviado a tu hermandad: %s",
  ["Sent to %s: %s"] = "Enviado a %s: %s",
  ["Places your group sent you, for half an hour."] = "Lugares que te envió tu grupo, durante media hora.",
  ["Send this spot to my group"] = "Enviar este lugar a mi grupo",
  ["Send to my group"] = "Enviar a mi grupo",
  ["No place to send."] = "Ningún lugar que enviar.",
  ["Bookmark: a click shows it on the map, a right click renames it"] = "Marcador: un clic lo muestra en el mapa, un clic derecho lo renombra",
  -- the broker displays' feed (ADR 0043, 31.10.2026)
  ["%d notes"] = "%d notas",
  ["%d notes, %d reminders"] = "%d notas, %d recordatorios",
  ["Click: the lists. Right click: a note here."] = "Clic: las listas. Clic derecho: una nota aquí.",
  ["Near here:"] = "Cerca de aquí:",
  ["No notes near here."] = "No hay notas cerca de aquí.",
  ["and %d more"] = "y %d más",
  -- Notes.lua: All Notes (06.11.2026)
  ["On"] = "Sobre",
  -- Notes.lua: All Notes, empty (06.11.2026)
  ["No notes yet. Add note on a page writes the first."] = "Aún no hay notas. Añadir nota en una página escribe la primera.",
}
ns.L:Register("esES", strings)
ns.L:Register("esMX", strings)
