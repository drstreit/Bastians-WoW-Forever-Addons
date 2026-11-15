-- Bastian's Chat, the words a line is recognised by (plan-chat-v3.md §10): per client language the
-- offer and group words, the roles, the question words, the money words, the short forms of the
-- dungeons and the names of the game's public channels. Data matched against other players' lines,
-- never drawn. English and German since package V1, every client language of the suite since V9
-- (French, Spanish for both Spanish clients, Brazilian Portuguese, Russian, Korean, both Chinese).
-- Pure.
local _, ns = ...

local Words = {}
ns.Words = Words

-- Lowercase. A word ending in "*" matches every word that starts so ("verkauf*": verkaufe,
-- verkaufen). A phrase may hold spaces. Words are found at word boundaries (Words.Find).
Words.enUS = {
  wts = { "wts", "selling", "sell", "for sale" },
  wtb = { "wtb", "buying", "paying for" },
  -- a craft or a service on offer or asked for (V45): these count beside a link of an item, a
  -- spell or a recipe
  service = {
    "tips",
    "tip",
    "tipping",
    "free",
    "your mats",
    "ur mats",
    "my mats",
    "own mats",
    "have mats",
    "mats provided",
    "open trade",
    "can open",
    "can craft",
    "can make",
    "can enchant",
    "craft*",
    "fee",
  },
  -- a trade or a service by its name: these count beside an offer word, a "looking for" or an
  -- "anyone", without a link
  trades = {
    "enchanter*",
    "enchanting",
    "enchant",
    "enchants",
    "blacksmith*",
    "tailor*",
    "leatherwork*",
    "alchemist*",
    "engineer*",
    "lockpick*",
    "portal",
    "portals",
    "port",
    "ports",
    "summon",
    "summons",
  },
  anyone = { "any", "anyone", "anybody", "someone", "who can" },
  -- a locked box names the service by itself
  locks = { "lockbox*", "lock box*", "junkbox*" },
  lfg = { "lfg", "looking for group", "lf group" },
  lfm = { "lfm", "looking for more" },
  lf = { "lf", "looking for", "need", "needs" }, -- only with a role or a dungeon
  roles = {
    tank = { "tank", "tanks", "prot" },
    heal = { "heal", "heals", "healer", "healers", "healz" },
    dps = { "dps", "dd", "damage" },
  },
  ask = {
    where = { "where are you", "where r u", "where are u", "where you at", "wru", "where r you" },
    ilvl = { "ilvl", "item level", "itemlevel" },
    level = { "what level", "which level", "what lvl", "your level", "ur level" },
    recipe = {
      "do you know",
      "do u know",
      "can you make",
      "can u make",
      "can you craft",
      "can u craft",
      "recipe",
    },
    invite = { "inv", "invite me", "inv me", "can i join", "room for", "can i come" },
    price = { "how much", "price", "hm?" },
    thanks = { "thanks", "thank you", "thx", "ty", "tyvm", "thank u", "thanx" },
    gz = { "gz", "grats", "gratz", "congrats", "congratulations", "grats!" },
    hi = { "hi", "hello", "hey", "heya", "hiya", "greetings" },
  },
  money = {
    gold = { "g", "gold", "gs" },
    silver = { "s", "silver" },
    copper = { "c", "copper", "cu" },
  },
  each = { "each", "ea", "per", "apiece", "a piece", "per unit", "pu" },
  stack = { "per stack", "a stack", "stack", "the lot", "for all" },
  -- short forms and names of the dungeons, longest first; the value is the English name, which
  -- Data's dungeon records are found by (V9)
  dungeons = {
    { "deadmines", "The Deadmines" },
    { "wailing caverns", "Wailing Caverns" },
    { "shadowfang keep", "Shadowfang Keep" },
    { "blackfathom deeps", "Blackfathom Deeps" },
    { "ragefire chasm", "Ragefire Chasm" },
    { "stockade", "The Stockade" },
    { "stocks", "The Stockade" },
    { "gnomeregan", "Gnomeregan" },
    { "gnomer", "Gnomeregan" },
    { "razorfen kraul", "Razorfen Kraul" },
    { "razorfen downs", "Razorfen Downs" },
    { "scarlet monastery", "Scarlet Monastery" },
    { "uldaman", "Uldaman" },
    { "ulda", "Uldaman" },
    { "zul'farrak", "Zul'Farrak" },
    { "maraudon", "Maraudon" },
    { "mara", "Maraudon" },
    { "sunken temple", "The Temple of Atal'Hakkar" },
    { "blackrock depths", "Blackrock Depths" },
    { "lbrs", "Lower Blackrock Spire" },
    { "ubrs", "Upper Blackrock Spire" },
    { "stratholme", "Stratholme" },
    { "strat", "Stratholme" },
    { "scholomance", "Scholomance" },
    { "scholo", "Scholomance" },
    { "dire maul", "Dire Maul" },
    { "rfc", "Ragefire Chasm" },
    { "wc", "Wailing Caverns" },
    { "sfk", "Shadowfang Keep" },
    { "bfd", "Blackfathom Deeps" },
    { "rfk", "Razorfen Kraul" },
    { "rfd", "Razorfen Downs" },
    { "sm", "Scarlet Monastery" },
    { "zf", "Zul'Farrak" },
    { "st", "The Temple of Atal'Hakkar" },
    { "brd", "Blackrock Depths" },
    { "vc", "The Deadmines" },
    { "dm", "The Deadmines" },
  },
  -- the game's public channels by their name without the zone ("Trade - City" is "trade")
  channels = {
    trade = { "trade" },
    lfg = { "lookingforgroup" },
    general = { "general" },
    defense = { "localdefense" },
    services = { "services" },
  },
}

