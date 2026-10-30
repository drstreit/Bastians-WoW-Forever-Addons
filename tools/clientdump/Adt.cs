// The parts of an ADT tile the navmesh needs (ADR 0026, world-graph.md §6.1): the terrain vertices and holes of
// every MCNK (root ADT), the liquid surfaces (MH2O, per 4.17-yard cell), the road texture weight per cell (tex0,
// through Terrain.ReadTex) and the object placements (obj0: MDDF doodads, MODF WMOs).
//
// Frames. World yards: wx north, wy west, wz up (the client's own). The navmesh frame ("recast frame", y up):
// rx = 32 * 533.33 - wy (east), ry = wz, rz = 32 * 533.33 - wx (south). It is a proper rotation of the world
// frame, so triangle winding survives, and it is exactly the ADT placement frame of MDDF/MODF (position x, y, z),
// and ADT tile (x, y) covers rx in [x, x + 1) * 533.33 and rz in [y, y + 1) * 533.33.
using System.Numerics;

namespace ClientDump;

static class Frame
{
    public const double Tile = 1600.0 / 3;
    public const double Chunk = Tile / 16;
    public const double Unit = Chunk / 8;
    public const double Origin = 32 * Tile;

    public static (double rx, double ry, double rz) FromWorld(double wx, double wy, double wz) =>
        (Origin - wy, wz, Origin - wx);

    public static (double wx, double wy, double wz) ToWorld(double rx, double ry, double rz) =>
        (Origin - rz, Origin - rx, ry);
}

/// <summary>One liquid surface triangle in the recast frame, with its LiquidType id.</summary>
readonly record struct LiquidTri(Vector3 A, Vector3 B, Vector3 C, int Type);

/// <summary>An object placement of obj0 (or a WMO's doodad, then Wmo is false and the transform is already the
/// doodad's full one, see Navmesh). Position and extents are in the placement (= recast) frame.</summary>
readonly record struct Placement(bool Wmo, uint Fdid, uint UniqueId, Vector3 Pos, Vector3 Rot, float Scale,
    ushort DoodadSet, ushort Flags, Vector3 ExtMin, Vector3 ExtMax);

sealed class AdtTile
{
    public int X, Y;
    public readonly float[]?[] Heights = new float[256][]; // per chunk 145 absolute heights (9x9 outer, 8x8 inner)
    public readonly ulong[] Holes = new ulong[256];        // per chunk bit r * 8 + c = hole
    public readonly uint[] AreaIds = new uint[256];        // per chunk the AreaTable id (MCNK 0x34), 0 = none
    public readonly float[] Road = new float[128 * 128];   // road texture weight per cell, row-major (rz, rx)
    public readonly List<LiquidTri> Liquids = [];
    public readonly List<Placement> Placements = [];
    public int UnnamedDoodads, UnnamedWmos;                // placements by file name that did not resolve
    public string? Error;
}

static class Adt
{
    /// <summary>MAID: per tile the root, obj0 and tex0 FileDataIDs; MPHD flags.</summary>
    public static (uint mphd, Dictionary<(int x, int y), (uint root, uint obj0, uint tex0)>) ReadWdt(byte[] wdt)
    {
        uint mphd = 0;
        var tiles = new Dictionary<(int, int), (uint, uint, uint)>();
        foreach (var (magic, start, size) in Terrain.Chunks(wdt, 0, wdt.Length))
        {
            if (magic == "MPHD") mphd = BitConverter.ToUInt32(wdt, start);
            if (magic != "MAID") continue;
            for (var i = 0; i < 64 * 64 && (i + 1) * 32 <= size; i++)
            {
                var o = start + i * 32;
                var root = BitConverter.ToUInt32(wdt, o);
                if (root != 0)
                    tiles[(i % 64, i / 64)] = (root, BitConverter.ToUInt32(wdt, o + 4), BitConverter.ToUInt32(wdt, o + 12));
            }
        }
        return (mphd, tiles);
    }

    public static void ReadRoot(byte[] adt, AdtTile t)
    {
        var chunk = 0;
        foreach (var (magic, start, size) in Terrain.Chunks(adt, 0, adt.Length))
        {
            if (magic == "MCNK") ReadMcnk(adt, start, size, t, chunk++);
            else if (magic == "MH2O") ReadLiquid(adt, start, t);
        }
    }

