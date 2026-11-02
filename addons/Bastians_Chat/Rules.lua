-- Bastian's Chat, the spam rules (chat.md "Spam", ADR 0042 §7: S1 lists, S2 trust, S3 repeats and
-- floods, S7 strength, S10 reasons). Pure: plain tables in and out, the time and the trust check
-- handed in, no WoW API.
local _, ns = ...
local Model = ns.Model

local Rules = {}
ns.Rules = Rules

Rules.FLOOD_SECS = 60
Rules.PRUNE_SECS = 30

-- S7: what each strength checks.
Rules.LEVELS = {
  off = {},
  light = { repeatSecs = 30 },
  normal = { repeatSecs = 120, flood = 6, builtin = true },
  strict = { repeatSecs = 300, flood = 4, builtin = true, urls = true },
}
Rules.LEVEL_ORDER = { "off", "light", "normal", "strict" }

-- The built-in spam words of normal and strict (gold sellers and their sites; plan-chat.md §3.3).
Rules.BUILTIN = "cheap gold, buy gold, gold for sale, sell gold, power leveling, powerleveling, "
  .. "discount code, coupon code, ~www%.%S*gold, ~gold%S*%.com, ~g[o0]ld%s*%$"

-- Only these kinds of line are checked: say and yell, channels, whispers from others.
local CHECKED = { say = true, channel = true, whisper = true }

-- settings = { level, block, allow, senders = { [name] = true }, action } -> the compiled rules.
function Rules.Compile(settings)
  settings = settings or {}
  local level = Rules.LEVELS[settings.level] and settings.level or "normal"
  local blockText = settings.block or ""
  if Rules.LEVELS[level].builtin then
    blockText = blockText .. "," .. Rules.BUILTIN
  end
  return {
    level = level,
    conf = Rules.LEVELS[level],
    block = Model.Words(blockText),
    allow = Model.Words(settings.allow),
    senders = settings.senders or {},
    action = (settings.action == "dim" or settings.action == "hide") and settings.action or "junk",
  }
end

-- The session's memory: repeats by sender and text, recent lines by sender, allowed senders.
function Rules.NewState()
  return { recent = {}, bySender = {}, allowed = {}, pruned = 0 }
end

local function prune(state, now, repeatSecs)
  if now - state.pruned < Rules.PRUNE_SECS then
    return
  end
  state.pruned = now
  for key, r in pairs(state.recent) do
    if now - r.at > (repeatSecs or 0) then
      state.recent[key] = nil
    end
  end
  for sender, times in pairs(state.bySender) do
    local kept = {}
    for _, t in ipairs(times) do
      if now - t <= Rules.FLOOD_SECS then
        kept[#kept + 1] = t
      end
    end
    state.bySender[sender] = #kept > 0 and kept or nil
  end
end

-- line = { cat, chatType, sender, plain (lower case), secret, own, public }; trusted(sender) ->
-- bool. Returns a verdict { action = "hide" | "junk" | "dim" | "fold", reason, count, foldKey } or
-- nil, and the fold key of a line shown for the first time (a later repeat folds into it).
-- The timeless part of the check: the blocked senders, the allowed and trusted, the word lists,
-- web addresses. Returns the verdict or nil, and whether the strength's counters (flood, repeats)
-- still apply to the line. Lines already shown are judged again with this alone (Chat.Refilter:
-- a count of floods or repeats makes no sense after the fact).
function Rules.Judge(state, rules, line, trusted)
  if line.secret or line.own or not CHECKED[line.cat] or type(line.sender) ~= "string" then
    return nil, false
  end
  if line.cat == "whisper" and line.chatType ~= "WHISPER" then
    return nil, false -- the player's own whispers and the game's away replies
  end
  if rules.senders[line.sender] then
    return { action = "hide", reason = "blocked sender" }, false
  end
  if state.allowed[line.sender] or (trusted and trusted(line.sender)) then
    return nil, false
  end
  local conf = rules.conf
  if not next(conf) then
    return nil, false -- off: only the blocked senders
  end
  local plain = line.plain or ""
  if Model.MatchWords(rules.allow, plain, line) then
    return nil, false
  end
  local hit = Model.MatchWords(rules.block, plain, line)
  if hit then
    return { action = rules.action, reason = "blocked word", word = hit.word }, false
  end
  if conf.urls and line.public and (plain:find("://", 1, true) or plain:find("www.", 1, true)) then
    return { action = "junk", reason = "web address" }, false
  end
  return nil, true
end

function Rules.Check(state, rules, line, now, trusted)
  local verdict, counted = Rules.Judge(state, rules, line, trusted)
  if verdict or not counted then
    return verdict
  end
  local conf = rules.conf
  prune(state, now, conf.repeatSecs)
  local plain = line.plain or ""
  if conf.flood then
    local times = state.bySender[line.sender] or {}
    times[#times + 1] = now
    state.bySender[line.sender] = times
    local n = 0
    for _, t in ipairs(times) do
      if now - t <= Rules.FLOOD_SECS then
        n = n + 1
      end
    end
    if n > conf.flood then
      return { action = "junk", reason = "flood", count = n }
    end
  end
  if conf.repeatSecs then
    local key = line.sender .. "\0" .. plain
    local r = state.recent[key]
    if r and now - r.at <= conf.repeatSecs then
      r.count = r.count + 1
      r.at = now
      return { action = "fold", reason = "repeated", count = r.count, foldKey = r.foldKey }
    end
    state.recent[key] = { at = now, count = 1, foldKey = key }
    return nil, key
  end
  return nil
end

-- "Not junk": the sender is allowed for the session.
function Rules.Allow(state, sender)
  if type(sender) == "string" then
    state.allowed[sender] = true
  end
end
