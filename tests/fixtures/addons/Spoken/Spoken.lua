-- Test double of Spoken 3.5 (the voice player): the public API the Voice bridge uses (API.lua of
-- 01.11.2026). Sources are tables with Enqueue, PlayNow, Remove and StopAll; the queue is one list of
-- clips, each carrying its `source`; Spoken.Finish() ends the head as the player would when the
-- clip has played out (stopCallback(clip, true)).
Spoken = { API_VERSION = 1, ADDON_VERSION = "3.7.0", callbacks = {}, queue = {}, stoppedAll = 0, sources = {}, paused = false }
Spoken.SITE_URL = "https://spoken.rusty.one"

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

function Spoken:GetCurrent()
  return self.queue[1]
end

function Spoken:GetNowPlaying()
  return self.queue[1]
end

function Spoken:IsPlaying(clip)
  if clip then
    return self.queue[1] == clip
  end
  return self.queue[1] ~= nil and not self.paused
end

function Spoken:IsPaused()
  return self.paused
end

function Spoken:Pause()
  self.paused = true
  self:Fire("AUDIO_CHANGED")
end

function Spoken:Resume()
  self.paused = false
  self:Fire("AUDIO_CHANGED")
end

function Spoken:TogglePause()
  self.paused = not self.paused
  self:Fire("AUDIO_CHANGED")
end

function Spoken:VoiceLanguage()
  return self.voiceLanguage or "enUS"
end

function Spoken:GetLanguageChoice()
  return self.voiceLanguage or "auto", self.fallbackLanguage or "enUS"
end

function Spoken:ShowsNarratorFor()
  return self.narrator ~= false
end

function Spoken:GetCaption()
  local head = self.queue[1]
  if not head then
    return nil
  end
  return { clip = head, progress = self.progress or 0.25, speaking = not self.paused }
end

local function remove(clip)
  for i = #Spoken.queue, 1, -1 do
    if Spoken.queue[i] == clip then
      table.remove(Spoken.queue, i)
    end
  end
end

local function newSource(key)
  local source = { key = key, enqueued = 0 }
  function source:Enqueue(clip)
    clip.source = self
    self.enqueued = self.enqueued + 1
    Spoken.queue[#Spoken.queue + 1] = clip
    Spoken:Fire("CLIP_QUEUED", clip)
    Spoken:Fire("AUDIO_CHANGED")
    return clip
  end
  function source:PlayNow(clip)
    clip.source = self
    table.insert(Spoken.queue, 1, clip)
    Spoken:Fire("CLIP_QUEUED", clip)
    Spoken:Fire("AUDIO_CHANGED")
    return true
  end
  function source:Remove(clip)
    remove(clip)
    if clip.stopCallback then
      clip.stopCallback(clip, false)
    end
    Spoken:Fire("AUDIO_CHANGED")
  end
  function source:StopAll()
    for i = #Spoken.queue, 1, -1 do
      if Spoken.queue[i].source == self then
        table.remove(Spoken.queue, i)
      end
    end
    Spoken:Fire("AUDIO_CHANGED")
  end
  return source
end

-- Spoken Quests' source exists from the start, as in the player
Spoken.sources.quests = newSource("quests")

function Spoken:RegisterSource(key, info)
  local source = newSource(key)
  source.info = info
  self.sources[key] = source
  self:Fire("SOURCE_REGISTERED", source)
  return source
end

function Spoken:GetSource(key)
  return self.sources[key]
end

function Spoken:StopAll()
  self.stoppedAll = self.stoppedAll + 1
  self.queue = {}
  self.paused = false
  self:Fire("AUDIO_CHANGED")
end

-- The head played out: the player calls its stopCallback with finishedPlaying and moves on.
function Spoken:Finish()
  local head = table.remove(self.queue, 1)
  if head and head.stopCallback then
    head.stopCallback(head, true)
  end
  self:Fire("AUDIO_CHANGED")
  return head
end