    static void ReadMcnk(byte[] b, int start, int size, AdtTile t, int order)
    {
        var flags = BitConverter.ToUInt32(b, start);
        var ix = (int)BitConverter.ToUInt32(b, start + 0x04);
        var iy = (int)BitConverter.ToUInt32(b, start + 0x08);
        if (ix > 15 || iy > 15) { ix = order % 16; iy = order / 16; }
        var holesHigh = BitConverter.ToUInt64(b, start + 0x14);
        var holesLow = BitConverter.ToUInt16(b, start + 0x3C);
        t.AreaIds[iy * 16 + ix] = BitConverter.ToUInt32(b, start + 0x34);
        var baseZ = BitConverter.ToSingle(b, start + 0x68 + 8);
        foreach (var (magic, s, n) in Terrain.Chunks(b, start + 0x80, start + size))
        {
            if (magic != "MCVT" || n < 145 * 4) continue;
            var v = new float[145];
            for (var i = 0; i < 145; i++) v[i] = BitConverter.ToSingle(b, s + i * 4) + baseZ;
            t.Heights[iy * 16 + ix] = v;
        }
        ulong holes = 0;
        for (var r = 0; r < 8; r++)
        for (var c = 0; c < 8; c++)
        {
            var hole = (flags & 0x10000) != 0
                ? ((holesHigh >> (r * 8 + c)) & 1) != 0
                : ((holesLow >> ((r / 2) * 4 + c / 2)) & 1) != 0;
            if (hole) holes |= 1UL << (r * 8 + c);
        }
        t.Holes[iy * 16 + ix] = holes;
    }

    /// <summary>MH2O: per chunk the liquid instances; per existing cell two triangles at the instance's vertex
    /// heights. The vertex block holds heights first for the vertex formats that have them (0, 1, 3); format 2
    /// (depth only, the sea) has none. The format is not read (it needs LiquidObject.db2): heights are used
    /// when they all lie within the instance's min and max height, otherwise the surface is flat at max.</summary>
    static void ReadLiquid(byte[] b, int start, AdtTile t)
    {
        for (var chunk = 0; chunk < 256; chunk++)
        {
            var h = start + chunk * 12;
            var ofsInst = BitConverter.ToInt32(b, h);
            var layers = BitConverter.ToInt32(b, h + 4);
            if (ofsInst == 0 || layers <= 0) continue;
            int ix = chunk % 16, iy = chunk / 16;
            for (var l = 0; l < layers; l++)
            {
                var o = start + ofsInst + l * 24;
                var type = BitConverter.ToUInt16(b, o);
                var minH = BitConverter.ToSingle(b, o + 4);
                var maxH = BitConverter.ToSingle(b, o + 8);
                int xo = b[o + 12], yo = b[o + 13], wd = b[o + 14], ht = b[o + 15];
                var ofsExists = BitConverter.ToInt32(b, o + 16);
                var ofsVerts = BitConverter.ToInt32(b, o + 20);
                if (wd == 0 || ht == 0 || xo + wd > 8 || yo + ht > 8) continue;
                float[]? hv = null;
                if (ofsVerts != 0 && start + ofsVerts + (wd + 1) * (ht + 1) * 4 <= b.Length)
                {
                    hv = new float[(wd + 1) * (ht + 1)];
                    for (var i = 0; i < hv.Length; i++)
                    {
                        hv[i] = BitConverter.ToSingle(b, start + ofsVerts + i * 4);
                        if (!float.IsFinite(hv[i]) || hv[i] < minH - 1 || hv[i] > maxH + 1) { hv = null; break; }
                    }
                }
                float H(int x, int y) => hv?[y * (wd + 1) + x] ?? maxH;
                for (var y = 0; y < ht; y++)
                for (var x = 0; x < wd; x++)
                {
                    if (ofsExists != 0)
                    {
                        var bit = y * wd + x;
                        if (((b[start + ofsExists + bit / 8] >> (bit % 8)) & 1) == 0) continue;
                    }
                    var x0 = (float)((t.X * 16 + ix) * Frame.Chunk + (xo + x) * Frame.Unit);
                    var z0 = (float)((t.Y * 16 + iy) * Frame.Chunk + (yo + y) * Frame.Unit);
                    var u = (float)Frame.Unit;
                    var a = new Vector3(x0, H(x, y), z0);
                    var bb = new Vector3(x0 + u, H(x + 1, y), z0);
                    var c = new Vector3(x0 + u, H(x + 1, y + 1), z0 + u);
                    var d = new Vector3(x0, H(x, y + 1), z0 + u);
                    t.Liquids.Add(new LiquidTri(a, c, bb, type));
                    t.Liquids.Add(new LiquidTri(a, d, c, type));
                }
            }
        }
    }