Words.deDE = {
  wts = { "verkaufe", "verkauf*", "vk", "biete" },
  wtb = { "kaufe", "suche*" }, -- "suche" with an item link is a purchase, with a role a group
  -- the lockboxes' German names are compounds ("Bronzeschließkassette"), which no word boundary
  -- finds: "öffnen" beside the link does
  service = {
    "tg",
    "trinkgeld",
    "gratis",
    "kostenlos",
    "umsonst",
    "eure mats",
    "deine mats",
    "eigene mats",
    "mats vorhanden",
    "handel auf",
    "öffnen",
    "aufmachen",
    "knacken",
    "herstell*",
  },
  trades = {
    "verzauberer*",
    "verzauberin",
    "verzauberung*",
    "schmied*",
    "schneider*",
    "lederer*",
    "alchemist*",
    "alchi",
    "ingenieur*",
    "ingi",
    "schlossknack*",
    "portal*",
    "port",
    "beschwörung*",
  },
  anyone = { "jemand", "irgendwer", "irgendjemand", "wer kann" },
  lfg = { "suche gruppe", "suche grp", "sucht gruppe", "suche eine gruppe" },
  lfm = { "suchen noch", "brauchen noch" },
  lf = { "suche*", "brauche*", "noch ein*" },
  roles = {
    tank = { "tank", "tanks" },
    heal = { "heiler", "heal*" },
    dps = { "schaden", "dd", "dds" },
  },
  ask = {
    where = { "wo bist du", "wo bist", "wo seid ihr", "wo steckst du" },
    ilvl = { "itemlevel", "gegenstandsstufe", "ilvl" },
    level = { "welches level", "welche stufe", "was für ein level", "dein level" },
    recipe = { "kannst du", "hast du das rezept", "rezept", "kennst du" },
    invite = { "inv", "einladen", "lad mich ein", "kann ich mit" },
    price = { "wie viel", "wieviel", "was kostet", "preis" },
    thanks = { "danke", "dankeschön", "danke schön", "vielen dank", "dankö" },
    gz = { "glückwunsch", "herzlichen glückwunsch", "gratuliere", "gw" },
    hi = { "hallo", "moin", "servus", "huhu", "grüß dich", "tach" },
  },
  money = {
    gold = { "g", "gold" },
    silver = { "s", "silber" },
    copper = { "k", "kupfer", "c" },
  },
  each = { "pro stück", "das stück", "je", "pro", "stück", "stk" },
  stack = { "pro stack", "der stack", "stack", "alles zusammen", "zusammen" },
  dungeons = {
    { "todesminen", "The Deadmines" },
    { "höhlen des wehklagens", "Wailing Caverns" },
    { "burg schattenfang", "Shadowfang Keep" },
    { "tiefschwarze grotte", "Blackfathom Deeps" },
    { "flammenschlund", "Ragefire Chasm" },
    { "verlies", "The Stockade" },
    { "kral der klingenhauer", "Razorfen Kraul" },
    { "hügel der klingenhauer", "Razorfen Downs" },
    { "scharlachrotes kloster", "Scarlet Monastery" },
    { "hdw", "Wailing Caverns" },
    { "bsf", "Shadowfang Keep" },
    { "tsg", "Blackfathom Deeps" },
    { "tm", "The Deadmines" },
    { "kloster", "Scarlet Monastery" },
  },
  channels = {
    trade = { "handel" },
    lfg = { "suchenachgruppe" },
    general = { "allgemein" },
    defense = { "lokaleverteidigung" },
    services = { "dienstleistungen" },
  },
}

