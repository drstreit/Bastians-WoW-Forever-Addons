// The scene of the Bastian map (ADR 0027): per ADT tile the layers a style draws, as rasters of n x n pixels
// (n = 256 by default, 2.08 yards) and as points. Read with the navmesh's readers (Adt, Wmo, M2, the placement
// transform verified there); nothing is drawn here, the drawing is the pipeline's (`bastians_build mapstyle`).
//
// Raster frame: row 0 is the tile's north edge, column 0 its west edge (as the minimap tile); a pixel's centre
// is rx = (x + (col + 0.5) / n) * 533.33, rz = (y + (row + 0.5) / n) * 533.33 in the recast frame (Adt.cs).
//
// Output, one gzip file per tile `<x>_<y>.bmd.gz` in <out>/<Directory>/ (little endian):
//   "BMDT" u32 version (3), i32 x, i32 y, i32 n
//   f32 ground[n*n]      terrain height, yards (NaN: a hole or no terrain)
//   u16 liquid[n*n]      LiquidType id, 0 = none
//   f32 surface[n*n]     liquid surface height (NaN: none)
//   f32 building[n*n]    the highest WMO face over the pixel (NaN: none)
//   u8  indoor[n*n]      1 when that face belongs to an indoor WMO group
//   f32 interior[n*n]    the highest face of an indoor WMO group (NaN: none): a building's footprint (v2)
//   f32 floor[n*n]       the lowest face of an indoor WMO group (NaN: none): under a roof when the top is
//                        well above it, open to the sky when they are the same (v3: Orgrimmar's streets)
//   f32 object[n*n]      the highest face of an M2 with collision (fences, rocks, trunks) (NaN: none)
//   u32 area[256]        per chunk the AreaTable id
//   i32 count, per ground texture: u32 FileDataID, u8 weight[n*n] (0..255)
//   i32 count, per M2 whose position lies in the tile (ADT doodads and WMO doodads):
//       u32 FileDataID, f32 wx, wy, wz, f32 scale, f32 heading (degrees), f32 radius, f32 height (model box)
//   i32 count, per WMO whose position lies in the tile: u32 FileDataID, f32 wx, wy, wz
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO.Compression;
using System.Numerics;

namespace ClientDump;

static class MapData
{
    sealed class Raster(int n)
    {
        public readonly int N = n;
        public readonly float[] Ground = Filled(n * n), Surface = Filled(n * n), Building = Filled(n * n), Object = Filled(n * n),
            Interior = Filled(n * n), Floor = Filled(n * n);
        public readonly ushort[] Liquid = new ushort[n * n];
        public readonly byte[] Indoor = new byte[n * n];
        public readonly SortedDictionary<uint, float[]> Textures = [];
        static float[] Filled(int len) { var a = new float[len]; Array.Fill(a, float.NaN); return a; }
    }

    readonly record struct Doodad(uint Fdid, Vector3 World, float Scale, float Heading, float Radius, float Height);

