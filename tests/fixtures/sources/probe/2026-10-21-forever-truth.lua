-- Synthetic probe dump for the probe ground-truth tests (probetruth.py): the P3 corners of the
-- 2026-10-19 fixture plus P2 quest log entries, P4 landmarks and P7 taxi records in the shape
-- Bastians_Probe writes (try() records are { ok, ret } with "<nil>" for nil returns). Values are made
-- up but consistent with the corners: Elwynn (1429) centre is world x -9096.875, y -200; UnitPosition returns x, y, z, instance.
BastiansProbeDB = {
  ["meta"] = { ["client"] = "forever", ["build"] = "fixture", ["interface"] = 16001 },
  ["results"] = {
    ["P3"] = {
      ["found"] = 3,
      ["maps"] = {
        [1415] = {
          ["name"] = "Eastern Kingdoms", ["mapType"] = 2, ["parent"] = 947,
          ["c00"] = { ["continent"] = 0, ["x"] = 10000, ["y"] = 10000 },
          ["c11"] = { ["continent"] = 0, ["x"] = -20000, ["y"] = -10000 },
          ["c10"] = { ["continent"] = 0, ["x"] = 10000, ["y"] = -10000 },
        },
        [1429] = {
          ["name"] = "Elwynn Forest", ["mapType"] = 3, ["parent"] = 1415,
          ["c00"] = { ["continent"] = 0, ["x"] = -7939.58, ["y"] = 1535.42 },
          ["c11"] = { ["continent"] = 0, ["x"] = -10254.17, ["y"] = -1935.42 },
          ["c10"] = { ["continent"] = 0, ["x"] = -7939.58, ["y"] = -1935.42 },
        },
        [1453] = {
          ["name"] = "Stormwind City", ["mapType"] = 3, ["parent"] = 1415,
          ["c00"] = { ["continent"] = 0, ["x"] = -8000, ["y"] = 2000 },
          ["c11"] = { ["continent"] = 0, ["x"] = -9000, ["y"] = 500 },
          ["c10"] = { ["continent"] = 0, ["x"] = -8000, ["y"] = 500 },
        },
      },
    },
    ["P2"] = {
      ["at"] = "2026-10-21T20:00:00Z",
      ["modern"] = {
        { ["index"] = 1, ["info"] = { ["ok"] = true, ["ret"] = { { ["questID"] = 0, ["title"] = "Elwynn Forest", ["isHeader"] = true } } } },
        { ["index"] = 2, ["info"] = { ["ok"] = true, ["ret"] = { { ["questID"] = 176, ["title"] = 'Wanted: "Hogger"', ["isHeader"] = false } } } },
        { ["index"] = 3, ["info"] = { ["ok"] = true, ["ret"] = { { ["questID"] = 62, ["title"] = "The Fargodeep Mine (renamed)", ["isHeader"] = false } } } },
        { ["index"] = 4, ["info"] = { ["ok"] = true, ["ret"] = { { ["questID"] = 99999, ["title"] = "Ghost quest", ["isHeader"] = false } } } },
        { ["index"] = 5, ["info"] = { ["ok"] = true, ["ret"] = { { ["questID"] = 176, ["title"] = 'Wanted: "Hogger"', ["isHeader"] = false } } } },
        { ["index"] = 6, ["info"] = { ["ok"] = false, ["err"] = "boom" } },
      },
      ["legacy"] = {},
    },
    ["P4"] = {
      {
        ["label"] = "Goldshire inn door",
        ["mapID"] = 1429, ["mapX"] = 0.5, ["mapY"] = 0.5,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -9096.875, -200.0, 100.0, 0 } },
        ["zone"] = "Elwynn Forest", ["subzone"] = "Goldshire", ["at"] = "2026-10-21T20:01:00Z",
      },
      {
        ["label"] = "Crystal Lake shore",
        ["mapID"] = 1429, ["mapX"] = 0.5, ["mapY"] = 0.5,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -9196.875, -200.0, 100.0, 0 } },
        ["zone"] = "Elwynn Forest", ["at"] = "2026-10-21T20:02:00Z",
      },
      {
        ["label"] = "Deadmines entrance",
        ["mapID"] = 1436, ["mapX"] = 0.42, ["mapY"] = 0.71,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -11000.0, 1500.0, 10.0, 0 } },
        ["zone"] = "Westfall", ["at"] = "2026-10-21T20:03:00Z",
      },
      {
        ["label"] = "inside the Deadmines",
        ["mapID"] = 1581, ["mapX"] = 0.3, ["mapY"] = 0.3,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { "<nil>", "<nil>", "<nil>", 36 } },
        ["zone"] = "The Deadmines", ["at"] = "2026-10-21T20:04:00Z",
      },
      -- landmarks with a target (21.10.2026): the pack's place of that NPC, object or node is checked
      {
        ["label"] = "Marshal Dughan",
        ["mapID"] = 1429, ["mapX"] = 0.421, ["mapY"] = 0.652,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -9448.69, 74.20, 100.0, 0 } },
        ["target"] = { ["guid"] = "Creature-0-4234-0-1-240-0000A1B2C3", ["kind"] = "npc", ["id"] = 240, ["name"] = "Marshal Dughan" },
        ["zone"] = "Elwynn Forest", ["subzone"] = "Goldshire", ["at"] = "2026-10-21T20:06:00Z",
      },
      {
        ["label"] = "Hogger far off",
        ["mapID"] = 1429, ["mapX"] = 0.50, ["mapY"] = 0.50,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -9096.875, -200.0, 100.0, 0 } },
        ["target"] = { ["guid"] = "Creature-0-4234-0-1-448-0000A1B2C4", ["kind"] = "npc", ["id"] = 448, ["name"] = "Hogger" },
        ["zone"] = "Elwynn Forest", ["at"] = "2026-10-21T20:07:00Z",
      },
      {
        ["label"] = "poster",
        ["mapID"] = 1429, ["mapX"] = 0.42, ["mapY"] = 0.66,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -9467.21, 77.67, 100.0, 0 } },
        ["target"] = { ["guid"] = "GameObject-0-4234-0-1-1734-0000A1B2C5", ["kind"] = "object", ["id"] = 1734, ["name"] = "Wanted Poster" },
        ["zone"] = "Elwynn Forest", ["at"] = "2026-10-21T20:08:00Z",
      },
      {
        ["label"] = "renamed innkeeper",
        ["mapID"] = 1429, ["mapX"] = 0.43, ["mapY"] = 0.66,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -9467.21, 42.96, 100.0, 0 } },
        ["target"] = { ["guid"] = "Creature-0-4234-0-1-295-0000A1B2C6", ["kind"] = "npc", ["id"] = 295, ["name"] = "Innkeeper Farlay" },
        ["zone"] = "Elwynn Forest", ["at"] = "2026-10-21T20:09:00Z",
      },
      {
        ["label"] = "Dughan seen in Westfall",
        ["mapID"] = 1436, ["mapX"] = 0.56, ["mapY"] = 0.47,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -11000.0, 1500.0, 10.0, 0 } },
        ["target"] = { ["guid"] = "Creature-0-4234-0-1-240-0000A1B2C7", ["kind"] = "npc", ["id"] = 240, ["name"] = "Marshal Dughan" },
        ["zone"] = "Westfall", ["at"] = "2026-10-21T20:10:00Z",
      },
      {
        ["label"] = "a stranger",
        ["mapID"] = 1429, ["mapX"] = 0.42, ["mapY"] = 0.65,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -9444.06, 77.67, 100.0, 0 } },
        ["target"] = { ["guid"] = "Creature-0-4234-0-1-77777-0000A1B2C8", ["kind"] = "npc", ["id"] = 77777, ["name"] = "Nobody" },
        ["zone"] = "Elwynn Forest", ["at"] = "2026-10-21T20:11:00Z",
      },
      {
        ["label"] = "another player",
        ["mapID"] = 1429, ["mapX"] = 0.42, ["mapY"] = 0.65,
        ["unitPosition"] = { ["ok"] = true, ["ret"] = { -9444.06, 77.67, 100.0, 0 } },
        ["target"] = { ["guid"] = "Player-1-0000ABCD", ["kind"] = "player", ["name"] = "Someone" },
        ["zone"] = "Elwynn Forest", ["at"] = "2026-10-21T20:12:00Z",
      },
    },
    ["P7"] = {
      ["opens"] = {
        {
          ["at"] = "2026-10-21T20:05:00Z",
          ["position"] = {
            ["mapID"] = 1453, ["mapX"] = 0.5, ["mapY"] = 0.5,
            ["unitPosition"] = { ["ok"] = true, ["ret"] = { -8500.0, 1250.0, 100.0, 0 } },
            ["zone"] = "Stormwind City",
          },
          ["modern"] = {
            ["ok"] = true,
            ["ret"] = {
              {
                { ["nodeID"] = 2, ["name"] = "Stormwind, Elwynn", ["position"] = { ["x"] = 0.502, ["y"] = 0.497 }, ["state"] = 1 },
                { ["nodeID"] = 4, ["name"] = "Sentinel Hill, Westfall", ["position"] = { ["x"] = 0.2, ["y"] = 0.9 }, ["state"] = 2 },
                { ["nodeID"] = 6, ["name"] = "Ironforge, Dun Morogh (renamed)", ["position"] = { ["x"] = 0.6, ["y"] = 0.1 }, ["state"] = 2 },
                { ["nodeID"] = 999, ["name"] = "Nowhere", ["position"] = { ["x"] = 0.1, ["y"] = 0.1 }, ["state"] = 0 },
              },
            },
          },
          ["legacyCount"] = { ["ok"] = true, ["ret"] = { 4 } },
        },
      },
      ["flights"] = {
        {
          ["index"] = 2, ["to"] = "Sentinel Hill, Westfall", ["seconds"] = 61.25,
          ["started"] = "2026-10-21T20:06:00Z",
          ["from"] = { ["mapID"] = 1453, ["mapX"] = 0.5, ["mapY"] = 0.5 },
          ["landed"] = { ["mapID"] = 1436, ["mapX"] = 0.56, ["mapY"] = 0.52 },
        },
      },
    },
  },
}