-- French (frFR). Capitals of letters with an accent stay as typed (the game's Lua lowers ASCII
-- only), so a word that starts with one is listed in both forms.
Words.frFR = {
  wts = { "vends", "vend", "à vendre", "vds" },
  wtb = { "achète", "achete", "cherche*", "recherche*" },
  service = { "pourboire*", "gratuit*", "vos compos", "tes compos", "mes compos", "peut ouvrir", "fabriqu*" },
  trades = {
    "enchanteur*",
    "enchantement*",
    "forgeron*",
    "tailleur*",
    "alchimiste*",
    "ingénieur*",
    "crochetage",
    "portail*",
    "invocation*",
  },
  anyone = { "quelqu'un", "qui peut" },
  lfg = { "cherche groupe", "recherche groupe", "cherche un groupe", "cherche grp" },
  lfm = { "recherchons", "cherchons", "il nous manque" },
  lf = { "cherche*", "recherche*", "besoin*", "manque*" },
  roles = {
    tank = { "tank", "tanks" },
    heal = { "heal*", "soigneur*", "soin*" },
    dps = { "dps", "dd", "dégâts" },
  },
  ask = {
    where = { "tu es où", "t'es où", "t es où", "où es-tu", "où es tu", "ou es tu", "tu es ou" },
    ilvl = { "ilvl", "niveau d'objet", "niveau d'équipement" },
    level = { "quel niveau", "ton niveau", "quel lvl" },
    recipe = { "tu connais", "tu peux faire", "tu peux craft", "recette", "as-tu la recette" },
    invite = { "inv", "invite", "inviter", "je peux venir" },
    price = { "combien", "quel prix", "prix" },
    thanks = { "merci", "merci beaucoup", "mci" },
    gz = { "félicitations", "felicitations", "bravo" },
    hi = { "salut", "bonjour", "bonsoir", "coucou" },
  },
  money = {
    gold = { "po", "g", "or" },
    silver = { "pa", "s", "argent" },
    copper = { "pc", "c", "cuivre" },
  },
  each = { "la pièce", "pièce", "l'unité", "chacun", "chaque" },
  stack = { "le stack", "la pile", "pile", "stack", "le tout", "le lot" },
  dungeons = {
    { "mortemines", "The Deadmines" },
    { "cavernes des lamentations", "Wailing Caverns" },
    { "ombrecroc", "Shadowfang Keep" },
    { "brassenoire", "Blackfathom Deeps" },
    { "ragefeu", "Ragefire Chasm" },
    { "la prison", "The Stockade" },
    { "monastère", "Scarlet Monastery" },
    { "monastere", "Scarlet Monastery" },
    { "kraal de tranchebauge", "Razorfen Kraul" },
    { "souilles de tranchebauge", "Razorfen Downs" },
  },
  channels = {
    trade = { "commerce" },
    lfg = { "recherchedegroupe" },
    general = { "général", "general" },
    defense = { "défenselocale", "defenselocale" },
    services = { "services" },
  },
}