    public static void Run(Client c, string defsDir, string map, string outDir, string? wdtFdidArg, string? listfile,
        string? tilesArg, int pixels, int threads)
    {
        var total = Stopwatch.StartNew();
        var (mapId, dir, _) = Minimap.ListTiles(c, defsDir, map, wdtFdidArg, listfile);
        var wdtFdid = uint.Parse(wdtFdidArg ?? throw new ArgumentException("--wdt-fdid is required"));
        var (mphd, maid) = Adt.ReadWdt(c.ReadFdid(wdtFdid));
        var bigAlpha = (mphd & 0x4) != 0 || (mphd & 0x80) != 0;
        var build = maid.Keys.OrderBy(k => k.y).ThenBy(k => k.x).ToList();
        if (tilesArg != null)
        {
            var r = tilesArg.Split(',').Select(int.Parse).ToArray();
            build = build.Where(k => k.x >= r[0] && k.x <= r[2] && k.y >= r[1] && k.y <= r[3]).ToList();
        }
        var need = build.SelectMany(k => Enumerable.Range(-1, 3).SelectMany(dy => Enumerable.Range(-1, 3)
                .Select(dx => (x: k.x + dx, y: k.y + dy))))
            .Where(maid.ContainsKey).Distinct().OrderBy(k => k.y).ThenBy(k => k.x).ToList();
        Console.WriteLine($"mapdata: map {mapId} {dir}, {build.Count} tiles, {need.Count} to read, {pixels} px per tile");

        var gate = new object();
        byte[]? Read(uint fdid)
        {
            if (fdid == 0) return null;
            lock (gate)
            {
                try { return c.ReadFdid(fdid); }
                catch (Exception) { return null; }
            }
        }
        uint? ByName(string name)
        {
            lock (gate) return c.FindFdidByName(name);
        }

        // 1. the tiles, their texture layers and placements
        var adts = new ConcurrentDictionary<(int, int), AdtTile>();
        var tex0s = new ConcurrentDictionary<(int, int), byte[]>();
        Parallel.ForEach(need, new ParallelOptions { MaxDegreeOfParallelism = threads }, k =>
        {
            var (root, obj0, tex0) = maid[k];
            var t = new AdtTile { X = k.x, Y = k.y };
            try
            {
                Adt.ReadRoot(Read(root) ?? throw new InvalidDataException($"root ADT {root} missing"), t);
                var ob = Read(obj0);
                if (ob != null) Adt.ReadObj(ob, t, ByName);
                var tb = Read(tex0);
                if (tb != null) tex0s[k] = tb;
            }
            catch (Exception e) { t.Error = e.Message; }
            adts[k] = t;
        });
        var placements = adts.Values.SelectMany(t => t.Placements).ToList();

        // 2. the models
        var wmos = new ConcurrentDictionary<uint, WmoModel>();
        Parallel.ForEach(placements.Where(p => p.Wmo).Select(p => p.Fdid).Distinct().Order(),
            new ParallelOptions { MaxDegreeOfParallelism = threads }, f => wmos[f] = Wmo.Read(Read, f, t => (int)t));
        var m2ids = placements.Where(p => !p.Wmo).Select(p => p.Fdid)
            .Concat(wmos.Values.SelectMany(w => w.Doodads.Select(d => d.Fdid))).Where(f => f != 0).Distinct().Order().ToList();
        var m2s = new ConcurrentDictionary<uint, (ModelMesh? mesh, Vector3 min, Vector3 max)>();
        Parallel.ForEach(m2ids, new ParallelOptions { MaxDegreeOfParallelism = threads }, f =>
        {
            var b = Read(f);
            m2s[f] = (M2.Read(b), BoxOf(b, out var max), max);
        });
        Console.WriteLine($"read {adts.Count} tiles, {wmos.Count} WMOs, {m2s.Count} M2s in {total.Elapsed.TotalSeconds:0.0} s");

        // 3. the scene per tile
        var outTiles = Path.Combine(outDir, dir);
        Directory.CreateDirectory(outTiles);
        var done = 0;
        Parallel.ForEach(build, new ParallelOptions { MaxDegreeOfParallelism = threads }, k =>
        {
            try
            {
                var (raster, doodads, buildings) = Scene(k, pixels, adts, tex0s, bigAlpha, wmos, m2s);
                Write(Path.Combine(outTiles, $"{k.x}_{k.y}.bmd.gz"), k, raster, adts.TryGetValue(k, out var t) ? t.AreaIds : new uint[256],
                    doodads, buildings);
            }
            catch (Exception e) { Console.Error.WriteLine($"warning: tile {k.x},{k.y}: {e.Message}"); }
            var n = Interlocked.Increment(ref done);
            if (n % 50 == 0 || n == build.Count) Console.WriteLine($"  {n}/{build.Count} tiles, {total.Elapsed.TotalSeconds:0} s");
        });
        Console.WriteLine($"-> {outTiles} ({build.Count} tiles), {total.Elapsed.TotalSeconds:0} s");
    }

