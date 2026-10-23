// Lists the minimap tile files of one map and converts a single tile BLP to PNG as proof.
// Source: the MAID chunk of world/maps/<dir>/<dir>.wdt (BfA and later: eight FileDataIDs per tile, the last is the
// minimap). Pre-BfA clients used textures/minimap/md5translate.trs instead; not implemented, see the doc.
using BLPSharp;

namespace ClientDump;

static class Minimap
{
    public static void Run(Client c, string defsDir, string map, string outDir,
        string? wdtFdidArg = null, string? listfile = null, string? tileArg = null)
    {
        var (_, dir, tiles) = ListTiles(c, defsDir, map, wdtFdidArg, listfile);
        Directory.CreateDirectory(outDir);
        var list = Path.Combine(outDir, $"{dir}_tiles.txt");
        File.WriteAllLines(list, tiles.Select(t => $"{t.x}\t{t.y}\t{t.fdid}"));
        Console.WriteLine($"tile list -> {list}");

        var first = tiles[0];
        if (tileArg != null)
        {
            var xy = tileArg.Split(',');
            first = tiles.First(t => t.x == int.Parse(xy[0]) && t.y == int.Parse(xy[1]));
        }
        using var blp = new MemoryStream(c.ReadFdid(first.fdid));
        var pixels = new BLPFile(blp).GetPixels(0, out var w, out var h); // BGRA
        var png = Path.Combine(outDir, $"{dir}_{first.x}_{first.y}.png");
        Png.Write(png, pixels, w, h);
        Console.WriteLine($"tile {first.x},{first.y} (fdid {first.fdid}) {w}x{h} -> {png}");
    }

    /// <summary>The map's id, directory and MAID minimap tiles (x, y, FileDataID), sorted by x then y.</summary>
    public static (int id, string dir, List<(int x, int y, uint fdid)> tiles) ListTiles(Client c, string defsDir,
        string map, string? wdtFdidArg, string? listfile)
    {
        var (id, dir) = ResolveMap(c, defsDir, map);
        Console.WriteLine($"map {id} directory '{dir}'");
        var wdtPath = $"world/maps/{dir}/{dir}.wdt";
        var wdtFdid = wdtFdidArg != null ? uint.Parse(wdtFdidArg)
            : (listfile != null ? FromListfile(listfile, wdtPath) : null) ?? c.FindFdidByName(wdtPath);
        Console.WriteLine($"{wdtPath}: " + (wdtFdid?.ToString() ?? "no FileDataID (pass --wdt-fdid or --listfile)"));
        var tiles = new List<(int x, int y, uint fdid)>();
        if (wdtFdid != null)
            tiles = ReadMaid(c.ReadFdid(wdtFdid.Value));
        Console.WriteLine($"MAID minimap tiles: {tiles.Count}");
        if (tiles.Count == 0)
            throw new InvalidOperationException("no minimap tile list found for this map (see docs/data/client-extraction.md)");
        tiles.Sort((a, b) => a.x != b.x ? a.x.CompareTo(b.x) : a.y.CompareTo(b.y));
        return (id, dir, tiles);
    }

    /// <summary>The community listfile is "fdid;path" per line.</summary>
    static uint? FromListfile(string file, string path)
    {
        var suffix = ";" + path;
        foreach (var line in File.ReadLines(file))
            if (line.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
                return uint.Parse(line[..line.IndexOf(';')]);
        return null;
    }

    static (int id, string dir) ResolveMap(Client c, string defsDir, string map)
    {
        var storage = Db2.Load(c, defsDir, "Map");
        foreach (var key in storage.Keys)
        {
            var row = storage[key];
            var dir = (string?)row["Directory"] ?? "";
            if (key.ToString() == map || dir.Equals(map, StringComparison.OrdinalIgnoreCase)
                || ((string?)row["MapName_lang"] ?? "").Equals(map, StringComparison.OrdinalIgnoreCase))
                return (key, dir);
        }
        throw new ArgumentException("map not found in Map.db2: " + map);
    }

    /// <summary>Chunks are 4 reversed-ASCII bytes plus a uint32 size. MAID holds 64*64 records of 8 uint32.</summary>
    static List<(int x, int y, uint fdid)> ReadMaid(byte[] wdt)
    {
        var tiles = new List<(int, int, uint)>();
        for (var p = 0; p + 8 <= wdt.Length;)
        {
            var magic = new string([(char)wdt[p + 3], (char)wdt[p + 2], (char)wdt[p + 1], (char)wdt[p]]);
            var size = BitConverter.ToInt32(wdt, p + 4);
            if (magic == "MAID")
            {
                for (var i = 0; i < 64 * 64 && (i + 1) * 32 <= size; i++)
                {
                    var minimap = BitConverter.ToUInt32(wdt, p + 8 + i * 32 + 28);
                    if (minimap != 0) tiles.Add((i % 64, i / 64, minimap)); // x/y order is an assumption, see doc
                }
            }
            p += 8 + size;
        }
        return tiles;
    }
}