-- Spanish (esES, and esMX below).
Words.esES = {
  wts = { "vendo", "se vende", "vendiendo" },
  wtb = { "compro", "busco*" },
  service = { "propina*", "gratis", "tus mats", "tus materiales", "puede abrir" },
  trades = {
    "encantador*",
    "encantamiento*",
    "herrero*",
    "sastre*",
    "alquimista*",
    "ingeniero*",
    "portal*",
    "invocación",
  },
  anyone = { "alguien", "quién puede", "quien puede" },
  lfg = { "busco grupo", "buscando grupo", "busco grp" },
  lfm = { "buscamos", "nos falta*" },
  lf = { "busco*", "necesito*", "necesitamos", "falta*" },
  roles = {
    tank = { "tanque", "tank" },
    heal = { "sanador*", "curandero*", "heal*", "healer" },
    dps = { "dps", "daño" },
  },
  ask = {
    where = { "dónde estás", "donde estas", "dónde andas", "donde andas" },
    ilvl = { "ilvl", "nivel de objeto", "nivel de equipo" },
    level = { "qué nivel", "que nivel", "tu nivel", "qué lvl" },
    recipe = { "sabes hacer", "puedes hacer", "puedes craftear", "receta", "tienes la receta" },
    invite = { "inv", "invita", "invítame", "invitame", "puedo ir" },
    price = { "cuánto", "cuanto", "precio" },
    thanks = { "gracias", "muchas gracias", "grax" },
    gz = { "felicidades", "enhorabuena", "felicitaciones" },
    hi = { "hola", "buenas", "saludos" },
  },
  money = {
    gold = { "o", "g", "oro" },
    silver = { "p", "s", "plata" },
    copper = { "c", "cobre" },
  },
  each = { "cada uno", "cada una", "c/u", "la unidad", "por unidad" },
  stack = { "el stack", "stack", "pila", "todo junto", "el lote" },
  dungeons = {
    { "minas de la muerte", "The Deadmines" },
    { "cuevas de los lamentos", "Wailing Caverns" },
    { "colmillo oscuro", "Shadowfang Keep" },
    { "brazanegra", "Blackfathom Deeps" },
    { "sima ígnea", "Ragefire Chasm" },
    { "sima ignea", "Ragefire Chasm" },
    { "monasterio escarlata", "Scarlet Monastery" },
  },
  channels = {
    trade = { "comercio" },
    lfg = { "buscargrupo" },
    general = { "general" },
    defense = { "defensalocal" },
    services = { "servicios" },
  },
}
Words.esMX = Words.esES

-- Brazilian Portuguese (ptBR).
Words.ptBR = {
  wts = { "vendo", "vende-se", "vendendo" },
  wtb = { "compro", "procuro*" },
  service = { "gorjeta*", "grátis", "gratis", "seus mats", "seus materiais", "pode abrir" },
  trades = {
    "encantador*",
    "encantamento*",
    "ferreiro*",
    "alfaiate*",
    "alquimista*",
    "engenheiro*",
    "portal*",
    "evocação",
  },
  anyone = { "alguém", "alguem", "quem pode" },
  lfg = { "procuro grupo", "procurando grupo" },
  lfm = { "procuramos", "falta*" },
  lf = { "procuro*", "preciso*", "precisamos", "falta*" },
  roles = {
    tank = { "tanque", "tank" },
    heal = { "curador*", "healer", "heal*" },
    dps = { "dps", "dano" },
  },
  ask = {
    where = {
      "onde você está",
      "onde voce esta",
      "onde vc ta",
      "onde vc está",
      "cadê você",
      "cade voce",
    },
    ilvl = { "ilvl", "nível de item", "nivel de item" },
    level = { "qual nível", "qual nivel", "seu nível", "seu nivel" },
    recipe = { "você sabe fazer", "vc sabe fazer", "pode fazer", "receita" },
    invite = { "inv", "convida", "me convida", "posso ir" },
    price = { "quanto", "preço", "preco" },
    thanks = { "obrigado", "obrigada", "valeu", "vlw", "brigado" },
    gz = { "parabéns", "parabens" },
    hi = { "oi", "olá", "ola", "eae", "e ai" },
  },
  money = {
    gold = { "o", "g", "ouro" },
    silver = { "p", "s", "prata" },
    copper = { "c", "cobre" },
  },
  each = { "cada um", "cada", "a unidade", "por unidade" },
  stack = { "o stack", "stack", "pilha", "tudo junto" },
  dungeons = {
    { "minas mortas", "The Deadmines" },
    { "caverna ululante", "Wailing Caverns" },
  },
  channels = {
    trade = { "comércio", "comercio" },
    lfg = { "procurandogrupo" },
    general = { "geral" },
    defense = { "defesalocal" },
    services = { "serviços", "servicos" },
  },
}