    /// <summary>The M2's model box (MD20 0xA0: min xyz, max xyz); zero when unreadable.</summary>
    static Vector3 BoxOf(byte[]? b, out Vector3 max)
    {
        max = default;
        if (b == null || b.Length < 0x100) return default;
        var md20 = -1;
        if (b[0] == 'M' && b[1] == 'D' && b[2] == '2' && b[3] == '0') md20 = 0;
        else
            for (var p = 0; p + 8 <= b.Length;)
            {
                var size = BitConverter.ToInt32(b, p + 4);
                if (size < 0 || p + 8 + size > b.Length) break;
                if (b[p] == 'M' && b[p + 1] == 'D' && b[p + 2] == '2' && b[p + 3] == '1') { md20 = p + 8; break; }
                p += 8 + size;
            }
        if (md20 < 0 || md20 + 0xB8 > b.Length) return default;
        max = Adt.V3(b, md20 + 0xAC);
        return Adt.V3(b, md20 + 0xA0);
    }

    static (Raster, List<Doodad>, List<(uint fdid, Vector3 world)>) Scene((int x, int y) k, int n,
        ConcurrentDictionary<(int, int), AdtTile> adts, ConcurrentDictionary<(int, int), byte[]> tex0s, bool bigAlpha,
        ConcurrentDictionary<uint, WmoModel> wmos, ConcurrentDictionary<uint, (ModelMesh? mesh, Vector3 min, Vector3 max)> m2s)
    {
        var r = new Raster(n);
        double x0 = k.x * Frame.Tile, z0 = k.y * Frame.Tile, px = Frame.Tile / n;
        bool Inside(Vector3 v) => v.X >= x0 && v.X < x0 + Frame.Tile && v.Z >= z0 && v.Z < z0 + Frame.Tile;

        // a triangle in the recast frame onto the pixel centres; keep the highest value
        void Fill(Vector3 a, Vector3 b, Vector3 c, Action<int, float> put)
        {
            double ax = (a.X - x0) / px - 0.5, az = (a.Z - z0) / px - 0.5, bx = (b.X - x0) / px - 0.5, bz = (b.Z - z0) / px - 0.5;
            double cx = (c.X - x0) / px - 0.5, cz = (c.Z - z0) / px - 0.5;
            var den = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz);
            if (Math.Abs(den) < 1e-12) return;
            int c0 = Math.Max(0, (int)Math.Ceiling(Math.Min(ax, Math.Min(bx, cx)))), c1 = Math.Min(n - 1, (int)Math.Floor(Math.Max(ax, Math.Max(bx, cx))));
            int r0 = Math.Max(0, (int)Math.Ceiling(Math.Min(az, Math.Min(bz, cz)))), r1 = Math.Min(n - 1, (int)Math.Floor(Math.Max(az, Math.Max(bz, cz))));
            for (var row = r0; row <= r1; row++)
            for (var col = c0; col <= c1; col++)
            {
                var wa = ((bz - cz) * (col - cx) + (cx - bx) * (row - cz)) / den;
                var wb = ((cz - az) * (col - cx) + (ax - cx) * (row - cz)) / den;
                var wc = 1 - wa - wb;
                if (wa < -1e-6 || wb < -1e-6 || wc < -1e-6) continue;
                put(row * n + col, (float)(wa * a.Y + wb * b.Y + wc * c.Y));
            }
        }
        static void Max(float[] into, int i, float v) { if (float.IsNaN(into[i]) || v > into[i]) into[i] = v; }
        static void Min(float[] into, int i, float v) { if (float.IsNaN(into[i]) || v < into[i]) into[i] = v; }

