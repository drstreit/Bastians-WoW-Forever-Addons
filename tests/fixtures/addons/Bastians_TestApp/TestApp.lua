-- Fixture app for the Core kernel tests: one module with a sub-module, events, bus, DB and migrations.
local ADDON, ns = ...

TestLog = TestLog or {}
local function log(entry)
  TestLog[#TestLog + 1] = entry
end

local mod = Bastians:NewModule("TestApp", {
  addon = ADDON,
  title = "Test App",
  apiVersion = 1,
  open = function() -- the hub's Open button (core.md "Settings hub")
    _G.testAppOpened = (_G.testAppOpened or 0) + 1
  end,
  defaults = {
    profile = { pinSize = 16, colors = { accent = "blue" } },
    char = { seen = 0 },
    global = { installs = 0 },
  },
  optional = { "QuestieDB", "Bastians_Nope" },
  options = {
    { type = "header", label = "Display" },
    { type = "toggle", key = "showMinimapButton", label = "Minimap button", default = true },
    { type = "range", key = "pinSize", label = "Pin size", min = 8, max = 32, step = 1 },
    { type = "select", key = "network", label = "Flight paths", values = { known = "Known only", all = "All" }, default = "known" },
    { type = "execute", label = "Reset", func = function() log("reset") end },
    { type = "note", text = function(mod) return "Pins: " .. tostring(mod.db.profile.pinSize) end },
  },
  migrations = {
    [2] = function(db)
      log("migrate2")
      if db.profile.oldSize then
        db.profile.pinSize = db.profile.oldSize
        db.profile.oldSize = nil
      end
    end,
  },
  OnInitialize = function()
    log("init")
  end,
  OnEnable = function(self)
    log("enable")
    self:RegisterEvent("TEST_EVENT", function(_, _, arg)
      if TestThrow then
        error("boom")
      end
      log("event:" .. tostring(arg))
    end)
    self:On("TEST_MSG", function(_, _, arg)
      log("msg:" .. tostring(arg))
    end)
  end,
  OnDisable = function()
    log("disable")
  end,
})
ns.mod = mod

Bastians:NewModule("TestApp.Sub", {
  defaults = { profile = { volume = 5 } },
  OnEnable = function()
    log("sub-enable")
  end,
  OnDisable = function()
    log("sub-disable")
  end,
})