-- Russian (ruRU). The game's Lua lowers ASCII only: Cyrillic stays as typed, so the words a line
-- starts with are listed with a capital too.
Words.ruRU = {
  wts = {
    "продам",
    "Продам",
    "продаю",
    "Продаю",
    "продается",
    "продаётся",
  },
  wtb = { "куплю", "Куплю", "покупаю", "Покупаю", "ищу*", "Ищу*" },
  lfg = { "ищу группу", "Ищу группу", "ищу пати", "Ищу пати" },
  lfm = { "ищем", "Ищем", "в группу", "В группу" },
  lf = {
    "ищу*",
    "Ищу*",
    "нужен",
    "Нужен",
    "нужна",
    "Нужна",
    "нужны",
    "Нужны",
  },
  roles = {
    tank = { "танк*", "Танк*" },
    heal = { "хил*", "Хил*", "лекар*", "Лекар*" },
    dps = { "дд", "ДД", "дпс", "рдд", "мдд" },
  },
  ask = {
    where = {
      "ты где",
      "Ты где",
      "где ты",
      "Где ты",
      "где находишься",
      "Где находишься",
    },
    ilvl = { "илвл", "ilvl", "уровень предметов", "гс" },
    level = {
      "какой уровень",
      "Какой уровень",
      "какой лвл",
      "Какой лвл",
      "твой уровень",
    },
    recipe = {
      "можешь сделать",
      "Можешь сделать",
      "умеешь делать",
      "есть рецепт",
      "Есть рецепт",
      "рецепт",
    },
    invite = {
      "инв",
      "Инв",
      "пригласи",
      "Пригласи",
      "кинь инвайт",
      "инвайт",
    },
    price = {
      "сколько",
      "Сколько",
      "почем",
      "почём",
      "Почем",
      "Почём",
      "цена",
      "Цена",
    },
    thanks = {
      "спасибо",
      "Спасибо",
      "спс",
      "Спс",
      "благодарю",
      "Благодарю",
    },
    gz = { "поздравляю", "Поздравляю", "грац", "Грац", "гц" },
    hi = {
      "привет",
      "Привет",
      "здравствуй",
      "Здравствуй",
      "хай",
      "Хай",
      "здарова",
      "Здарова",
    },
  },
  money = {
    gold = { "г", "з", "золото", "золота", "g" },
    silver = { "с", "серебро", "серебра", "s" },
    copper = { "м", "медь", "меди", "c" },
  },
  each = { "за штуку", "за шт", "шт", "каждый" },
  stack = { "за стак", "стак", "пачка", "всё вместе", "все вместе" },
  dungeons = {
    { "мертвые копи", "The Deadmines" },
    { "мёртвые копи", "The Deadmines" },
    { "Мертвые копи", "The Deadmines" },
    { "Мёртвые копи", "The Deadmines" },
    { "пещеры стенаний", "Wailing Caverns" },
    { "Пещеры стенаний", "Wailing Caverns" },
    { "темного клыка", "Shadowfang Keep" },
    { "тёмного клыка", "Shadowfang Keep" },
    { "Темного Клыка", "Shadowfang Keep" },
    { "огненная пропасть", "Ragefire Chasm" },
    { "Огненная пропасть", "Ragefire Chasm" },
    { "монастырь", "Scarlet Monastery" },
    { "Монастырь", "Scarlet Monastery" },
    { "мк", "The Deadmines" },
    { "МК", "The Deadmines" },
    { "ктк", "Shadowfang Keep" },
    { "КТК", "Shadowfang Keep" },
  },
  channels = {
    trade = { "торговля", "Торговля" },
    lfg = { "поискспутников", "ПоискСпутников" },
    general = { "общий", "Общий" },
    defense = { "оборона", "Оборона" },
  },
}