        // terrain of this tile: the four triangles of each 4.17-yard cell (as the navmesh), holes left out
        if (adts.TryGetValue(k, out var t))
        {
            for (var ch = 0; ch < 256; ch++)
            {
                var h = t.Heights[ch];
                if (h == null) continue;
                int ix = ch % 16, iy = ch / 16;
                var ccx = (k.x * 16 + ix) * Frame.Chunk;
                var ccz = (k.y * 16 + iy) * Frame.Chunk;
                for (var row = 0; row < 8; row++)
                for (var col = 0; col < 8; col++)
                {
                    if (((t.Holes[ch] >> (row * 8 + col)) & 1) != 0) continue;
                    float fx = (float)(ccx + col * Frame.Unit), fz = (float)(ccz + row * Frame.Unit), u = (float)Frame.Unit;
                    var a = new Vector3(fx, h[row * 17 + col], fz);
                    var b = new Vector3(fx + u, h[row * 17 + col + 1], fz);
                    var cc = new Vector3(fx + u, h[(row + 1) * 17 + col + 1], fz + u);
                    var d = new Vector3(fx, h[(row + 1) * 17 + col], fz + u);
                    var m = new Vector3(fx + u / 2, h[row * 17 + 9 + col], fz + u / 2);
                    void G(int i, float v) => Max(r.Ground, i, v);
                    Fill(m, a, b, G); Fill(m, b, cc, G); Fill(m, cc, d, G); Fill(m, d, a, G);
                }
            }
            foreach (var l in t.Liquids)
                Fill(l.A, l.B, l.C, (i, v) =>
                {
                    if (!float.IsNaN(r.Surface[i]) && r.Surface[i] >= v) return;
                    r.Surface[i] = v;
                    r.Liquid[i] = (ushort)l.Type;
                });
        }
        if (tex0s.TryGetValue(k, out var tb)) Textures(tb, bigAlpha, r);

