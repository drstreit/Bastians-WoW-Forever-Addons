-- Bastian's Book: a creature's round portrait by its npc id, its display learned from the client (ADR 0090).
local _, ns = ...
local B = Bastians

local Portrait = {}
ns.Portrait = Portrait

Portrait.TIMEOUT = 3 -- seconds a creature's model may take to load; then it is given up

local known, failed, asked = {}, {}, {}
local queue = {}
local scratch -- the one model nobody sees
local current -- the creature it is loading
local turn = 0 -- which wait is the running one

-- Whether this client draws creature portraits at all.
function Portrait.Can()
  return B.Compat.CanCreaturePortrait() == true
end

-- The display the client answered for the creature, or nil.
function Portrait.Known(npcID)
  return known[tonumber(npcID) or 0]
end

-- The model the creatures are set on (tests, the probe).
function Portrait.Model()
  return scratch
end

local function settle(npcID, displayID)
  if displayID then
    known[npcID] = displayID
    if Portrait.OnKnown then -- who drew a stand-in draws the portrait now (the Atlas)
      Portrait.OnKnown(npcID, displayID)
    end
  else
    failed[npcID] = true -- not asked again this session
  end
end

-- Takes the queue's creatures in turn until one has to be waited for.
local function work()
  while true do
    turn = turn + 1
    current = table.remove(queue, 1)
    if not current then
      scratch:Hide() -- nothing to load: the model rests
      return
    end
    scratch:Show()
    local npcID = current
    if not B.Compat.ShowCreature(scratch, npcID) then
      settle(npcID, nil)
    else
      local displayID = B.Compat.ModelDisplay(scratch)
      if displayID then -- the client knew at once
        settle(npcID, displayID)
      else
        local mine = turn
        C_Timer.After(Portrait.TIMEOUT, function()
          if mine == turn and current == npcID then
            settle(npcID, B.Compat.ModelDisplay(scratch))
            work()
          end
        end)
        return
      end
    end
  end
end

local function onLoaded()
  local npcID = current
  if not npcID then
    return
  end
  settle(npcID, B.Compat.ModelDisplay(scratch))
  work()
end

-- Asks the client for the creature's display; Portrait.OnKnown(npcID, displayID) is called when
-- it answers. Nothing happens for a creature known, asked or given up already.
function Portrait.Ask(npcID)
  npcID = tonumber(npcID)
  if not npcID or known[npcID] or failed[npcID] or asked[npcID] or not Portrait.Can() then
    return
  end
  if not scratch then
    scratch = B.Compat.NewModel(UIParent)
    if not scratch then
      failed[npcID] = true
      return
    end
    -- its place and size before a creature is set: a model on a frame with no size stays empty
    scratch:SetSize(1, 1)
    scratch:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    scratch:SetAlpha(0)
    scratch:EnableMouse(false)
    scratch:SetScript("OnModelLoaded", onLoaded)
    scratch:Hide()
  end
  asked[npcID] = true
  queue[#queue + 1] = npcID
  if not current then
    work()
  end
end

-- Draws the creature's portrait into `texture` -> true. false: the display is not known (it is
-- asked for now) or this client draws none; the caller keeps what it drew before.
function Portrait.Set(texture, npcID)
  npcID = tonumber(npcID)
  local displayID = npcID and known[npcID]
  if displayID then
    return B.Compat.CreaturePortrait(texture, displayID) == true
  end
  Portrait.Ask(npcID)
  displayID = npcID and known[npcID] -- the client may have known at once
  if displayID then
    return B.Compat.CreaturePortrait(texture, displayID) == true
  end
  return false
end