-- Korean (koKR): words carry their particles ("탱커분", "폐광가실"), so they are found without
-- boundaries (loose).
Words.koKR = {
  loose = true,
  wts = { "팝니다", "판매", "팔아요", "ㅍㅍ" },
  wtb = { "삽니다", "구매", "사요", "ㅅㅅ" },
  lfg = { "파티 구함", "파티구함", "파티 찾습니다", "파티찾아요" },
  lfm = { "구인", "모집" },
  lf = { "구함", "구합니다", "구해요", "찾습니다" },
  roles = {
    tank = { "탱커", "탱" },
    heal = { "힐러", "힐" },
    dps = { "딜러", "딜" },
  },
  ask = {
    where = { "어디세요", "어디야", "어디 있어", "어디에요", "어디예요" },
    ilvl = { "템렙", "아이템 레벨", "ilvl" },
    level = { "몇 레벨", "레벨 몇", "몇렙", "렙 몇" },
    recipe = { "만들 수 있", "제작 가능", "도안", "레시피" },
    invite = { "초대", "inv" },
    price = { "얼마", "가격" },
    thanks = { "감사", "고마워", "고맙", "ㄳ", "ㄱㅅ" },
    gz = { "축하", "ㅊㅋ" },
    hi = { "안녕", "하이", "ㅎㅇ" },
  },
  money = {
    gold = { "골", "골드", "g" },
    silver = { "실", "실버", "s" },
    copper = { "코", "코퍼", "c" },
  },
  each = { "개당", "1개당", "하나에" },
  stack = { "묶음", "세트", "일괄" },
  dungeons = {
    { "죽음의 폐광", "The Deadmines" },
    { "폐광", "The Deadmines" },
    { "통곡의 동굴", "Wailing Caverns" },
    { "통곡", "Wailing Caverns" },
    { "그림자송곳니", "Shadowfang Keep" },
    { "성난불길", "Ragefire Chasm" },
    { "검은심연", "Blackfathom Deeps" },
    { "지하감옥", "The Stockade" },
    { "수도원", "Scarlet Monastery" },
  },
  channels = {
    trade = { "거래" },
    lfg = { "파티찾기" },
    general = { "일반" },
    defense = { "지역방어" },
  },
}

-- Simplified Chinese (zhCN), written without spaces: found without boundaries (loose).
Words.zhCN = {
  loose = true,
  wts = { "出售", "卖" },
  wtb = { "收购", "求购", "收" },
  lfg = { "求组", "求带", "找队" },
  lfm = { "来人", "招人", "组人", "速来" },
  lf = { "缺", "求", "来" },
  roles = {
    tank = { "坦克", "坦" },
    heal = { "治疗", "奶" },
    dps = { "输出", "dps" },
  },
  ask = {
    where = { "你在哪", "在哪里", "在哪儿" },
    ilvl = { "装等", "装备等级", "ilvl" },
    level = { "几级", "多少级" },
    recipe = { "会做", "能做", "有配方", "配方", "图纸" },
    invite = { "组我", "邀请我", "拉我", "inv" },
    price = { "多少钱", "价格", "什么价" },
    thanks = { "谢谢", "多谢", "感谢" },
    gz = { "恭喜", "祝贺" },
    hi = { "你好", "您好", "嗨", "哈喽" },
  },
  money = {
    gold = { "金", "金币", "g" },
    silver = { "银", "银币", "s" },
    copper = { "铜", "铜币", "c" },
  },
  each = { "每个", "单价" },
  stack = { "一组", "整组", "打包" },
  dungeons = {
    { "死亡矿井", "The Deadmines" },
    { "死矿", "The Deadmines" },
    { "哀嚎洞穴", "Wailing Caverns" },
    { "影牙城堡", "Shadowfang Keep" },
    { "怒焰裂谷", "Ragefire Chasm" },
    { "黑暗深渊", "Blackfathom Deeps" },
    { "监狱", "The Stockade" },
    { "血色修道院", "Scarlet Monastery" },
    { "诺莫瑞根", "Gnomeregan" },
    { "剃刀沼泽", "Razorfen Kraul" },
    { "剃刀高地", "Razorfen Downs" },
    { "奥达曼", "Uldaman" },
    { "祖尔法拉克", "Zul'Farrak" },
    { "玛拉顿", "Maraudon" },
    { "黑石深渊", "Blackrock Depths" },
    { "斯坦索姆", "Stratholme" },
    { "通灵学院", "Scholomance" },
    { "厄运之槌", "Dire Maul" },
  },
  channels = {
    trade = { "交易" },
    lfg = { "寻求组队" },
    general = { "综合" },
    defense = { "本地防务" },
  },
}

