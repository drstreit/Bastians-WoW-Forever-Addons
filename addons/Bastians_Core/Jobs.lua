-- Sliced work (core-contracts §12): coroutines with a per-frame time budget; no OnUpdate while idle.
local _, ns = ...
local B = ns.B

local Jobs = { queue = {}, budgetMs = 4 }
B.Jobs = Jobs

local frame = CreateFrame("Frame")
frame:Hide()

local Handle = {}
Handle.__index = Handle

function Handle:Cancel()
  self.cancelled = true
end
function Handle:IsDone()
  return self.done
end
function Handle:IsCancelled()
  return self.cancelled
end

local function finish(job)
  job.done = true
  if job.owner and job.owner.jobs then
    job.owner.jobs[job] = nil
  end
  if job.onDone and not job.cancelled then
    ns.safecall(job.owner, job.onDone, job)
  end
end

-- Bastians.Jobs:Run(owner, name, fn, { budgetMs = 4, onDone = function(job) end })
-- fn receives a `yield` function to call inside long loops; the job continues next frame.
function Jobs:Run(owner, name, fn, opts)
  opts = opts or {}
  local job = setmetatable({
    owner = owner,
    name = name,
    budgetMs = opts.budgetMs or self.budgetMs,
    onDone = opts.onDone,
    done = false,
    cancelled = false,
  }, Handle)
  job.co = coroutine.create(function()
    fn(coroutine.yield)
  end)
  self.queue[#self.queue + 1] = job
  if owner and owner.jobs then
    owner.jobs[job] = true
  end
  frame:Show()
  return job
end

function Jobs:CancelAll(owner)
  for i = #self.queue, 1, -1 do
    local job = self.queue[i]
    if job.owner == owner then
      job.cancelled = true
      table.remove(self.queue, i)
      finish(job)
    end
  end
  if #self.queue == 0 then
    frame:Hide()
  end
end

function Jobs:Pending()
  return #self.queue
end

-- Run a job to its end now, ignoring the budget: for data that vanishes when a window closes
-- (the auction listing). The job's onDone runs as usual.
function Jobs:Flush(job)
  if not job or job.done or job.cancelled then
    return
  end
  for i = #self.queue, 1, -1 do
    if self.queue[i] == job then
      table.remove(self.queue, i)
    end
  end
  while coroutine.status(job.co) ~= "dead" do
    local ok, err = coroutine.resume(job.co)
    if not ok then
      ns.noteError(job.owner, ("job %s: %s"):format(tostring(job.name), tostring(err)))
      job.cancelled = true
      job.failed = err
      break
    end
  end
  finish(job)
  if #self.queue == 0 then
    frame:Hide()
  end
end

-- One job per frame, round robin, resumed until its own budget is spent or it finishes.
frame:SetScript("OnUpdate", function()
  local queue = Jobs.queue
  local job = table.remove(queue, 1)
  if not job then
    frame:Hide()
    return
  end
  if not job.cancelled then
    local start = debugprofilestop()
    repeat
      local ok, err = coroutine.resume(job.co)
      if not ok then
        ns.noteError(job.owner, ("job %s: %s"):format(tostring(job.name), tostring(err)))
        job.cancelled = true
        job.failed = err
      end
    until job.cancelled or coroutine.status(job.co) == "dead" or debugprofilestop() - start >= job.budgetMs
    if B.Perf and B.Perf.enabled then -- a slice counts as one call of its owner (23.10.2026)
      B.Perf.Record(job.owner, "job " .. tostring(job.name), debugprofilestop() - start)
    end
  end
  if job.cancelled or coroutine.status(job.co) == "dead" then
    finish(job)
  else
    queue[#queue + 1] = job
  end
  if #queue == 0 then
    frame:Hide()
  end
end)
