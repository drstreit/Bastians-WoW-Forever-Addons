// The rooms of the placed WMOs for the city plans (map.md "City plans"): per placement its groups (with the id
// WMOAreaTable names them by), the portals between them (a portal to an outdoor group is a door) and each group's
// triangles in world yards. Formats as Wmo.cs, plus (wowdev.wiki): MOHD wmoID at 32; MOGN group names; MOPV portal
// vertices; MOPT (20 bytes: first vertex u16, count u16, plane); MOPR (8 bytes: portal u16, other group u16, side
// i16, pad); MOGP name offset at 0, description offset at 4, portal start u16 at 0x24, portal count u16 at 0x26,
// unique id (WMOAreaTable.WMOGroupID) at 0x38. For drawing, <unique>.mesh per group: MOTV uv (first set), MOCV colours
// (first set, BGRA), the material of each kept triangle (MOPY), and MLIQ (x verts, y verts, x tiles, y tiles, corner,
// material u16; 8 bytes per vertex with the height at +4; a byte per tile, low nibble 15 = no liquid; tiles 4.1666 yards).
using System.Numerics;
using System.Text.Json;

namespace ClientDump;

static class WmoRooms
{
    sealed record Liquid(int XVerts, int YVerts, int XTiles, int YTiles, Vector3 Corner, float[] Heights, byte[] Tiles);

    sealed record Group(int Index, uint Id, uint Flags, string Name, string Description,
        List<(int portal, int other, int side)> Portals, float[] Verts, int[] Tris,
        float[] Uv, byte[] Colours, ushort[] Materials, Liquid? Liquid);

    const float LiquidTile = 533.33333f / 128;

    public static void Run(Client c, string defsDir, string map, string outDir, string? wdtFdidArg, string? listfile,
        string tilesArg)
    {
        var (mapId, dir) = Minimap.ResolveMap(c, defsDir, map);
        var wdtFdid = uint.Parse(wdtFdidArg ?? throw new ArgumentException("--wdt-fdid is required"));
        var (_, maid) = Adt.ReadWdt(c.ReadFdid(wdtFdid));
        var r = tilesArg.Split(',').Select(int.Parse).ToArray();
        if (r.Length != 4) throw new ArgumentException("--tiles wants x0,y0,x1,y1");

        byte[]? Read(uint fdid)
        {
            if (fdid == 0) return null;
            try { return c.ReadFdid(fdid); }
            catch (Exception) { return null; }
        }

        var placements = new SortedDictionary<uint, Placement>();
        foreach (var (k, ids) in maid.Where(e => e.Key.x >= r[0] && e.Key.x <= r[2] && e.Key.y >= r[1] && e.Key.y <= r[3]))
        {
            var ob = Read(ids.obj0);
            if (ob == null) continue;
            var t = new AdtTile { X = k.x, Y = k.y };
            Adt.ReadObj(ob, t, name => c.FindFdidByName(name));
            foreach (var p in t.Placements.Where(p => p.Wmo)) placements[p.UniqueId] = p;
        }

        // an instance map has no terrain: its one WMO is placed in the WDT itself, in the same MWMO/MODF chunks
        var global = new AdtTile { X = 0, Y = 0 };
        Adt.ReadObj(c.ReadFdid(wdtFdid), global, name => c.FindFdidByName(name));
        foreach (var p in global.Placements.Where(p => p.Wmo)) placements[p.UniqueId] = p;

        Directory.CreateDirectory(outDir);
        using var stream = File.Create(Path.Combine(outDir, "rooms.json"));
        using var w = new Utf8JsonWriter(stream);
        w.WriteStartObject();
        w.WriteNumber("map", mapId);
        w.WriteString("directory", dir);
        w.WriteStartArray("placements");
        var groups = 0;
        foreach (var (unique, p) in placements)
            groups += WritePlacement(w, unique, p, Read, outDir, name => c.FindFdidByName(name));
        w.WriteEndArray();
        w.WriteEndObject();
        Console.WriteLine($"wmo-rooms: map {mapId} {dir}, {placements.Count} placements, {groups} groups -> {outDir}");
    }