-- Traditional Chinese (zhTW), loose as zhCN.
Words.zhTW = {
  loose = true,
  wts = { "出售", "賣" },
  wtb = { "收購", "求購", "收" },
  lfg = { "求組", "求帶", "找隊" },
  lfm = { "來人", "招人", "組人", "速來" },
  lf = { "缺", "求", "來" },
  roles = {
    tank = { "坦克", "坦" },
    heal = { "治療", "補" },
    dps = { "輸出", "dps" },
  },
  ask = {
    where = { "你在哪", "在哪裡", "在哪兒" },
    ilvl = { "裝等", "裝備等級", "ilvl" },
    level = { "幾級", "多少級" },
    recipe = { "會做", "能做", "有配方", "配方", "圖紙" },
    invite = { "組我", "邀請我", "拉我", "inv" },
    price = { "多少錢", "價格", "什麼價" },
    thanks = { "謝謝", "多謝", "感謝" },
    gz = { "恭喜", "祝賀" },
    hi = { "你好", "您好", "嗨", "哈囉" },
  },
  money = {
    gold = { "金", "g" },
    silver = { "銀", "s" },
    copper = { "銅", "c" },
  },
  each = { "每個", "單價" },
  stack = { "一組", "整組" },
  dungeons = {
    { "死亡礦坑", "The Deadmines" },
    { "死礦", "The Deadmines" },
    { "哀嚎洞穴", "Wailing Caverns" },
    { "影牙城堡", "Shadowfang Keep" },
    { "怒焰裂谷", "Ragefire Chasm" },
    { "黑暗深淵", "Blackfathom Deeps" },
    { "監獄", "The Stockade" },
    { "血色修道院", "Scarlet Monastery" },
  },
  channels = {
    trade = { "交易" },
    lfg = { "尋求組隊" },
    general = { "綜合" },
    defense = { "本地防務" },
  },
}

-- ---------------------------------------------------------------------------------------------
-- Finding words
-- ---------------------------------------------------------------------------------------------

-- Letters and digits of ASCII, and every byte of a UTF-8 letter (128 and above).
local function wordByte(b)
  return b ~= nil and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b >= 128)
end

-- the punctuation outside ASCII that parts words ("¿dónde", "«vends»", "你在哪？")
Words.PUNCT = {}
for _, p in ipairs({
  "¿",
  "¡",
  "«",
  "»",
  "“",
  "”",
  "„",
  "‘",
  "’",
  "‚",
  "…",
  "–",
  "—",
  "·",
  "，",
  "。",
  "？",
  "！",
  "：",
  "；",
  "、",
  "（",
  "）",
  "～",
}) do
  Words.PUNCT[p] = true
end