        // objects of the 3 x 3 tiles, once each, by unique id
        var objs = new SortedDictionary<uint, Placement>();
        for (var ny = k.y - 1; ny <= k.y + 1; ny++)
        for (var nx = k.x - 1; nx <= k.x + 1; nx++)
            if (adts.TryGetValue((nx, ny), out var nt))
                foreach (var p in nt.Placements)
                    objs.TryAdd(p.UniqueId ^ (p.Wmo ? 0x80000000u : 0u), p);
        var doodads = new List<Doodad>();
        var buildings = new List<(uint, Vector3)>();
        void Mesh(ModelMesh mesh, Navmesh.Xf xf, bool building)
        {
            if (mesh.Tris.Length == 0) return;
            var w = new Vector3[mesh.Verts.Length / 3];
            for (var i = 0; i < w.Length; i++)
                w[i] = xf.M.Mul(new Vector3(mesh.Verts[i * 3], mesh.Verts[i * 3 + 1], mesh.Verts[i * 3 + 2])) + xf.T;
            for (var tri = 0; tri < mesh.Tris.Length / 3; tri++)
            {
                Vector3 a = w[mesh.Tris[tri * 3]], b = w[mesh.Tris[tri * 3 + 1]], c = w[mesh.Tris[tri * 3 + 2]];
                if (Math.Max(a.X, Math.Max(b.X, c.X)) < x0 || Math.Min(a.X, Math.Min(b.X, c.X)) > x0 + Frame.Tile
                    || Math.Max(a.Z, Math.Max(b.Z, c.Z)) < z0 || Math.Min(a.Z, Math.Min(b.Z, c.Z)) > z0 + Frame.Tile) continue;
                var indoor = building && (mesh.TriFlags[tri] & 1) != 0;
                if (building)
                    Fill(a, b, c, (i, v) =>
                    {
                        if (indoor) { Max(r.Interior, i, v); Min(r.Floor, i, v); }
                        if (!float.IsNaN(r.Building[i]) && r.Building[i] >= v) return;
                        r.Building[i] = v;
                        r.Indoor[i] = (byte)(indoor ? 1 : 0);
                    });
                else Fill(a, b, c, (i, v) => Max(r.Object, i, v));
            }
        }
        void Doodad(uint fdid, Navmesh.Xf xf, float scale, float heading)
        {
            if (!m2s.TryGetValue(fdid, out var m)) return;
            if (m.mesh != null) Mesh(m.mesh, xf, false);
            var pos = xf.T;
            if (!Inside(pos)) return;
            var (wx, wy, wz) = Frame.ToWorld(pos.X, pos.Y, pos.Z);
            var radius = Math.Max(Math.Max(Math.Abs(m.min.X), Math.Abs(m.max.X)), Math.Max(Math.Abs(m.min.Y), Math.Abs(m.max.Y))) * scale;
            doodads.Add(new Doodad(fdid, new Vector3((float)wx, (float)wy, (float)wz), scale, heading, radius,
                (m.max.Z - m.min.Z) * scale));
        }
        foreach (var p in objs.Values)
        {
            var xf = Navmesh.PlacementXf(p);
            if (!p.Wmo)
            {
                Doodad(p.Fdid, xf, p.Scale, p.Rot.Y);
                continue;
            }
            if (Inside(p.Pos))
            {
                var (wx, wy, wz) = Frame.ToWorld(p.Pos.X, p.Pos.Y, p.Pos.Z);
                buildings.Add((p.Fdid, new Vector3((float)wx, (float)wy, (float)wz)));
            }
            if (!wmos.TryGetValue(p.Fdid, out var wm) || wm.Error != null) continue;
            Mesh(wm.Mesh, xf, true);
            foreach (var (a, b, c, type) in wm.Liquids)
                Fill(xf.M.Mul(a) + xf.T, xf.M.Mul(b) + xf.T, xf.M.Mul(c) + xf.T, (i, v) =>
                {
                    if (!float.IsNaN(r.Surface[i]) && r.Surface[i] >= v) return;
                    r.Surface[i] = v;
                    r.Liquid[i] = (ushort)type;
                });
            for (var si = 0; si < wm.Sets.Count; si++)
            {
                if (si != 0 && si != p.DoodadSet) continue;
                var (first, count) = wm.Sets[si];
                for (var di = first; di < first + count && di < wm.Doodads.Count; di++)
                {
                    var d = wm.Doodads[di];
                    if (d.Fdid == 0) continue;
                    var inner = Navmesh.Matrix3.Q(d.Rot) * Navmesh.Matrix3.Scale(d.Scale);
                    Doodad(d.Fdid, new Navmesh.Xf(xf.M * inner, xf.M.Mul(d.Pos) + xf.T), d.Scale * p.Scale, p.Rot.Y);
                }
            }
        }
        doodads.Sort((a, b) => a.Fdid != b.Fdid ? a.Fdid.CompareTo(b.Fdid)
            : a.World.X != b.World.X ? a.World.X.CompareTo(b.World.X) : a.World.Y.CompareTo(b.World.Y));
        buildings.Sort((a, b) => a.Item1 != b.Item1 ? a.Item1.CompareTo(b.Item1) : a.Item2.X.CompareTo(b.Item2.X));
        return (r, doodads, buildings);
    }

    /// <summary>tex0: per chunk the layers (MCLY) and alpha maps (MCAL, 64 x 64); each texture's weight averaged
    /// onto the raster's pixels of that chunk; the base layer gets what the others leave.</summary>
    static void Textures(byte[] b, bool bigAlpha, Raster r)
    {
        var n = r.N;
        var per = n / 16; // pixels per chunk side
        var textures = new List<uint>();
        var chunk = 0;
        foreach (var (magic, start, size) in Terrain.Chunks(b, 0, b.Length))
        {
            if (magic == "MDID")
                for (var i = 0; i + 4 <= size; i += 4) textures.Add(BitConverter.ToUInt32(b, start + i));
            if (magic != "MCNK") continue;
            int ix = chunk % 16, iy = chunk / 16;
            chunk++;
            var layers = new List<(uint tex, uint flags, int ofs)>();
            int mcal = -1, mcalSize = 0;
            foreach (var (m, s, len) in Terrain.Chunks(b, start, start + size))
            {
                if (m == "MCLY")
                    for (var i = 0; i + 16 <= len; i += 16)
                        layers.Add((BitConverter.ToUInt32(b, s + i), BitConverter.ToUInt32(b, s + i + 4), BitConverter.ToInt32(b, s + i + 8)));
                if (m == "MCAL") { mcal = s; mcalSize = len; }
            }
            if (layers.Count == 0) continue;
            var rest = new float[per * per];
            Array.Fill(rest, 1f);
            var weights = new float[layers.Count][];
            for (var l = 1; l < layers.Count; l++)
            {
                weights[l] = new float[per * per];
                if ((layers[l].flags & 0x100) == 0 || mcal < 0) continue;
                var alpha = Terrain.Alpha(b, mcal + layers[l].ofs, mcal + mcalSize, layers[l].flags, bigAlpha);
                var step = 64 / per;
                for (var py = 0; py < per; py++)
                for (var pxl = 0; pxl < per; pxl++)
                {
                    double sum = 0;
                    for (var sy = 0; sy < step; sy++)
                    for (var sx = 0; sx < step; sx++)
                        sum += alpha[(py * step + sy) * 64 + pxl * step + sx];
                    var wgt = (float)(sum / (step * step) / 255);
                    weights[l][py * per + pxl] = wgt;
                    rest[py * per + pxl] -= wgt;
                }
            }
            weights[0] = rest.Select(v => Math.Max(0, v)).ToArray();
            for (var l = 0; l < layers.Count; l++)
            {
                var idx = (int)layers[l].tex;
                var fdid = idx < textures.Count ? textures[idx] : 0;
                if (!r.Textures.TryGetValue(fdid, out var into))
                {
                    into = new float[n * n];
                    r.Textures[fdid] = into;
                }
                for (var py = 0; py < per; py++)
                for (var pxl = 0; pxl < per; pxl++)
                    into[(iy * per + py) * n + ix * per + pxl] += weights[l][py * per + pxl];
            }
        }
    }

    static void Write(string path, (int x, int y) k, Raster r, uint[] areas, List<Doodad> doodads,
        List<(uint fdid, Vector3 world)> buildings)
    {
        var tmp = path + ".tmp";
        using (var file = File.Create(tmp))
        using (var gz = new GZipStream(file, CompressionLevel.Fastest))
        using (var w = new BinaryWriter(gz))
        {
            w.Write("BMDT"u8.ToArray());
            w.Write(3u);
            w.Write(k.x);
            w.Write(k.y);
            w.Write(r.N);
            foreach (var v in r.Ground) w.Write(v);
            foreach (var v in r.Liquid) w.Write(v);
            foreach (var v in r.Surface) w.Write(v);
            foreach (var v in r.Building) w.Write(v);
            w.Write(r.Indoor);
            foreach (var v in r.Interior) w.Write(v);
            foreach (var v in r.Floor) w.Write(v);
            foreach (var v in r.Object) w.Write(v);
            foreach (var a in areas) w.Write(a);
            w.Write(r.Textures.Count);
            foreach (var (fdid, weights) in r.Textures)
            {
                w.Write(fdid);
                foreach (var v in weights) w.Write((byte)Math.Clamp(Math.Round(v * 255), 0, 255));
            }
            w.Write(doodads.Count);
            foreach (var d in doodads)
            {
                w.Write(d.Fdid);
                w.Write(d.World.X); w.Write(d.World.Y); w.Write(d.World.Z);
                w.Write(d.Scale); w.Write(d.Heading); w.Write(d.Radius); w.Write(d.Height);
            }
            w.Write(buildings.Count);
            foreach (var (fdid, world) in buildings)
            {
                w.Write(fdid);
                w.Write(world.X); w.Write(world.Y); w.Write(world.Z);
            }
        }
        File.Move(tmp, path, true);
    }
}