    static int WritePlacement(Utf8JsonWriter w, uint unique, Placement p, Func<uint, byte[]?> read, string outDir,
        Func<string, uint?> byName)
    {
        byte[] motx = [];
        var materials = new List<uint>();
        var b = read(p.Fdid);
        if (b == null) return 0;
        var gfid = new List<uint>();
        var count = 0;
        uint wmoId = 0;
        byte[] mogn = [];
        var portalVerts = new List<Vector3>();
        var portals = new List<(int first, int count)>();
        var refs = new List<(int portal, int other, int side)>();
        foreach (var (magic, s, n) in Terrain.Chunks(b, 0, b.Length))
        {
            switch (magic)
            {
                case "MOHD": count = BitConverter.ToInt32(b, s + 4); wmoId = BitConverter.ToUInt32(b, s + 32); break;
                case "GFID": for (var i = 0; i + 4 <= n; i += 4) gfid.Add(BitConverter.ToUInt32(b, s + i)); break;
                case "MOGN": mogn = b[s..(s + n)]; break;
                case "MOTX": motx = b[s..(s + n)]; break;
                case "MOMT":
                    for (var i = 0; i + 64 <= n; i += 64) materials.Add(BitConverter.ToUInt32(b, s + i + 12));
                    break;
                case "MOPV": for (var i = 0; i + 12 <= n; i += 12) portalVerts.Add(Adt.V3(b, s + i)); break;
                case "MOPT":
                    for (var i = 0; i + 20 <= n; i += 20)
                        portals.Add((BitConverter.ToUInt16(b, s + i), BitConverter.ToUInt16(b, s + i + 2)));
                    break;
                case "MOPR":
                    for (var i = 0; i + 8 <= n; i += 8)
                        refs.Add((BitConverter.ToUInt16(b, s + i), BitConverter.ToUInt16(b, s + i + 2),
                            BitConverter.ToInt16(b, s + i + 4)));
                    break;
            }
        }

        var xf = Navmesh.PlacementXf(p);
        Vector3 World(Vector3 v)
        {
            var q = xf.M.Mul(v) + xf.T;
            var (wx, wy, wz) = Frame.ToWorld(q.X, q.Y, q.Z);
            return new Vector3((float)wx, (float)wy, (float)wz);
        }

        var list = new List<Group>();
        for (var g = 0; g < Math.Min(count, gfid.Count); g++)
        {
            var gb = read(gfid[g]);
            if (gb != null && ReadGroup(gb, g, mogn, refs) is { } group) list.Add(group);
        }

        // MOMT's first texture: an offset into MOTX on old files, a FileDataID on new ones
        uint Texture(uint t)
        {
            if (motx.Length == 0 || t >= motx.Length) return t;
            var name = Text(motx, (int)t);
            return name.Length == 0 ? 0 : byName(name) ?? 0;
        }

        w.WriteStartObject();
        w.WriteNumber("unique", unique);
        w.WriteNumber("fdid", p.Fdid);
        w.WriteNumber("wmoId", wmoId);
        w.WriteStartArray("pos");
        var (px, py, pz) = Frame.ToWorld(p.Pos.X, p.Pos.Y, p.Pos.Z);
        w.WriteNumberValue(Math.Round(px, 2)); w.WriteNumberValue(Math.Round(py, 2)); w.WriteNumberValue(Math.Round(pz, 2));
        w.WriteEndArray();
        w.WriteStartArray("materials");
        foreach (var t in materials) w.WriteNumberValue(Texture(t));
        w.WriteEndArray();
        w.WriteStartArray("portals");
        foreach (var (first, n) in portals)
        {
            w.WriteStartArray();
            for (var i = first; i < first + n && i < portalVerts.Count; i++)
            {
                var v = World(portalVerts[i]);
                w.WriteStartArray();
                w.WriteNumberValue(Math.Round(v.X, 2)); w.WriteNumberValue(Math.Round(v.Y, 2)); w.WriteNumberValue(Math.Round(v.Z, 2));
                w.WriteEndArray();
            }
            w.WriteEndArray();
        }
        w.WriteEndArray();
        w.WriteStartArray("groups");
        using var mesh = new BinaryWriter(File.Create(Path.Combine(outDir, unique + ".bin")));
        using var extra = new BinaryWriter(File.Create(Path.Combine(outDir, unique + ".mesh")));
        foreach (var g in list)
        {
            w.WriteStartObject();
            w.WriteNumber("i", g.Index);
            w.WriteNumber("id", g.Id);
            w.WriteNumber("flags", g.Flags);
            w.WriteString("name", g.Name);
            w.WriteString("desc", g.Description);
            w.WriteNumber("nv", g.Verts.Length / 3);
            w.WriteNumber("nt", g.Tris.Length / 3);
            w.WriteStartArray("portals");
            foreach (var (portal, other, side) in g.Portals)
            {
                w.WriteStartArray();
                w.WriteNumberValue(portal); w.WriteNumberValue(other); w.WriteNumberValue(side);
                w.WriteEndArray();
            }
            w.WriteEndArray();
            w.WriteEndObject();
            for (var i = 0; i + 2 < g.Verts.Length; i += 3)
            {
                var v = World(new Vector3(g.Verts[i], g.Verts[i + 1], g.Verts[i + 2]));
                mesh.Write(v.X); mesh.Write(v.Y); mesh.Write(v.Z);
            }
            foreach (var t in g.Tris) mesh.Write(t);
            var nv = g.Verts.Length / 3;
            for (var i = 0; i < nv * 2; i++) extra.Write(i < g.Uv.Length ? g.Uv[i] : 0f);
            for (var i = 0; i < nv * 4; i++) extra.Write(i < g.Colours.Length ? g.Colours[i] : (byte)255);
            foreach (var m in g.Materials) extra.Write(m);
            var l = g.Liquid;
            extra.Write(l?.XVerts ?? 0); extra.Write(l?.YVerts ?? 0); extra.Write(l?.XTiles ?? 0); extra.Write(l?.YTiles ?? 0);
            if (l != null)
            {
                for (var y = 0; y < l.YVerts; y++)
                    for (var x = 0; x < l.XVerts; x++)
                    {
                        var v = World(new Vector3(l.Corner.X + x * LiquidTile, l.Corner.Y + y * LiquidTile, l.Heights[y * l.XVerts + x]));
                        extra.Write(v.X); extra.Write(v.Y); extra.Write(v.Z);
                    }
                extra.Write(l.Tiles);
            }
        }
        w.WriteEndArray();
        w.WriteEndObject();
        return list.Count;
    }

