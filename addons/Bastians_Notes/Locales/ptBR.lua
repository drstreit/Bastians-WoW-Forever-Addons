-- Brazilian Portuguese strings of Bastians_Notes (ptBR). Keys are the English texts (Locale.lua); loaded after the German file.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
ns.L:Register("ptBR", {
  -- Notes.lua
  ["Notes"] = "Notas",
  ["Note"] = "Nota",
  ["My notes"] = "Minhas notas",
  ["a spot"] = "um local",
  ["Click to edit"] = "Clique para editar",
  ["Add note"] = "Adicionar nota",
  ["Add note here"] = "Adicionar nota aqui",
  ["Your notes on spots; notes on NPCs and quests show on their tooltips."] = "Suas notas sobre locais; as notas sobre NPCs e missões aparecem nas respectivas dicas.",
  ["Reminders: say a note when near it or when its NPC is targeted"] = "Lembretes: dizer uma nota ao chegar perto dela ou ao selecionar o NPC dela",
  ["No map position here (instance?)"] = "Sem posição no mapa aqui (instância?)",
  ["Note kept: %s"] = "Nota salva: %s",

  -- Editor.lua
  ["On %s"] = "Em: %s",
  ["Title"] = "Título",
  ["List"] = "Lista",
  ["Private"] = "Privada",
  ["Goes with its list"] = "Vai com a sua lista",
  ["Never"] = "Nunca",
  ["When near"] = "Ao chegar perto",
  ["When I target it"] = "Ao selecioná-la",
  ["Save"] = "Salvar",
  ["(right click: open it)"] = "(clique direito: abrir)",
  ["Cancel"] = "Cancelar",
  ["Remove"] = "Remover",
  ["A note needs a title."] = "Uma nota precisa de um título.",
  ["The note could not be kept (%s)."] = "Não foi possível salvar a nota (%s).",

  -- Lists.lua
  ["List name"] = "Nome da lista",
  ["New list"] = "Nova lista",
  ["Rename"] = "Renomear",
  ["Remove list"] = "Remover lista",
  ["on"] = "ligado",
  ["off"] = "desligado",
  ["Bookmarks"] = "Marcadores",

  -- Share.lua, sharing (N3)
  ["Share"] = "Compartilhar",
  ["Import"] = "Importar",
  ["Party"] = "Grupo",
  ["Raid"] = "Raide",
  ["Guild"] = "Guilda",
  ["Whisper"] = "Sussurro",
  ["Player name"] = "Nome do jogador",
  ["Or copy this text (Ctrl+C) for a forum, Discord or another account:"] = "Ou copie este texto (Ctrl+C) para um fórum, Discord ou outra conta:",
  ["Type the name of the player to whisper to."] = "Digite o nome do jogador para quem sussurrar.",
  ["Not sent (%s)."] = "Não enviado (%s).",
  ["Nothing to share: every note of this list is private."] = "Nada a compartilhar: todas as notas desta lista são privadas.",
  ["%s: %d notes, %d bookmarks go along."] = "%s: vão junto %d notas e %d marcadores.",
  ["%d private notes stay here."] = "%d notas privadas ficam aqui.",
  ["A list for you"] = "Uma lista para você",
  ["Accept"] = "Aceitar",
  ["Decline"] = "Recusar",
  ['%s shares the list "%s" with %d notes and %d bookmarks. Nothing is kept without your click.'] = '%s compartilha a lista "%s" com %d notas e %d marcadores. Nada é salvo sem o seu clique.',
  ["Import a list"] = "Importar uma lista",
  ["Paste the text (Ctrl+V), then Read."] = "Cole o texto (Ctrl+V) e depois clique em Ler.",
  ["Read"] = "Ler",
  ["This text holds no list (%s)."] = "Este texto não contém nenhuma lista (%s).",
  ["Sent: %s (%d notes, %d bookmarks)."] = "Enviado: %s (%d notas, %d marcadores).",
  ["%d private notes stayed here."] = "%d notas privadas ficaram aqui.",
  ["a pasted text"] = "um texto colado",
  ["Kept: %s (%d notes, %d bookmarks)."] = "Salvo: %s (%d notas, %d marcadores).",

  -- location sharing (R26.9, N4)
  ["You are not in a group."] = "Você não está em um grupo.",
  ["Sent to your group: %s"] = "Enviado ao seu grupo: %s",
  ["[%s] %s: %s (on your map)"] = "[%s] %s: %s (no seu mapa)",
  ["%s is here"] = "%s está aqui",
  ["From %s, %d min ago"] = "De %s, há %d min",
  ["Click for a route there"] = "Clique para uma rota até lá",
  ["From others"] = "De outros",
  ["Places your group, your guild or a friend sent you, for half an hour."] = "Locais que seu grupo, sua guilda ou um amigo enviou a você, por meia hora.",
  ["Sent to your guild: %s"] = "Enviado à sua guilda: %s",
  ["Sent to %s: %s"] = "Enviado a %s: %s",
  ["Places your group sent you, for half an hour."] = "Locais que seu grupo enviou a você, por meia hora.",
  ["Send this spot to my group"] = "Enviar este local ao meu grupo",
  ["Send to my group"] = "Enviar ao meu grupo",
  ["No place to send."] = "Nenhum local para enviar.",
  ["Bookmark: a click shows it on the map, a right click renames it"] = "Marcador: um clique o mostra no mapa, um clique direito o renomeia",

  -- the broker displays' feed (ADR 0043, 31.10.2026)
  ["%d notes"] = "%d notas",
  ["%d notes, %d reminders"] = "%d notas, %d lembretes",
  ["Click: the lists. Right click: a note here."] = "Clique: as listas. Clique direito: uma nota aqui.",
  ["Near here:"] = "Perto daqui:",
  ["No notes near here."] = "Não há notas perto daqui.",
  ["and %d more"] = "e mais %d",
  -- Notes.lua: All Notes (06.11.2026)
  ["On"] = "Sobre",
  -- Notes.lua: All Notes, empty (06.11.2026)
  ["No notes yet. Add note on a page writes the first."] = "Ainda não há notas. Adicionar nota em uma página escreve a primeira.",
})