-- Is the character that ends at byte `i` (before a word) or starts at it (after one) a letter?
local function letterBefore(s, i)
  local b = s:byte(i)
  if not b or b < 128 then
    return wordByte(b)
  end
  local j = i
  while j > 1 and s:byte(j) >= 128 and s:byte(j) < 192 do
    j = j - 1
  end
  return not Words.PUNCT[s:sub(j, i)]
end

local function letterAfter(s, i)
  local b = s:byte(i)
  if not b or b < 128 then
    return wordByte(b)
  end
  local n = b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1
  return not Words.PUNCT[s:sub(i, i + n - 1)]
end

-- Where `word` stands in `plain` as a word: start and end, or nil. `loose` skips the boundaries
-- (for the languages written without spaces, V9).
function Words.Find(plain, word, loose)
  if type(plain) ~= "string" or type(word) ~= "string" or word == "" then
    return nil
  end
  local prefix = word:sub(-1) == "*"
  if prefix then
    word = word:sub(1, -2)
  end
  local init = 1
  while true do
    local s, e = plain:find(word, init, true)
    if not s then
      return nil
    end
    local before = s > 1 and letterBefore(plain, s - 1) or false
    local after = letterAfter(plain, e + 1)
    if loose or (not before and (prefix or not after)) then
      if prefix then
        while wordByte(plain:byte(e + 1)) do
          e = e + 1
        end
      end
      return s, e
    end
    init = s + 1
  end
end

-- The first word of `list` that `plain` holds, with its start and end.
function Words.Has(plain, list, loose)
  if type(list) ~= "table" then
    return nil
  end
  for _, word in ipairs(list) do
    local s, e = Words.Find(plain, word, loose)
    if s then
      return word, s, e
    end
  end
  return nil
end

local function union(a, b)
  local out, seen = {}, {}
  for _, list in ipairs({ a or {}, b or {} }) do
    for _, v in ipairs(list) do
      local key = type(v) == "table" and v[1] or v
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = v
      end
    end
  end
  return out
end

local cache = {}

-- The words of a client language merged with the English ones (Trade's jargon, "wts", "lfm",
-- "dps", is English on every realm), and the money words as a lookup. Built once per language.
function Words.For(locale)
  local key = locale or "enUS"
  if cache[key] then
    return cache[key]
  end
  local own, en = Words[key] or Words.enUS, Words.enUS
  local w = { locale = key, loose = own.loose, roles = {}, ask = {}, money = {}, channels = {}, units = {} }
  local lists = { "wts", "wtb", "lfg", "lfm", "lf", "each", "stack", "service", "trades", "anyone", "locks" }
  for _, list in ipairs(lists) do
    w[list] = own == en and en[list] or union(own[list], en[list])
  end
  for _, group in ipairs({ "roles", "ask", "money", "channels" }) do
    for id, list in pairs(en[group]) do
      w[group][id] = own == en and list or union(own[group] and own[group][id], list)
    end
  end
  w.dungeons = own == en and en.dungeons or union(own.dungeons, en.dungeons)
  for unit, list in pairs(w.money) do
    for _, word in ipairs(list) do
      w.units[word] = unit
    end
  end
  cache[key] = w
  return w
end

-- The kind of a public channel by its name ("Trade - City" and "Handel - Stadt" are "trade"),
-- or nil for a channel of the player's own.
function Words.ChannelKind(w, name)
  if type(name) ~= "string" then
    return nil
  end
  local base = (name:match("^(.-)%s+%-%s+.+$") or name):lower():gsub("%s+", "")
  for kind, list in pairs(w.channels) do
    for _, word in ipairs(list) do
      if base == word then
        return kind
      end
    end
  end
  return nil
end

-- The dungeon a line names: its English name, or nil.
function Words.Dungeon(w, plain)
  for _, pair in ipairs(w.dungeons) do
    if Words.Find(plain, pair[1], w.loose) then
      return pair[2]
    end
  end
  return nil
end

-- The roles a line names, in the order tank, heal, dps.
function Words.Roles(w, plain)
  local out = {}
  for _, role in ipairs({ "tank", "heal", "dps" }) do
    if Words.Has(plain, w.roles[role], w.loose) then
      out[#out + 1] = role
    end
  end
  return out
end