    /// <summary>obj0: MDDF (36 bytes: name id, unique id, position, rotation in degrees, scale / 1024, flags; flag
    /// 0x40 = the name id is a FileDataID) and MODF (64 bytes: name id, unique id, position, rotation, extents,
    /// flags, doodad set, name set, scale / 1024; flag 0x8 = FileDataID, 0x4 = has scale). Otherwise the name id
    /// indexes MMID/MWID into the MMDX/MWMO names, resolved with <paramref name="byName"/>.</summary>
    public static void ReadObj(byte[] b, AdtTile t, Func<string, uint?> byName)
    {
        byte[]? mmdx = null, mwmo = null;
        var mmid = new List<int>();
        var mwid = new List<int>();
        foreach (var (magic, s, n) in Terrain.Chunks(b, 0, b.Length))
        {
            switch (magic)
            {
                case "MMDX": mmdx = b[s..(s + n)]; break;
                case "MWMO": mwmo = b[s..(s + n)]; break;
                case "MMID": for (var i = 0; i + 4 <= n; i += 4) mmid.Add(BitConverter.ToInt32(b, s + i)); break;
                case "MWID": for (var i = 0; i + 4 <= n; i += 4) mwid.Add(BitConverter.ToInt32(b, s + i)); break;
                case "MDDF":
                    for (var o = s; o + 36 <= s + n; o += 36)
                    {
                        var flags = BitConverter.ToUInt16(b, o + 34);
                        var id = BitConverter.ToUInt32(b, o);
                        uint? fdid = (flags & 0x40) != 0 ? id : Name(mmdx, mmid, (int)id, byName);
                        if (fdid is null or 0) { t.UnnamedDoodads++; continue; }
                        t.Placements.Add(new Placement(false, fdid.Value, BitConverter.ToUInt32(b, o + 4), V3(b, o + 8),
                            V3(b, o + 20), BitConverter.ToUInt16(b, o + 32) / 1024f, 0, flags, default, default));
                    }
                    break;
                case "MODF":
                    for (var o = s; o + 64 <= s + n; o += 64)
                    {
                        var flags = BitConverter.ToUInt16(b, o + 56);
                        var id = BitConverter.ToUInt32(b, o);
                        uint? fdid = (flags & 0x8) != 0 ? id : Name(mwmo, mwid, (int)id, byName);
                        if (fdid is null or 0) { t.UnnamedWmos++; continue; }
                        var scale = (flags & 0x4) != 0 ? BitConverter.ToUInt16(b, o + 62) / 1024f : 1f;
                        t.Placements.Add(new Placement(true, fdid.Value, BitConverter.ToUInt32(b, o + 4), V3(b, o + 8),
                            V3(b, o + 20), scale, BitConverter.ToUInt16(b, o + 58), flags, V3(b, o + 32), V3(b, o + 44)));
                    }
                    break;
            }
        }
    }

    static uint? Name(byte[]? names, List<int> offsets, int index, Func<string, uint?> byName)
    {
        if (names == null || index < 0 || index >= offsets.Count) return null;
        var o = offsets[index];
        var end = Array.IndexOf(names, (byte)0, o);
        if (o < 0 || o >= names.Length) return null;
        var name = System.Text.Encoding.ASCII.GetString(names, o, (end < 0 ? names.Length : end) - o);
        // ADTs name the .mdx/.mdl of old; the client file is the .m2
        if (name.EndsWith(".mdx", StringComparison.OrdinalIgnoreCase) || name.EndsWith(".mdl", StringComparison.OrdinalIgnoreCase))
            name = name[..^4] + ".m2";
        return byName(name);
    }

    public static Vector3 V3(byte[] b, int o) =>
        new(BitConverter.ToSingle(b, o), BitConverter.ToSingle(b, o + 4), BitConverter.ToSingle(b, o + 8));
}
