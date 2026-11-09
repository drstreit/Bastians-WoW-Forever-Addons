-- Brazilian Portuguese strings of Bastians_Route (ptBR). Keys are the English texts (Locale.lua); loaded after the German file.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
ns.L:Register("ptBR", {
  -- plan-second-wave.md S6 (01.11.2026)
  ["Route home"] = "Rota para casa",
  -- Arrow.lua
  ["Next step"] = "Próximo passo",
  ["position unknown"] = "posição desconhecida",
  ["another continent"] = "outro continente",

  -- Route.lua, Window.lua: home and the teleports (R26.7)
  ["Home"] = "Casa",
  ["The way to your inn, with the hearthstone and every teleport you have ready."] = "O caminho até a sua estalagem, com a Pedra de Regresso e todos os teletransportes que você tiver prontos.",
  ["No teleport table in the data."] = "Não há tabela de teletransportes nos dados.",
  ["unknown"] = "desconhecido",
  ["not yours"] = "não é seu",
  ["not castable now"] = "não pode ser lançado agora",
  ["cooldown unknown"] = "tempo de recarga desconhecido",
  ["landing learned"] = "ponto de chegada aprendido",
  ["Teleport"] = "Teletransporte",

  -- Explore (R26.11)
  ["Explore"] = "Explorar",
  ["what is worth doing nearby"] = "o que vale a pena fazer por perto",
  ["quest"] = "missão",
  ["farm spot"] = "local de farm",
  ["sale at the auction house"] = "venda na Casa de Leilões",
  ["craft"] = "fabricação",
  ["%s away"] = "a %s",
  ["XP/h"] = "XP/h",
  ["%d without price"] = "%d sem preço",
  ["Explore needs Bastian's Data."] = "Explorar requer o Bastian's Data.",
  ["Timing the ways from here..."] = "Calculando os caminhos a partir daqui...",
  ["%d things to do within %d min"] = "%d coisas para fazer em até %d min",
  ["%d ways still being timed"] = "%d caminhos ainda estão sendo calculados",
  ["%d min"] = "%d min",
  ["XP per hour"] = "XP por hora",
  ["Gold per hour"] = "Ouro por hora",
  ["Way"] = "Caminho",
  -- the session plan (W10 step 3)

  -- departures (R26.6)
  ["Learned when %s leaves; shared with your group and guild."] = "Aprendido quando %s parte; compartilhado com seu grupo e sua guilda.",
  ["No boat or zeppelin with departures in the data."] = "Não há barcos nem zepelins com partidas nos dados.",
  ["leaves in %s"] = "parte em %s",

  -- a member of the group (R26.9)
  ["No member of your group called %s."] = "Nenhum membro do seu grupo se chama %s.",
  ["%s has no map position for you (another zone or an instance)."] = "%s não tem posição no mapa para você (outra zona ou uma instância).",

  -- Several stops (R26.4)
  ["Several stops need the route network of this continent."] = "Várias paradas exigem a rede de rotas deste continente.",
  ["Tour"] = "Percurso",
  ["No route through the stops (%s)."] = "Não há rota pelas paradas (%s).",
  ["no way"] = "sem caminho",
  ["%d stops left out: another continent, or no way there."] = "%d paradas deixadas de fora: outro continente ou sem caminho até lá.",
  ["%s: %d stops, %s"] = "%s: %d paradas, %s",

  -- Route options (R26.5)
  ["Fastest"] = "Mais rápida",
  ["Safest"] = "Mais segura",
  ["No flights"] = "Sem voos",
  ["Route by default"] = "Rota padrão",
  ["Switch to this kind of route; it stays the default."] = "Mudar para este tipo de rota; ele continua sendo o padrão.",
  ["Careful: level %d creatures"] = "Cuidado: criaturas de nível %d",
  -- the route's verdict (catalog review A4.3, 07.11.2026)
  ["Safe trip"] = "Viagem segura",
  ["Watch out"] = "Cuidado",
  ["Risky trip"] = "Viagem arriscada",
  ["elite"] = "elite",

  -- Death.lua (R26.8)
  ["No corpse to go back to."] = "Não há corpo para onde voltar.",
  ["your corpse"] = "seu corpo",
  ["Your corpse"] = "Seu corpo",
  ["Died here"] = "Morreu aqui",
  ["Died %s"] = "Morreu %s",
  ["%d min ago"] = "há %d min",
  ["%d h ago"] = "há %d h",
  ["%d days ago"] = "há %d dias",
  ["Click for the way back"] = "Clique para o caminho de volta",
  ["Click for a route there"] = "Clique para uma rota até lá",
  ["the place of death"] = "o local da morte",
  ["Deaths"] = "Mortes",
  ["Where you died: your corpse, and the earlier deaths of this character."] = "Onde você morreu: seu corpo e as mortes anteriores deste personagem.",
  ["Route back to the corpse after releasing"] = "Traçar a rota de volta ao corpo após liberar o espírito",

  -- Route.lua: messages
  ["Hearth: inn unknown. Type /broute hearth while standing at your inn."] = "Regresso: estalagem desconhecida. Digite /broute hearth enquanto estiver na sua estalagem.",
  ["Hearth: you are bound to %s now; type /broute hearth there."] = "Regresso: você agora está vinculado a %s; digite /broute hearth lá.",
  ["Hearth: no Hearthstone in your bags."] = "Regresso: não há Pedra de Regresso nas suas bolsas.",
  ["Hearth: ready in %s."] = "Regresso: pronta em %s.",
  ["your inn"] = "sua estalagem",
  ["No map position here (instance?)"] = "Sem posição no mapa aqui (instância?)",
  ["No route to %s"] = "Não há rota para %s",
  ["You are already there: %s"] = "Você já está lá: %s",
  ["Route to %s: %s, %d steps"] = "Rota para %s: %s, %d passos",
  ["the marked spot"] = "o ponto marcado",
  ["Could not re-route to %s from here; keeping the route."] = "Não foi possível recalcular a rota para %s a partir daqui; mantendo a rota.",
  ["You have arrived: %s"] = "Você chegou: %s",
  ["Hearth set: %s"] = "Regresso definido: %s",
  ["here"] = "aqui",
  ["Hearth: %s, %s"] = "Regresso: %s, %s",
  ["set"] = "definido",
  ["ready"] = "pronta",
  ["ready in %s"] = "pronta em %s",
  ["Hearth: inn unknown (/broute hearth at your inn)"] = "Regresso: estalagem desconhecida (/broute hearth na sua estalagem)",
  ["%d flight masters learned, %d flight times measured"] = "%d mestres de voo aprendidos, %d tempos de voo medidos",

  -- Route.lua: settings and actions
  ["Route"] = "Rota",
  ["Flight paths to use"] = "Rotas de voo a usar",
  ["Known to this character"] = "Conhecidas por este personagem",
  ["Known to any of my characters"] = "Conhecidas por qualquer um dos meus personagens",
  ["All flight masters"] = "Todos os mestres de voo",
  ["Open the step list when a route starts"] = "Abrir a lista de passos quando uma rota começar",
  ["Show an arrow to the next step while a route is active"] = "Mostrar uma seta para o próximo passo enquanto houver uma rota ativa",
  -- Flight.lua: the flight bar (catalog review A4.1, 07.11.2026)
  ["Show a flight bar with the time left while flying"] = "Mostrar uma barra de voo com o tempo restante enquanto voa",
  ["%s to %s"] = "%s para %s",
  ["%s left"] = "%s restante",
  ["Route here"] = "Rota até aqui",
  ["Route to"] = "Rota para",
  ["Open Bastian's Route"] = "Abrir Bastian's Route",

  -- Window.lua
  ["wait up to %s"] = "aguardar até %s",
  ["Time"] = "Tempo",
  ["Distance"] = "Distância",
  ["yd"] = "jd",
  ["Estimate: a straight line or an unmeasured ride."] = "Estimativa: uma linha reta ou um trajeto não medido.",
  ["Legs marked approx are straight lines or unmeasured rides; the time is an estimate."] = "Os trechos marcados como aprox. são linhas retas ou trajetos não medidos; o tempo é uma estimativa.",
  ["The map draws them dashed: they may cross water until the route graph knows the terrain."] = "O mapa os desenha tracejados: eles podem cruzar a água até que o grafo de rotas conheça o terreno.",
  ["No route. Right click anything with a place and choose Route to."] = "Sem rota. Clique com o botão direito em qualquer coisa com um local e escolha Rota para.",
  ["the target"] = "o destino",
  ["To %s: %s, %d steps"] = "Para %s: %s, %d passos",
  ["Clear"] = "Limpar",
  ["Clear the route."] = "Limpar a rota.",
  ["Replan"] = "Recalcular",
  ["Plan the route again from where you stand."] = "Planejar a rota novamente a partir de onde você está.",
  ["Click a step to see its end on the map."] = "Clique em um passo para ver o fim dele no mapa.",

  -- Graph.lua: the words of a step ("Fly to X", "Go 380 yd SE to X (approx)")
  ["Go"] = "Ir",
  ["Fly"] = "Voar",
  ["Take the boat"] = "Pegue o barco",
  ["Take the zeppelin"] = "Pegue o zepelim",
  ["Take the tram"] = "Pegue o bondinho",
  ["Take the portal"] = "Entre no portal",
  ["Hearth"] = "Pedra de Regresso",
  ["to"] = "para",
  ["approx"] = "aprox.",
  -- the broker displays' feed (ADR 0043, 31.10.2026)
  ["%s, %s"] = "%s, %s",
  ["Click: the steps. Right click: clear the route."] = "Clique: os passos. Botão direito: limpar a rota.",
  ["and %d more"] = "e mais %d",

  -- Welcome, Suite page, Help page, app pages, Words (01.11.2026)
  ["Next: %s"] = "Próximo: %s",
  -- the /way command (ADR 0062, 08.11.2026)
  ["/way: %s"] = "/way: %s",
  ["New route"] = "Nova rota",
  ["Add to route"] = "Adicionar à rota",
  ["Waypoints"] = "Pontos de rota",
  ["What /way does while a route runs: start a new route, or add the place to the route."] = "O que /way faz enquanto há uma rota: começar uma rota nova ou adicionar o local à rota.",
  ["Which addon answers /way: Bastian's Route, or the one that had it first."] = "Qual addon responde a /way: Bastian's Route ou o que o tinha primeiro.",
  ["No zone called %s."] = "Nenhuma zona chamada %s.",
  ["Several zones match %s: %s"] = "Várias zonas correspondem a %s: %s",
})
