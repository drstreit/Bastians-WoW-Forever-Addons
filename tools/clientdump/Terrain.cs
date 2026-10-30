// The walkable ground of one map for the route network (ADR 0025): every ADT tile's terrain as cells of
// 1/8 chunk (4.17 yards), with the ground height, the steepest slope, holes, liquid and the weight of the
// ground textures named in a road list. Reads the root ADT (MCNK heights and holes, MH2O liquid) and the
// tex0 ADT (MDID textures, MCLY layers, MCAL alpha) by the FileDataIDs of the WDT's MAID chunk; buildings
// and doodads (obj0) are not read: bridges, tunnels and city interiors come from the connector table.
//
// Output, gzip: "BTER" u32 version (1), i32 tiles; per tile i32 x, i32 y, then 128 x 128 cells row-major
// (row = world north to south, col = world west to east inside the tile, as the minimap tile), each
// i16 height (yards, rounded), u8 slope (degrees), u8 flags (1 hole, 2 liquid, 4 deep, 8 no terrain),
// u16 liquid type (LiquidType.db2), i16 liquid surface (yards), u8 road weight (0..255).
// Beside it "<dir>_textures.tsv": fdid, cells covered (sum of weights / 255), for picking road textures.
using System.IO.Compression;

namespace ClientDump;

static class Terrain
{
    const int Cells = 128; // per tile side: 16 chunks x 8 cells
    const double ChunkYards = 1600.0 / 3 / 16;
    const double CellYards = ChunkYards / 8;

    public static void Run(Client c, string defsDir, string map, string outDir, string? wdtFdidArg,
        string? listfile, string? roadsFile, string? tileArg)
    {
        var (_, dir, _) = Minimap.ListTiles(c, defsDir, map, wdtFdidArg, listfile);
        var wdtFdid = uint.Parse(wdtFdidArg ?? throw new ArgumentException("--wdt-fdid is required"));
        var wdt = c.ReadFdid(wdtFdid);
        var (mphd, maid) = ReadWdt(wdt);
        var bigAlpha = (mphd & 0x4) != 0 || (mphd & 0x80) != 0;
        var roads = roadsFile != null
            ? File.ReadLines(roadsFile).Select(l => l.Split('\t', ';', ',')[0].Trim())
                .Where(s => uint.TryParse(s, out _)).Select(uint.Parse).ToHashSet()
            : [];
        var tiles = maid.Where(t => t.root != 0).ToList();
        if (tileArg != null)
        {
            var xy = tileArg.Split(',');
            tiles = tiles.Where(t => t.x == int.Parse(xy[0]) && t.y == int.Parse(xy[1])).ToList();
        }
        Console.WriteLine($"terrain: {tiles.Count} tiles, big alpha {bigAlpha}, {roads.Count} road textures");
        Directory.CreateDirectory(outDir);
        var usage = new Dictionary<uint, double>();
        var path = Path.Combine(outDir, $"{dir}_terrain.bin.gz");
        var tmp = path + ".tmp";
        var missing = 0;
        using (var file = File.Create(tmp))
        using (var gz = new GZipStream(file, CompressionLevel.Optimal))
        using (var w = new BinaryWriter(gz))
        {
            w.Write("BTER"u8.ToArray());
            w.Write(1u);
            w.Write(tiles.Count);
            foreach (var t in tiles)
            {
                var grid = new Cell[Cells * Cells];
                for (var i = 0; i < grid.Length; i++) grid[i].Flags = 8;
                try
                {
                    ReadRoot(c.ReadFdid(t.root), grid);
                    if (t.tex0 != 0) ReadTex(c.ReadFdid(t.tex0), grid, bigAlpha, roads, usage);
                }
                catch (Exception e)
                {
                    missing++;
                    Console.Error.WriteLine($"warning: tile {t.x},{t.y}: {e.Message}");
                }
                w.Write(t.x);
                w.Write(t.y);
                foreach (var cell in grid)
                {
                    w.Write((short)Math.Clamp(Math.Round(cell.Height), short.MinValue, short.MaxValue));
                    w.Write((byte)Math.Clamp(Math.Round(cell.Slope), 0, 90));
                    w.Write(cell.Flags);
                    w.Write(cell.LiquidType);
                    w.Write((short)Math.Clamp(Math.Round(cell.Surface), short.MinValue, short.MaxValue));
                    w.Write((byte)Math.Clamp(Math.Round(cell.Road * 255), 0, 255));
                }
            }
        }
        File.Move(tmp, path, true);
        var tsv = Path.Combine(outDir, $"{dir}_textures.tsv");
        File.WriteAllLines(tsv, usage.OrderByDescending(kv => kv.Value)
            .Select(kv => $"{kv.Key}\t{Math.Round(kv.Value)}"));
        Console.WriteLine($"-> {path} ({tiles.Count - missing} tiles read, {missing} failed); textures -> {tsv}");
    }

