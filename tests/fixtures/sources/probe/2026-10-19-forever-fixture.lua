-- Synthetic probe dump for tests: the shape Bastians_Probe writes, with made-up but consistent map corners.
-- Elwynn Forest (1429) spans world x -7940..-10254 (north to south) and y 1535..-1935 (west to east);
-- Stormwind (1453) is a smaller map inside the same continent. Not measured: replaced by a real dump (P3).
BastiansProbeDB = {
  ["meta"] = { ["client"] = "forever", ["build"] = "fixture", ["interface"] = 16001 },
  ["results"] = {
    ["P3"] = {
      ["found"] = 4,
      ["maps"] = {
        [947] = { ["name"] = "Azeroth", ["mapType"] = 1, ["parent"] = 0 },
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
  },
}
