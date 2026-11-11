-- What is known about a moment (courtesy.md "The moments"): the speaker, the hour, the weather and
-- the other person, as Voice reads them. What the client does not say stays unknown (CLAUDE.md 4.2).
local _, ns = ...
local B = Bastians
local Model, Compat, Voice = ns.Model, ns.Compat, ns.Voice

local Facts = {}
ns.Facts = Facts

local plain = B.Compat.Plain

local function sexWord(code)
  code = plain(code)
  return code == 2 and "m" or code == 3 and "f" or nil
end

-- The speaker: the character as it is.
function Facts.Speaker()
  local shown, key = UnitRace("player")
  return {
    myName = plain((UnitName("player"))),
    myRace = plain(shown),
    myRaceKey = plain(key),
    mySex = sexWord((Compat.Call("UnitSex", "player"))),
  }
end

-- The clock, the weather, the place and how the player fares, into `facts`.
function Facts.Surroundings(facts)
  local zone = plain((Compat.Call("GetZoneText")))
  facts.zone = type(zone) == "string" and zone ~= "" and zone or nil
  local subzone = Compat.SubZone()
  facts.subzone = subzone ~= facts.zone and subzone or nil
  facts.land = Model.LANDS[Compat.PlayerMap() or false]
  facts.time = Model.DayKey(plain((Compat.Call("GetGameTime"))))
  local weather, intensity = Compat.Weather()
  facts.weather = weather
  facts.heavy = Model.Heavy(weather, intensity)
  facts.hurt = Model.Hurt(Compat.Health())
  return facts
end

-- The other person from a unit token, into `facts`.
function Facts.Unit(facts, unit)
  local race, raceKey = UnitRace(unit)
  facts.race, facts.raceKey = plain(race), plain(raceKey)
  local class, classKey = UnitClass(unit)
  facts.class, facts.classKey = plain(class), plain(classKey)
  facts.sex = sexWord((Compat.Call("UnitSex", unit)))
  facts.level = Model.LevelGap(Compat.Level(unit), Compat.Level("player"))
  return facts
end

-- The other person from a GUID, into `facts` (an emote and an invite carry one, no unit).
function Facts.Guid(facts, guid)
  guid = plain(guid)
  if type(guid) ~= "string" or guid == "" then
    return facts
  end
  local class, classKey, race, raceKey, sex = Compat.Call("GetPlayerInfoByGUID", guid)
  facts.class, facts.classKey = plain(class), plain(classKey)
  facts.race, facts.raceKey = plain(race), plain(raceKey)
  facts.sex = sexWord(sex)
  return facts
end

local kinds -- spell name -> kind, in the client's language; built on first use

-- A spell's place under "buff" by its name ("mind", "nature.thorns", "blessing.might"), or nil.
function Facts.BuffKind(name)
  name = plain(name)
  if type(name) ~= "string" then
    return nil
  end
  if not kinds then
    kinds = {}
    for id, kind in pairs(Model.BUFFS) do
      local spell = B.Compat.GetSpellName(id)
      if spell then
        kinds[spell] = kind
      end
    end
  end
  return kinds[name]
end

-- The facts of a real moment.
function Facts.Moment(event)
  local facts = Facts.Surroundings(Facts.Speaker())
  facts.situation = Model.Situation(event, Facts.BuffKind)
  facts.target = event.who
  if event.kind == "buff" then -- what was cast, whether in a fight, whether more came with it
    local spell = plain(event.what)
    facts.spell = type(spell) == "string" and spell ~= "" and spell or nil
    facts.fight, facts.many = event.fight, event.many
  end
  if event.guid then
    Facts.Guid(facts, event.guid)
  elseif event.unit and UnitExists(event.unit) then
    Facts.Unit(facts, event.unit)
  end
  return Voice.Complete(facts)
end