    internal struct Cell
    {
        public double Height, Slope, Surface, Road;
        public byte Flags;
        public ushort LiquidType;
    }

    /// <summary>MPHD flags and the MAID records: per tile the root ADT and the tex0 ADT FileDataIDs.</summary>
    static (uint mphd, List<(int x, int y, uint root, uint tex0)>) ReadWdt(byte[] wdt)
    {
        uint mphd = 0;
        var tiles = new List<(int, int, uint, uint)>();
        foreach (var (magic, start, size) in Chunks(wdt, 0, wdt.Length))
        {
            if (magic == "MPHD") mphd = BitConverter.ToUInt32(wdt, start);
            if (magic != "MAID") continue;
            for (var i = 0; i < 64 * 64 && (i + 1) * 32 <= size; i++)
            {
                var o = start + i * 32;
                // rootADT, obj0, obj1, tex0, lod, mapTexture, mapTextureN, minimapTexture
                var root = BitConverter.ToUInt32(wdt, o);
                var tex0 = BitConverter.ToUInt32(wdt, o + 12);
                if (root != 0) tiles.Add((i % 64, i / 64, root, tex0));
            }
        }
        return (mphd, tiles);
    }

    internal static IEnumerable<(string magic, int start, int size)> Chunks(byte[] b, int from, int to)
    {
        for (var p = from; p + 8 <= to;)
        {
            var magic = new string([(char)b[p + 3], (char)b[p + 2], (char)b[p + 1], (char)b[p]]);
            var size = BitConverter.ToInt32(b, p + 4);
            if (size < 0 || p + 8 + size > to) yield break;
            yield return (magic, p + 8, size);
            p += 8 + size;
        }
    }

    static void ReadRoot(byte[] adt, Cell[] grid)
    {
        var chunk = 0;
        foreach (var (magic, start, size) in Chunks(adt, 0, adt.Length))
        {
            if (magic == "MCNK") ReadMcnk(adt, start, size, grid, chunk++);
            else if (magic == "MH2O") ReadLiquid(adt, start, grid);
        }
    }

