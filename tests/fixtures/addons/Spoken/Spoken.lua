-- Test double of Spoken 3.5 (the voice player): only the public API the Quests bridge uses.
Spoken = { API_VERSION = 1, callbacks = {}, queue = {}, stoppedAll = 0 }

function Spoken:IsCompatible(required)
  return type(required) == "number" and required <= self.API_VERSION
end

function Spoken:RegisterCallback(event, fn)
  local handle = { event = event, fn = fn }
  self.callbacks[#self.callbacks + 1] = handle
  return handle
end

function Spoken:UnregisterCallback(handle)
  for i = #self.callbacks, 1, -1 do
    if self.callbacks[i] == handle then
      table.remove(self.callbacks, i)
    end
  end
end

function Spoken:Fire(event, ...)
  for _, h in ipairs(self.callbacks) do
    if h.event == event then
      h.fn(...)
    end
  end
end

function Spoken:GetQueue()
  local out = {}
  for i, clip in ipairs(self.queue) do
    out[i] = clip
  end
  return out
end

function Spoken:GetSource(key)
  if key ~= "quests" then
    return nil
  end
  return {
    Remove = function(_, clip)
      for i = #Spoken.queue, 1, -1 do
        if Spoken.queue[i] == clip then
          table.remove(Spoken.queue, i)
        end
      end
      Spoken:Fire("AUDIO_CHANGED")
    end,
  }
end

function Spoken:StopAll()
  self.stoppedAll = self.stoppedAll + 1
  self.queue = {}
  self:Fire("AUDIO_CHANGED")
end