    static Group? ReadGroup(byte[] b, int index, byte[] mogn, List<(int portal, int other, int side)> refs)
    {
        foreach (var (magic, s, n) in Terrain.Chunks(b, 0, b.Length))
        {
            if (magic != "MOGP") continue;
            var flags = BitConverter.ToUInt32(b, s + 8);
            if ((flags & 0x80) != 0 || (flags & 0x4000000) != 0) return null; // unreachable, antiportal (Wmo.cs)
            int first = BitConverter.ToUInt16(b, s + 0x24), count = BitConverter.ToUInt16(b, s + 0x26);
            byte[]? mopy = null;
            int[]? idx = null;
            float[]? v = null, uv = null;
            byte[]? colours = null;
            Liquid? liquid = null;
            foreach (var (sm, ss, sn) in Terrain.Chunks(b, s + 0x44, s + n))
            {
                switch (sm)
                {
                    case "MOPY": mopy = b[ss..(ss + sn)]; break;
                    case "MPY2":
                        mopy = new byte[sn / 2];
                        for (var i = 0; i + 1 < mopy.Length; i += 2) { mopy[i] = b[ss + i * 2]; mopy[i + 1] = b[ss + i * 2 + 2]; }
                        break;
                    case "MOVI":
                        idx = new int[sn / 2];
                        for (var i = 0; i < idx.Length; i++) idx[i] = BitConverter.ToUInt16(b, ss + i * 2);
                        break;
                    case "MOVX":
                        idx = new int[sn / 4];
                        for (var i = 0; i < idx.Length; i++) idx[i] = BitConverter.ToInt32(b, ss + i * 4);
                        break;
                    case "MOVT":
                        v = new float[sn / 4];
                        for (var i = 0; i < v.Length; i++) v[i] = BitConverter.ToSingle(b, ss + i * 4);
                        break;
                    case "MOTV" when uv == null:
                        uv = new float[sn / 4];
                        for (var i = 0; i < uv.Length; i++) uv[i] = BitConverter.ToSingle(b, ss + i * 4);
                        break;
                    case "MOCV" when colours == null: colours = b[ss..(ss + sn)]; break;
                    case "MLIQ":
                        int xv = BitConverter.ToInt32(b, ss), yv = BitConverter.ToInt32(b, ss + 4);
                        int xt = BitConverter.ToInt32(b, ss + 8), yt = BitConverter.ToInt32(b, ss + 12);
                        if (xv > 0 && yv > 0 && 30 + xv * yv * 8 + xt * yt <= sn)
                        {
                            var h = new float[xv * yv];
                            for (var i = 0; i < h.Length; i++) h[i] = BitConverter.ToSingle(b, ss + 30 + i * 8 + 4);
                            var tileStart = ss + 30 + xv * yv * 8;
                            liquid = new Liquid(xv, yv, xt, yt, Adt.V3(b, ss + 16), h, b[tileStart..(tileStart + xt * yt)]);
                        }
                        break;
                }
            }
            var tris = new List<int>();
            var mats = new List<ushort>();
            if (idx != null && v != null && mopy != null)
            {
                var nv = v.Length / 3;
                for (var t = 0; t < idx.Length / 3 && t * 2 + 1 < mopy.Length; t++)
                {
                    var f = mopy[t * 2];
                    var render = (f & 0x20) != 0 && (f & 0x04) == 0;
                    if ((f & 0x08) == 0 && !render) continue;
                    int a = idx[t * 3], c = idx[t * 3 + 1], d = idx[t * 3 + 2];
                    if (a >= nv || c >= nv || d >= nv) continue;
                    tris.Add(a); tris.Add(c); tris.Add(d);
                    mats.Add(mopy[t * 2 + 1]);
                }
            }
            return new Group(index, BitConverter.ToUInt32(b, s + 0x38), flags, Text(mogn, BitConverter.ToInt32(b, s)),
                Text(mogn, BitConverter.ToInt32(b, s + 4)),
                refs.Skip(first).Take(count).ToList(), v ?? [], tris.ToArray(), uv ?? [], colours ?? [], mats.ToArray(), liquid);
        }
        return null;
    }

    static string Text(byte[] names, int offset)
    {
        if (offset < 0 || offset >= names.Length) return "";
        var end = Array.IndexOf(names, (byte)0, offset);
        return System.Text.Encoding.UTF8.GetString(names, offset, (end < 0 ? names.Length : end) - offset);
    }
}