    /// <summary>One chunk: the 9x9 outer and 8x8 inner heights (MCVT), the holes; slope per cell from the
    /// four triangles centre-corner-corner.</summary>
    static void ReadMcnk(byte[] b, int start, int size, Cell[] grid, int order)
    {
        var flags = BitConverter.ToUInt32(b, start);
        var ix = (int)BitConverter.ToUInt32(b, start + 0x04);
        var iy = (int)BitConverter.ToUInt32(b, start + 0x08);
        if (ix > 15 || iy > 15) { ix = order % 16; iy = order / 16; }
        var holesHigh = BitConverter.ToUInt64(b, start + 0x14);
        var holesLow = BitConverter.ToUInt16(b, start + 0x3C);
        var baseZ = BitConverter.ToSingle(b, start + 0x68 + 8);
        float[]? v = null;
        foreach (var (magic, s, n) in Chunks(b, start + 0x80, start + size))
        {
            if (magic != "MCVT" || n < 145 * 4) continue;
            v = new float[145];
            for (var i = 0; i < 145; i++) v[i] = BitConverter.ToSingle(b, s + i * 4) + baseZ;
        }
        if (v == null) return;
        double Outer(int r, int col) => v[r * 17 + col];
        double Inner(int r, int col) => v[r * 17 + 9 + col];
        var half = CellYards / 2;
        for (var r = 0; r < 8; r++)
        for (var col = 0; col < 8; col++)
        {
            var hole = (flags & 0x10000) != 0
                ? ((holesHigh >> (r * 8 + col)) & 1) != 0
                : ((holesLow >> ((r / 2) * 4 + col / 2)) & 1) != 0;
            double cz = Inner(r, col), a = Outer(r, col), bb = Outer(r, col + 1);
            double cc = Outer(r + 1, col + 1), d = Outer(r + 1, col);
            // corners relative to the centre: a (-h,-h), b (-h,+h), c (+h,+h), d (+h,-h) as (row, col)
            var slope = Math.Max(Math.Max(Tri(cz, -half, -half, a, -half, half, bb),
                    Tri(cz, -half, half, bb, half, half, cc)),
                Math.Max(Tri(cz, half, half, cc, half, -half, d), Tri(cz, half, -half, d, -half, -half, a)));
            ref var cell = ref grid[(iy * 8 + r) * Cells + ix * 8 + col];
            cell.Height = cz;
            cell.Slope = slope;
            cell.Flags = (byte)((cell.Flags & ~8 & 0xff) | (hole ? 1 : 0));
        }
    }

    /// <summary>Slope in degrees of the triangle (0,0,z0), (r1,c1,z1), (r2,c2,z2).</summary>
    static double Tri(double z0, double r1, double c1, double z1, double r2, double c2, double z2)
    {
        double ux = r1, uy = c1, uz = z1 - z0, vx = r2, vy = c2, vz = z2 - z0;
        double nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
        var len = Math.Sqrt(nx * nx + ny * ny + nz * nz);
        return len == 0 ? 0 : Math.Acos(Math.Abs(nz) / len) * 180 / Math.PI;
    }

    /// <summary>MH2O: 256 headers (instances offset, layer count, attributes offset), offsets from the data
    /// start. The surface is the instance's max height level (vertex data is not read).</summary>
    static void ReadLiquid(byte[] b, int start, Cell[] grid)
    {
        for (var chunk = 0; chunk < 256; chunk++)
        {
            var h = start + chunk * 12;
            var ofsInst = BitConverter.ToInt32(b, h);
            var layers = BitConverter.ToInt32(b, h + 4);
            var ofsAttr = BitConverter.ToInt32(b, h + 8);
            if (ofsInst == 0 || layers <= 0) continue;
            ulong deep = ofsAttr != 0 ? BitConverter.ToUInt64(b, start + ofsAttr + 8) : 0;
            int ix = chunk % 16, iy = chunk / 16;
            for (var l = 0; l < layers; l++)
            {
                var o = start + ofsInst + l * 24;
                var type = BitConverter.ToUInt16(b, o);
                var maxH = BitConverter.ToSingle(b, o + 8);
                int xo = b[o + 12], yo = b[o + 13], wd = b[o + 14], ht = b[o + 15];
                var ofsExists = BitConverter.ToInt32(b, o + 16);
                for (var y = 0; y < ht; y++)
                for (var x = 0; x < wd; x++)
                {
                    if (ofsExists != 0)
                    {
                        var bit = y * wd + x;
                        if (((b[start + ofsExists + bit / 8] >> (bit % 8)) & 1) == 0) continue;
                    }
                    int r = yo + y, col = xo + x;
                    if (r > 7 || col > 7) continue;
                    ref var cell = ref grid[(iy * 8 + r) * Cells + ix * 8 + col];
                    if ((cell.Flags & 2) != 0 && cell.Surface >= maxH) continue; // keep the upper layer
                    cell.LiquidType = type;
                    cell.Surface = maxH;
                    var isDeep = ((deep >> (r * 8 + col)) & 1) != 0;
                    cell.Flags = (byte)((cell.Flags | 2) & ~4 | (isDeep ? 4 : 0));
                }
            }
        }
    }

