-- The one search syntax of the suite (ADR 0045): a box's text compiled into a query that matches
-- records. Pure: no WoW API. Unknown field values are neither true nor false (CLAUDE.md §4.2).
local _, ns = ...
local B = ns.B

local Query = {}
B.Query = Query

local find, lower, sub, gsub = string.find, string.lower, string.sub, string.gsub

-- The errors a query can carry (English keys, the box translates them).
Query.ERRORS = {
  quote = "A quote is not closed.",
  bracket = "A bracket is not closed.",
  stray = "A closing bracket has no opening one.",
  pattern = "The pattern is broken; it is read as plain text.",
}

-- The syntax as lines for a box's tooltip (English keys, the box translates them).
Query.HELP = {
  'wolf den: every word   "den mother": the phrase',
  "wolf OR boar: either   -rabid: not   ( ): groups",
  "heal*: any letters   /^wt[bs]/: a Lua pattern",
}

local MAGIC = "([%^%$%(%)%%%.%[%]%*%+%-%?])"

local function trim(s)
  return (gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- "5g", "1g50s", "30c", "2.5g" -> copper; a bare number counts as gold. nil when it is no money.
function Query.ParseMoney(text)
  text = lower(trim(tostring(text or "")))
  if text == "" then
    return nil
  end
  local bare = tonumber(text)
  if bare then
    return math.floor(bare * 10000 + 0.5)
  end
  local total, rest = 0, gsub(text, "%s+", "")
  local any = false
  for amount, coin in string.gmatch(rest, "([%d%.]+)([gsc])") do
    local n = tonumber(amount)
    if not n then
      return nil
    end
    total = total + n * (coin == "g" and 10000 or coin == "s" and 100 or 1)
    any = true
  end
  if not any or gsub(rest, "[%d%.]+[gsc]", "") ~= "" then
    return nil
  end
  return math.floor(total + 0.5)
end

local function number(field, text)
  if field.kind == "money" then
    return Query.ParseMoney(text)
  end
  return tonumber(text)
end

-- ---------------------------------------------------------------------------------------------
-- Reading the text: tokens
-- ---------------------------------------------------------------------------------------------

local BREAK = '[%s%(%)"|&]' -- what ends a word

-- { kind = "word"|"phrase"|"pattern"|"or"|"and"|"not"|"open"|"close", text, field?, at }
local function tokens(text, q)
  local out, i, n = {}, 1, #text
  local function add(t)
    out[#out + 1] = t
  end
  while i <= n do
    local c = sub(text, i, i)
    if find(c, "%s") then
      i = i + 1
    elseif c == "(" then
      add({ kind = "open", at = i })
      i = i + 1
    elseif c == ")" then
      add({ kind = "close", at = i })
      i = i + 1
    elseif c == "|" or c == "&" then
      add({ kind = c == "|" and "or" or "and", at = i })
      i = i + 1
      while sub(text, i, i) == c do
        i = i + 1
      end
    elseif (c == "-" or c == "!") and i < n and not find(sub(text, i + 1, i + 1), "[%s%)]") then
      add({ kind = "not", at = i })
      i = i + 1
    elseif c == "+" and i < n and not find(sub(text, i + 1, i + 1), "[%s%)]") then
      i = i + 1 -- Google's "+word": the word is needed, as every word is
    elseif c == '"' then
      local close = find(text, '"', i + 1, true)
      if not close then
        q.error, q.errorAt = q.error or "quote", q.errorAt or i
        close = n + 1
      end
      add({ kind = "phrase", text = sub(text, i + 1, close - 1), at = i })
      i = close + 1
    elseif c == "/" and i < n then
      -- a pattern runs to the next "/" that ends a word (followed by a space, a bracket or the end)
      local j, close = i + 1, nil
      while j <= n do
        if sub(text, j, j) == "/" and (j == n or find(sub(text, j + 1, j + 1), "[%s%)]")) then
          close = j
          break
        end
        j = j + 1
      end
      if close and close > i + 1 then
        add({ kind = "pattern", text = sub(text, i + 1, close - 1), raw = sub(text, i, close), at = i })
        i = close + 1
      else
        local e = (find(text, BREAK, i + 1) or n + 1) - 1
        add({ kind = "word", text = sub(text, i, e), at = i })
        i = e + 1
      end
    else
      local e = (find(text, BREAK, i) or n + 1) - 1
      local word = sub(text, i, e)
      local t = { kind = "word", text = word, at = i }
      -- field:"a phrase"
      if sub(word, -1) == ":" and sub(text, e + 1, e + 1) == '"' then
        local close = find(text, '"', e + 2, true)
        if not close then
          q.error, q.errorAt = q.error or "quote", q.errorAt or e + 1
          close = n + 1
        end
        t.text, t.quoted = word .. sub(text, e + 2, close - 1), true
        e = close
      end
      if not t.quoted and (word == "OR" or word == "AND" or word == "NOT") then
        t = { kind = lower(word), at = i }
      end
      add(t)
      i = e + 1
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Terms
-- ---------------------------------------------------------------------------------------------

local function textTerm(word, field, quoted)
  local low = lower(word)
  if not quoted and find(low, "*", 1, true) then
    local pattern = gsub(gsub(low, MAGIC, "%%%1"), "%%%*", "%%S-")
    return { term = "pattern", pattern = pattern, field = field }
  end
  return { term = "text", text = low, field = field }
end

local function patternTerm(t, q)
  if pcall(find, "", t.text) then
    return { term = "pattern", pattern = t.text }
  end
  q.error, q.errorAt = q.error or "pattern", q.errorAt or t.at
  return textTerm(t.raw)
end

-- A word: a field's comparison, range or value when the box knows the field, else plain text.
local function wordTerm(t, q)
  local word = t.text
  local fields = q.fields
  if fields then
    local name, rest = string.match(word, "^([%a_][%w_]*)(.*)$")
    local field = name and fields[lower(name)]
    if field and rest ~= "" then
      local op, value = string.match(rest, "^:?([<>]=?)(.+)$")
      if not op then
        op, value = string.match(rest, "^(=)(.+)$")
      end
      if not op then
        value = string.match(rest, "^:(.*)$")
      end
      if value then
        local kind = field.kind or "text"
        if kind == "flag" then
          return { term = "flag", field = field, value = lower(value) }
        end
        if kind == "number" or kind == "money" then
          local lo, hi = string.match(value, "^(.-)%.%.(.+)$")
          lo, hi = lo and number(field, lo), hi and number(field, hi)
          if lo and hi then
            return { term = "range", field = field, lo = lo, hi = hi }
          end
          local num = number(field, value)
          if num then
            return { term = "compare", field = field, op = op or "=", num = num }
          end
        elseif op and op ~= "=" then
          local num = tonumber(value)
          if num then
            return { term = "compare", field = field, op = op, num = num }
          end
        end
        if value == "" then
          return nil -- "zone:" while typing
        end
        return textTerm(value, field, t.quoted)
      end
    end
  end
  return textTerm(word)
end

-- ---------------------------------------------------------------------------------------------
-- Parsing: OR of ANDs of (NOT) terms and groups
-- ---------------------------------------------------------------------------------------------

local function parser(list, q)
  local pos = 1
  local parseOr
  local function peek()
    return list[pos]
  end
  local function unary()
    local t = peek()
    if not t then
      return nil
    end
    if t.kind == "not" then
      pos = pos + 1
      local node = unary()
      return node and { op = "not", node = node } or nil
    elseif t.kind == "open" then
      pos = pos + 1
      local node = parseOr()
      if peek() and peek().kind == "close" then
        pos = pos + 1
      else
        q.error, q.errorAt = q.error or "bracket", q.errorAt or t.at
      end
      return node
    end
    pos = pos + 1
    if t.kind == "phrase" then
      return t.text ~= "" and textTerm(t.text, nil, true) or nil
    elseif t.kind == "pattern" then
      return patternTerm(t, q)
    end
    return wordTerm(t, q)
  end
  local function parseAnd()
    local items = {}
    while true do
      local t = peek()
      if not t or t.kind == "close" or t.kind == "or" then
        break
      end
      if t.kind == "and" then
        pos = pos + 1
      else
        local node = unary()
        if node then
          items[#items + 1] = node
        end
      end
    end
    if #items == 0 then
      return nil
    end
    return #items == 1 and items[1] or { op = "and", list = items }
  end
  function parseOr()
    local branches = {}
    while true do
      local node = parseAnd()
      if node then
        branches[#branches + 1] = node
      end
      local t = peek()
      if t and t.kind == "or" then
        pos = pos + 1
      else
        break
      end
    end
    if #branches == 0 then
      return nil
    end
    return #branches == 1 and branches[1] or { op = "or", list = branches }
  end
  local top = {}
  while pos <= #list do
    local node = parseOr()
    if node then
      top[#top + 1] = node
    end
    local t = peek()
    if t and t.kind == "close" then
      q.error, q.errorAt = q.error or "stray", q.errorAt or t.at
      pos = pos + 1
    end
  end
  if #top == 0 then
    return nil
  end
  return #top == 1 and top[1] or { op = "and", list = top }
end

-- ---------------------------------------------------------------------------------------------
-- Matching: true, false, or nil for unknown (Kleene logic; only true matches)
-- ---------------------------------------------------------------------------------------------

local eval

-- A field's text, or any of its list of texts, passes `fn`.
local function fieldText(v, fn)
  if type(v) == "table" then
    for _, item in ipairs(v) do
      if fn(lower(tostring(item))) then
        return true
      end
    end
    return false
  end
  return fn(lower(tostring(v)))
end

local function compare(op, a, b)
  if op == "=" then
    return a == b
  elseif op == ">" then
    return a > b
  elseif op == ">=" then
    return a >= b
  elseif op == "<" then
    return a < b
  end
  return a <= b
end

local function evalTerm(node, low, rec)
  local term, field = node.term, node.field
  if term == "text" or term == "pattern" then
    local function test(hay)
      if term == "text" then
        return find(hay, node.text, 1, true) ~= nil
      end
      local ok, at = pcall(find, hay, node.pattern)
      return ok and at ~= nil
    end
    if not field then
      return low ~= nil and test(low)
    end
    local v = field.get(rec)
    if v == nil then
      return nil
    end
    return fieldText(v, test)
  elseif term == "flag" then
    local v = field.get(rec, node.value)
    if v == nil then
      return nil
    end
    return v and true or false
  end
  local v = field.get(rec)
  if type(v) ~= "number" then
    v = tonumber(v)
  end
  if v == nil then
    return nil
  end
  if term == "range" then
    return v >= node.lo and v <= node.hi
  end
  return compare(node.op, v, node.num)
end

function eval(node, low, rec)
  local op = node.op
  if op == "and" then
    local result = true
    for _, child in ipairs(node.list) do
      local r = eval(child, low, rec)
      if r == false then
        return false
      elseif r == nil then
        result = nil
      end
    end
    return result
  elseif op == "or" then
    local result = false
    for _, child in ipairs(node.list) do
      local r = eval(child, low, rec)
      if r == true then
        return true
      elseif r == nil then
        result = nil
      end
    end
    return result
  elseif op == "not" then
    local r = eval(node.node, low, rec)
    if r == nil then
      return nil
    end
    return not r
  end
  return evalTerm(node, low, rec)
end

-- The plain words to highlight (positive text terms without a field) and whether the query is
-- nothing but such words in an AND (the fast path).
local function collect(node, words, negated)
  if not node then
    return true
  end
  if node.op == "and" then
    local plain = true
    for _, child in ipairs(node.list) do
      plain = collect(child, words, negated) and plain
    end
    return plain
  elseif node.op == "or" then
    for _, child in ipairs(node.list) do
      collect(child, words, negated)
    end
    return false
  elseif node.op == "not" then
    collect(node.node, words, true)
    return false
  end
  if node.term == "text" and not node.field then
    if not negated then
      words[#words + 1] = node.text
    end
    return not negated
  end
  return false
end

-- ---------------------------------------------------------------------------------------------
-- The query object
-- ---------------------------------------------------------------------------------------------

local Q = {}
Q.__index = Q

-- Does the record match? `rec` is a text (any case) or a table; a table's text comes from the
-- compile option `text(rec)`. Fields read the table.
function Q:Match(rec)
  if self.empty then
    return true
  end
  local text = rec
  if type(rec) ~= "string" then
    text = self.textOf and self.textOf(rec) or nil
  end
  return self:MatchLower(text and lower(text) or nil, rec)
end

-- The same with the record's text already in lower case (the lists keep it so).
function Q:MatchLower(low, rec)
  if self.empty then
    return true
  end
  if self.plain then
    if not low then
      return false
    end
    for _, w in ipairs(self.words) do
      if not find(low, w, 1, true) then
        return false
      end
    end
    return true
  end
  return eval(self.root, low, rec) == true
end

-- How well a name matches (search providers, core-contracts §7a): nil for no match, else exact 1,
-- starts with the first word 0.9, plain words found inside 0.7, any other match 0.6.
function Q:Score(name, rec)
  if self.empty or type(name) ~= "string" then
    return nil
  end
  local low = lower(name)
  if not self:MatchLower(low, rec) then
    return nil
  end
  local words = self.words
  if self.plain and low == self.joined then
    return 1
  end
  if words[1] and sub(low, 1, #words[1]) == words[1] then
    return 0.9
  end
  return self.plain and 0.7 or 0.6
end

local cache = setmetatable({}, { __mode = "k" }) -- [fields table] = { n, byText = { [text] = q } }
local NO_FIELDS = {}
local CACHE_MAX = 64

-- Query.Compile(text, { fields = { name = { kind, get } }, text = function(rec) end }) -> q.
-- Never fails: a broken part is read as well as it can be and named in q.error (a key of
-- Query.ERRORS) at q.errorAt. q.empty: nothing to match (every record matches).
-- Field kinds: "text" (default; get(rec) -> a text or a list of texts), "number", "money"
-- (get(rec) -> a number of copper), "flag" (get(rec, value) -> true/false). get returns nil for
-- unknown.
function Query.Compile(text, opts)
  text = trim(tostring(text or ""))
  opts = opts or NO_FIELDS
  local key = opts.fields or NO_FIELDS
  local slot = cache[key]
  if not slot or slot.n >= CACHE_MAX then
    slot = { n = 0, byText = {} }
    cache[key] = slot
  end
  local hit = slot.byText[text]
  if hit and hit.textOf == opts.text then
    return hit
  end
  local q = setmetatable({ text = text, fields = opts.fields, textOf = opts.text, words = {} }, Q)
  q.root = parser(tokens(text, q), q)
  q.empty = q.root == nil
  q.plain = collect(q.root, q.words) and #q.words > 0
  q.joined = table.concat(q.words, " ")
  slot.byText[text] = q
  slot.n = slot.n + 1
  return q
end

-- A query string or a compiled query -> a compiled query.
function Query.Of(query, opts)
  if type(query) == "table" and query.MatchLower then -- a query, or one wrapped with more fields
    return query
  end
  return Query.Compile(query, opts)
end

-- The positive text terms of an AND (or one term), nil for anything else.
local function andTerms(node)
  if not node then
    return nil
  end
  local list = node.op == "and" and node.list or { node }
  for _, t in ipairs(list) do
    if t.term ~= "text" then
      return nil
    end
  end
  return list
end

-- Does every record that matches `new` match `old` too? Then a list may test only the rows the
-- old text kept ("if the search is further specified, you only need to
-- search the current results"). True for the plain case only: both an AND of positive text terms
-- (words, phrases, a text field's value), the new text typed on at the end of the old one, so
-- the terms are the same but the last, which grew. Anything else (OR, NOT, `*`, numbers, a new
-- field) answers false and the list scans everything.
function Query.Narrows(oldText, newText, opts)
  oldText, newText = trim(tostring(oldText or "")), trim(tostring(newText or ""))
  if oldText == "" or sub(newText, 1, #oldText) ~= oldText then
    return false
  end
  if newText == oldText then
    return true
  end
  local old, new = Query.Compile(oldText, opts), Query.Compile(newText, opts)
  if old.error or new.error or old.empty or new.empty then
    return false
  end
  local a, b = andTerms(old.root), andTerms(new.root)
  if not (a and b) or #b < #a then
    return false
  end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if x.field ~= y.field then
      return false
    end
    if i < #a then
      if x.text ~= y.text then
        return false
      end
    elseif sub(y.text, 1, #x.text) ~= x.text then
      return false
    end
  end
  return true
end