    /// <summary>tex0: MDID (texture FileDataIDs), then 256 MCNK containers with MCLY layers and MCAL alpha.
    /// A layer's weight per cell is its alpha averaged over the cell's 8x8 alpha pixels; the base layer gets
    /// what the others leave.</summary>
    internal static void ReadTex(byte[] b, Cell[] grid, bool bigAlpha, HashSet<uint> roads, Dictionary<uint, double> usage)
    {
        var textures = new List<uint>();
        var chunk = 0;
        foreach (var (magic, start, size) in Chunks(b, 0, b.Length))
        {
            if (magic == "MDID")
                for (var i = 0; i + 4 <= size; i += 4) textures.Add(BitConverter.ToUInt32(b, start + i));
            if (magic != "MCNK") continue;
            int ix = chunk % 16, iy = chunk / 16;
            chunk++;
            var layers = new List<(uint tex, uint flags, int ofs)>();
            int mcal = -1, mcalSize = 0;
            foreach (var (m, s, n) in Chunks(b, start, start + size))
            {
                if (m == "MCLY")
                    for (var i = 0; i + 16 <= n; i += 16)
                        layers.Add((BitConverter.ToUInt32(b, s + i), BitConverter.ToUInt32(b, s + i + 4),
                            BitConverter.ToInt32(b, s + i + 8)));
                if (m == "MCAL") { mcal = s; mcalSize = n; }
            }
            if (layers.Count == 0) continue;
            var weights = new double[layers.Count, 64];
            var rest = new double[64];
            Array.Fill(rest, 1.0);
            for (var l = 1; l < layers.Count; l++)
            {
                if ((layers[l].flags & 0x100) == 0 || mcal < 0) continue;
                var alpha = Alpha(b, mcal + layers[l].ofs, mcal + mcalSize, layers[l].flags, bigAlpha);
                for (var cell = 0; cell < 64; cell++)
                {
                    double sum = 0;
                    int r = cell / 8, col = cell % 8;
                    for (var py = 0; py < 8; py++)
                    for (var px = 0; px < 8; px++)
                        sum += alpha[(r * 8 + py) * 64 + col * 8 + px];
                    weights[l, cell] = sum / 64 / 255;
                    rest[cell] -= weights[l, cell];
                }
            }
            for (var cell = 0; cell < 64; cell++) weights[0, cell] = Math.Max(0, rest[cell]);
            for (var l = 0; l < layers.Count; l++)
            {
                var idx = (int)layers[l].tex;
                var fdid = idx < textures.Count ? textures[idx] : 0;
                double total = 0;
                for (var cell = 0; cell < 64; cell++) total += weights[l, cell];
                usage[fdid] = usage.GetValueOrDefault(fdid) + total;
                if (!roads.Contains(fdid)) continue;
                for (var cell = 0; cell < 64; cell++)
                    grid[(iy * 8 + cell / 8) * Cells + ix * 8 + cell % 8].Road += weights[l, cell];
            }
        }
    }

    /// <summary>One layer's 64x64 alpha map: compressed (flag 0x200, RLE), 8-bit (big alpha) or 4-bit.</summary>
    internal static byte[] Alpha(byte[] b, int p, int end, uint flags, bool bigAlpha)
    {
        var a = new byte[4096];
        if ((flags & 0x200) != 0)
        {
            var o = 0;
            while (o < 4096 && p < end)
            {
                var head = b[p++];
                var count = head & 0x7F;
                if ((head & 0x80) != 0)
                {
                    var value = p < end ? b[p++] : (byte)0;
                    for (var i = 0; i < count && o < 4096; i++) a[o++] = value;
                }
                else
                    for (var i = 0; i < count && o < 4096 && p < end; i++) a[o++] = b[p++];
            }
        }
        else if (bigAlpha)
            Array.Copy(b, p, a, 0, Math.Min(4096, end - p));
        else
            for (var i = 0; i < 2048 && p + i < end; i++)
            {
                a[i * 2] = (byte)((b[p + i] & 0x0F) * 17);
                a[i * 2 + 1] = (byte)((b[p + i] >> 4) * 17);
            }
        return a;
    }
}
