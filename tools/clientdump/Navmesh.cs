// The movement mesh of one map (ADR 0026, world-graph.md §6.1): per ADT tile the client's collision geometry
// (terrain, WMO groups, M2 collision, liquids) rasterised and built into a tiled Recast/Detour navmesh with
// DotRecast. Offline only; the mesh never ships, the network extraction (W3) reads it.
//
// Pipeline per Recast tile (an ADT tile is split x split Recast tiles): triangles marked by slope and source
// (ground, road, indoor), rasterised; the three Recast span filters; then the liquids are applied to the spans
// (water at most swim_depth deep: the floor becomes "shallow"; deeper: the floor is dropped and a span at the
// surface is added as "deep", so swimmers can leave the water where the shore is within climb; lava and slime
// make the floor "blocked"); compact heightfield, erosion by the agent radius, watershed regions, contours,
// polygons, detail mesh, Detour tile data. Fixed settings and a fixed order: the same client gives the same
// bytes. Output: <Dir>.navmesh (format in docs/data/client-extraction.md "Navmesh") and <Dir>.navmesh.json.
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO.Compression;
using System.Numerics;
using System.Text.Json;
using DotRecast.Core;
using DotRecast.Core.Numerics;
using DotRecast.Detour;
using DotRecast.Detour.Io;
using DotRecast.Recast;

namespace ClientDump;

static class Navmesh
{
    public const int AreaGround = 1, AreaRoad = 2, AreaShallow = 3, AreaDeep = 4, AreaIndoor = 5, AreaBlocked = 6;
    public const int FlagWalk = 1, FlagSwim = 2, FlagIndoor = 4, FlagRoad = 8, FlagShallow = 16, FlagBlocked = 32;
    public static readonly string[] AreaNames = ["none", "ground", "road", "shallow", "deep", "indoor", "blocked"];

    /// <summary>The fixed build settings; see docs/data/client-extraction.md for their source.</summary>
    public sealed class Settings
    {
        public int Split = 4;                   // Recast tiles per ADT tile and axis
        public int TileCells = 250;             // cells per Recast tile side: 533.33 / 4 / 250 = 0.5333 yards
        public float Ch = 0.26666667f;          // cell height (TrinityCore's small BASE_UNIT_DIM)
        public float AgentHeight = 1.6f;        // TrinityCore walkableHeight (6 x 0.2667)
        public float AgentRadius = 0.53333336f; // TrinityCore walkableRadius (2 x 0.2667 = 1 x 0.5333)
        public float AgentClimb = 1.6f;         // TrinityCore walkableClimb (6 x 0.2667)
        public float MaxSlope = 55f;            // TrinityCore walkableSlopeAngle default
        public int MinRegion = 400;             // cells (TrinityCore 60^2 on 40-cell tiles, see the doc)
        public int MergeRegion = 2500;          // cells (TrinityCore 50^2)
        public float MaxError = 1.8f;           // TrinityCore maxSimplificationError
        public float DetailSampleDist = 16;     // x cs (TrinityCore)
        public float DetailMaxError = 1;        // x ch (TrinityCore)
        public float SwimDepth = 1.6f;          // ADR 0025: water deeper than this is swum
        public float RoadMin = 0.35f;           // nav.toml road_min
        public float Cs => (float)(Frame.Tile / Split / TileCells);
        public int Border => (int)Math.Ceiling(AgentRadius / Cs) + 3; // TrinityCore borderSize = radius + 3
        public int HeightCells => (int)Math.Ceiling(AgentHeight / Ch);
        public int ClimbCells => (int)Math.Floor(AgentClimb / Ch);
        public int RadiusCells => (int)Math.Ceiling(AgentRadius / Cs);
    }

    /// <summary>Passes lines through, except DotRecast's warnings (console and error stream) ("delaunayHull: Removing dangling face",
    /// "rcBuildRegions: 1 overlapping regions", "BuildPolyMesh: Bad triangulation Contour 28"), counted by kind.</summary>
    sealed class RecastWarnings(TextWriter inner) : TextWriter
    {
        public readonly SortedDictionary<string, int> Counts = [];
        readonly System.Text.StringBuilder line = new();
        public override System.Text.Encoding Encoding => inner.Encoding;
        public override void Write(char value)
        {
            if (value == '\r') return;
            if (value != '\n') { line.Append(value); return; }
            var l = line.ToString();
            line.Clear();
            var colon = l.IndexOf(':');
            var kind = colon > 0 ? l[..colon] : "";
            if (l.StartsWith("Walk towards")) kind = l;
            if (kind is "delaunayHull" || kind.StartsWith("rc") || kind.StartsWith("Build") || kind.StartsWith("Walk"))
            {
                var key = kind == l ? l : kind + ":" + System.Text.RegularExpressions.Regex.Replace(l[(colon + 1)..], @"[-\d\[\],.]+", " ").Trim();
                Counts[key] = Counts.GetValueOrDefault(key) + 1;
            }
            else inner.WriteLine(l);
        }
    }

    /// <summary>A model placed in the recast frame: recast = M * model + T.</summary>
    internal readonly record struct Xf(Matrix3 M, Vector3 T);

    internal readonly struct Matrix3(double a, double b, double c, double d, double e, double f, double g, double h, double i)
    {
        readonly double m00 = a, m01 = b, m02 = c, m10 = d, m11 = e, m12 = f, m20 = g, m21 = h, m22 = i;
        public Vector3 Mul(Vector3 v) => new((float)(m00 * v.X + m01 * v.Y + m02 * v.Z),
            (float)(m10 * v.X + m11 * v.Y + m12 * v.Z), (float)(m20 * v.X + m21 * v.Y + m22 * v.Z));
        public static Matrix3 operator *(Matrix3 p, Matrix3 q) => new(
            p.m00 * q.m00 + p.m01 * q.m10 + p.m02 * q.m20, p.m00 * q.m01 + p.m01 * q.m11 + p.m02 * q.m21, p.m00 * q.m02 + p.m01 * q.m12 + p.m02 * q.m22,
            p.m10 * q.m00 + p.m11 * q.m10 + p.m12 * q.m20, p.m10 * q.m01 + p.m11 * q.m11 + p.m12 * q.m21, p.m10 * q.m02 + p.m11 * q.m12 + p.m12 * q.m22,
            p.m20 * q.m00 + p.m21 * q.m10 + p.m22 * q.m20, p.m20 * q.m01 + p.m21 * q.m11 + p.m22 * q.m21, p.m20 * q.m02 + p.m21 * q.m12 + p.m22 * q.m22);
        public static Matrix3 Scale(double s) => new(s, 0, 0, 0, s, 0, 0, 0, s);
        public static Matrix3 Rx(double r) => new(1, 0, 0, 0, Math.Cos(r), -Math.Sin(r), 0, Math.Sin(r), Math.Cos(r));
        public static Matrix3 Ry(double r) => new(Math.Cos(r), 0, Math.Sin(r), 0, 1, 0, -Math.Sin(r), 0, Math.Cos(r));
        public static Matrix3 Rz(double r) => new(Math.Cos(r), -Math.Sin(r), 0, Math.Sin(r), Math.Cos(r), 0, 0, 0, 1);
        public static Matrix3 Q(Quaternion q)
        {
            double x = q.X, y = q.Y, z = q.Z, w = q.W;
            return new(1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
                2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
                2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y));
        }
        // model (z up) -> recast (y up): recast = (m.y, m.z, m.x) of the internal frame (see Placement)
        public static readonly Matrix3 ToRecast = new(0, 1, 0, 0, 0, 1, 1, 0, 0);
    }

    /// <summary>An ADT placement: TrinityCore's vmap ModelInstance puts a model at internal = R * s * v + (pz, px,
    /// py) with R = Rz(rot.y) Ry(rot.x) Rx(rot.z) (G3D fromEulerAnglesZYX), internal = (mid - wx, mid - wy, wz).
    /// In the recast frame (rx = mid - wy, ry = wz, rz = mid - wx) that is recast = P R s v + pos with P the
    /// axis permutation (x, y, z) -> (y, z, x). Verified against the MODF extents (see the doc).</summary>
    internal static Xf PlacementXf(Placement p)
    {
        const double d = Math.PI / 180;
        var r = Matrix3.Rz(p.Rot.Y * d) * Matrix3.Ry(p.Rot.X * d) * Matrix3.Rx(p.Rot.Z * d);
        return new Xf(Matrix3.ToRecast * r * Matrix3.Scale(p.Scale), p.Pos);
    }

    sealed class TileResult
    {
        public int X, Y;
        public List<(int tx, int tz, byte[] data, int polys, int verts, int dtris)> Tiles = [];
        public List<string> Failed = [];
        public uint[] AreaIds = [];
        public int SolidTris, LiquidTris, Objects;
        public long Ms;
        public string? Error;
    }

    public static void Run(Client c, string defsDir, string map, string outDir, string? wdtFdidArg, string? listfile,
        string? roadsFile, string? tilesArg, string? blockedArg, int threads, bool readOnly = false)
    {
        var total = Stopwatch.StartNew();
        var s = new Settings();
        var (mapId, dir, _) = Minimap.ListTiles(c, defsDir, map, wdtFdidArg, listfile);
        var wdtFdid = uint.Parse(wdtFdidArg ?? throw new ArgumentException("--wdt-fdid is required"));
        var (mphd, maid) = Adt.ReadWdt(c.ReadFdid(wdtFdid));
        var bigAlpha = (mphd & 0x4) != 0 || (mphd & 0x80) != 0;
        var roads = roadsFile != null
            ? File.ReadLines(roadsFile).Select(l => l.Split('\t', ';', ',')[0].Trim())
                .Where(x => uint.TryParse(x, out _)).Select(uint.Parse).ToHashSet()
            : [];

        // the liquids that block, by LiquidType name (nav.toml [liquids] blocked)
        var blockedWords = (blockedArg ?? "magma,lava,slime,fel,tar pit").Split(',').Select(w => w.Trim()).ToArray();
        var liquidNames = new Dictionary<int, string>();
        var lt = Db2.Load(c, defsDir, "LiquidType");
        foreach (var key in lt.Keys) liquidNames[key] = (string?)lt[key]["Name"] ?? "";
        var blocked = liquidNames.Where(kv => blockedWords.Any(w => kv.Value.Contains(w, StringComparison.OrdinalIgnoreCase)))
            .Select(kv => kv.Key).ToHashSet();

        var build = maid.Keys.OrderBy(k => k.y).ThenBy(k => k.x).ToList();
        if (tilesArg != null)
        {
            var r = tilesArg.Split(',').Select(int.Parse).ToArray();
            build = build.Where(k => k.x >= r[0] && k.x <= r[2] && k.y >= r[1] && k.y <= r[3]).ToList();
        }
        var need = build.SelectMany(k => Enumerable.Range(-1, 3).SelectMany(dy => Enumerable.Range(-1, 3)
                .Select(dx => (x: k.x + dx, y: k.y + dy))))
            .Where(maid.ContainsKey).Distinct().OrderBy(k => k.y).ThenBy(k => k.x).ToList();
        Console.WriteLine($"navmesh: map {mapId} {dir}, {build.Count} tiles to build, {need.Count} to read, " +
            $"{roads.Count} road textures, blocked liquids [{string.Join(", ", blocked.Order().Select(i => $"{i} {liquidNames[i]}"))}], " +
            $"cs {s.Cs:0.####} ch {s.Ch:0.####}, {threads} threads");

        // 1. read: one client read at a time (TACTSharp is not known to be thread safe), parsing in parallel
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
        Dictionary<string, uint>? names = null;
        uint? ByName(string name)
        {
            lock (gate)
            {
                var id = c.FindFdidByName(name);
                if (id != null) return id;
                if (listfile == null) return null;
                names ??= File.ReadLines(listfile).Select(l => l.Split(';', 2)).Where(p => p.Length == 2)
                    .GroupBy(p => p[1].ToLowerInvariant()).ToDictionary(g => g.Key, g => uint.Parse(g.First()[0]));
                return names.TryGetValue(name.Replace('\\', '/').ToLowerInvariant(), out var f) ? f : null;
            }
        }
        var sw = Stopwatch.StartNew();
        var adts = new ConcurrentDictionary<(int, int), AdtTile>();
        Parallel.ForEach(need, new ParallelOptions { MaxDegreeOfParallelism = threads }, k =>
        {
            var (root, obj0, tex0) = maid[k];
            var t = new AdtTile { X = k.x, Y = k.y };
            try
            {
                var rb = Read(root) ?? throw new InvalidDataException($"root ADT {root} missing");
                Adt.ReadRoot(rb, t);
                var tb = Read(tex0);
                if (tb != null && roads.Count > 0)
                {
                    var grid = new Terrain.Cell[128 * 128];
                    Terrain.ReadTex(tb, grid, bigAlpha, roads, []);
                    for (var i = 0; i < grid.Length; i++) t.Road[i] = (float)grid[i].Road;
                }
                var ob = Read(obj0);
                if (ob != null) Adt.ReadObj(ob, t, ByName);
            }
            catch (Exception e) { t.Error = e.Message; }
            adts[k] = t;
        });
        foreach (var t in adts.Values.Where(t => t.Error != null).OrderBy(t => t.Y).ThenBy(t => t.X))
            Console.Error.WriteLine($"warning: tile {t.X},{t.Y}: {t.Error}");
        var placements = adts.Values.SelectMany(t => t.Placements).ToList();
        Console.WriteLine($"read {adts.Count} ADT tiles in {sw.Elapsed.TotalSeconds:0.0} s: {placements.Count(p => p.Wmo)} WMO and " +
            $"{placements.Count(p => !p.Wmo)} doodad placements ({adts.Values.Sum(t => t.UnnamedWmos)} WMO and " +
            $"{adts.Values.Sum(t => t.UnnamedDoodads)} doodad names unresolved), " +
            $"{placements.Count(p => !p.Wmo && (p.Flags & 0x40) == 0)} doodads by name");

        // 2. the models
        sw.Restart();
        var wmos = new ConcurrentDictionary<uint, WmoModel>();
        Parallel.ForEach(placements.Where(p => p.Wmo).Select(p => p.Fdid).Distinct().Order(),
            new ParallelOptions { MaxDegreeOfParallelism = threads },
            f => wmos[f] = Wmo.Read(Read, f, t => (int)t));
        var m2ids = placements.Where(p => !p.Wmo).Select(p => p.Fdid)
            .Concat(wmos.Values.SelectMany(w => w.Doodads.Select(d => d.Fdid))).Where(f => f != 0).Distinct().Order().ToList();
        var m2s = new ConcurrentDictionary<uint, ModelMesh?>();
        Parallel.ForEach(m2ids, new ParallelOptions { MaxDegreeOfParallelism = threads }, f => m2s[f] = M2.Read(Read(f)));
        Console.WriteLine($"models in {sw.Elapsed.TotalSeconds:0.0} s: {wmos.Count} WMOs ({wmos.Values.Count(w => w.Error != null)} failed, " +
            $"{wmos.Values.Sum(w => w.GroupsRead)} groups, {wmos.Values.Sum(w => w.IndoorGroups)} indoor, " +
            $"{wmos.Values.Sum(w => w.GroupsSkipped)} skipped, {wmos.Values.Sum(w => w.Mesh.Tris.Length / 3)} collision triangles, " +
            $"{wmos.Values.Sum(w => w.Liquids.Count)} liquid triangles), {m2s.Count} M2s " +
            $"({m2s.Values.Count(m => m == null)} unreadable, {m2s.Values.Count(m => m is { Tris.Length: > 0 })} with collision, " +
            $"{m2s.Values.Sum(m => m?.Tris.Length / 3 ?? 0)} triangles)");
        foreach (var w in wmos.OrderBy(kv => kv.Key).Where(kv => kv.Value.Error != null).Take(10))
            Console.Error.WriteLine($"warning: WMO {w.Key}: {w.Value.Error}");
        ExtentCheck(placements, wmos);
        if (readOnly) return;

        // 3. build, tile by tile in parallel; results in the fixed tile order. DotRecast prints its warnings
        // straight to the console (RcContext.Warn); they are counted instead.
        sw.Restart();
        var (console, errors) = (Console.Out, Console.Error);
        var recastWarnings = new RecastWarnings(console);
        var recastErrors = new RecastWarnings(errors);
        Console.SetOut(TextWriter.Synchronized(recastWarnings));
        Console.SetError(TextWriter.Synchronized(recastErrors));
        var results = new TileResult[build.Count];
        var done = 0;
        Parallel.For(0, build.Count, new ParallelOptions { MaxDegreeOfParallelism = threads }, i =>
        {
            var k = build[i];
            var tsw = Stopwatch.StartNew();
            var res = new TileResult { X = k.x, Y = k.y, AreaIds = adts.TryGetValue(k, out var at) ? at.AreaIds : new uint[256] };
            try { BuildAdt(s, k, adts, wmos, m2s, blocked, res); }
            catch (Exception e) { res.Error = e.GetType().Name + ": " + e.Message; }
            res.Ms = tsw.ElapsedMilliseconds;
            results[i] = res;
            var n = Interlocked.Increment(ref done);
            if (n % 50 == 0 || n == build.Count)
                Console.WriteLine($"  {n}/{build.Count} tiles, {sw.Elapsed.TotalSeconds:0} s");
        });
        foreach (var r in results.Where(r => r.Error != null))
            Console.Error.WriteLine($"warning: build {r.X},{r.Y}: {r.Error}");
        foreach (var f in results.SelectMany(r => r.Failed))
            Console.Error.WriteLine($"warning: Recast tile {f}");
        Console.WriteLine($"{fallbacks} Recast tiles built with monotone regions, {results.Sum(r => r.Failed.Count)} failed");
        var buildSeconds = sw.Elapsed.TotalSeconds;
        Console.SetOut(console);
        Console.SetError(errors);
        foreach (var kv in recastErrors.Counts) recastWarnings.Counts[kv.Key] = recastWarnings.Counts.GetValueOrDefault(kv.Key) + kv.Value;
        if (recastWarnings.Counts.Count > 0)
            Console.WriteLine("recast warnings: " + string.Join(", ", recastWarnings.Counts.Select(kv => $"{kv.Key} {kv.Value}")));

        // 4. write
        Directory.CreateDirectory(outDir);
        var path = Path.Combine(outDir, $"{dir}.navmesh");
        var size = Write(path, s, mapId, c.Version, results);
        var summary = Path.Combine(outDir, $"{dir}.navmesh.json");
        WriteSummary(summary, s, mapId, dir, c, results, buildSeconds, total.Elapsed.TotalSeconds, size, adts, wmos, m2s);
        Console.WriteLine($"-> {path} ({size / 1048576.0:0.0} MB, {results.Sum(r => r.Tiles.Count)} Recast tiles, " +
            $"{results.Sum(r => r.Tiles.Sum(t => t.polys))} polys), build {buildSeconds:0} s, total {total.Elapsed.TotalSeconds:0} s; {summary}");
    }

    /// <summary>The transform check: the MOHD bounding box of every placed WMO, put through PlacementXf, must give
    /// the MODF extents (the client's own placed bounds, in the placement frame).</summary>
    static void ExtentCheck(List<Placement> placements, ConcurrentDictionary<uint, WmoModel> wmos)
    {
        var devs = new List<double>();
        var contained = 0;
        foreach (var p in placements.Where(p => p.Wmo).DistinctBy(p => p.UniqueId))
        {
            if (!wmos.TryGetValue(p.Fdid, out var w) || w.Error != null) continue;
            var xf = PlacementXf(p);
            var (mn, mx) = (new Vector3(float.MaxValue), new Vector3(float.MinValue));
            for (var i = 0; i < 8; i++)
            {
                var v = new Vector3((i & 1) != 0 ? w.BoxMax.X : w.BoxMin.X, (i & 2) != 0 ? w.BoxMax.Y : w.BoxMin.Y,
                    (i & 4) != 0 ? w.BoxMax.Z : w.BoxMin.Z);
                var r = xf.M.Mul(v) + xf.T;
                mn = Vector3.Min(mn, r); mx = Vector3.Max(mx, r);
            }
            var d = Math.Max((mn - p.ExtMin).Length(), (mx - p.ExtMax).Length());
            devs.Add(d);
            if (d < 1) continue;
            // the extents may also hold the placement's doodads: then the box lies inside them
            var inside = mn.X >= p.ExtMin.X - 0.1f && mn.Y >= p.ExtMin.Y - 0.1f && mn.Z >= p.ExtMin.Z - 0.1f
                && mx.X <= p.ExtMax.X + 0.1f && mx.Y <= p.ExtMax.Y + 0.1f && mx.Z <= p.ExtMax.Z + 0.1f;
            if (inside) { contained++; continue; }
            var (wx, wy, wz) = Frame.ToWorld(p.Pos.X, p.Pos.Y, p.Pos.Z);
            Console.WriteLine($"  transform check: WMO {p.Fdid} at {wx:0},{wy:0},{wz:0} (rotation {p.Rot.X:0.#} {p.Rot.Y:0.#} {p.Rot.Z:0.#}, " +
                $"scale {p.Scale:0.###}, flags {p.Flags:x}): box {mn} {mx} vs extents {p.ExtMin} {p.ExtMax}");
        }
        devs.Sort();
        if (devs.Count == 0) return;
        Console.WriteLine($"transform check: {devs.Count} WMO placements, MOHD box through the transform vs MODF extents: " +
            $"median {devs[devs.Count / 2]:0.000}, 95% {devs[(int)(devs.Count * 0.95)]:0.000}, max {devs[^1]:0.000} yards, " +
            $"{devs.Count(d => d < 1)} within 1 yard, {contained} more inside larger extents (doodads), " +
            $"{devs.Count - devs.Count(d => d < 1) - contained} off");
    }

    /// <summary>The triangles of one ADT tile plus a border, then its Recast tiles.</summary>
    static void BuildAdt(Settings s, (int x, int y) k, ConcurrentDictionary<(int, int), AdtTile> adts,
        ConcurrentDictionary<uint, WmoModel> wmos, ConcurrentDictionary<uint, ModelMesh?> m2s, HashSet<int> blocked,
        TileResult res)
    {
        var pad = (s.Border + 2) * s.Cs + 1;
        float x0 = (float)(k.x * Frame.Tile) - pad, z0 = (float)(k.y * Frame.Tile) - pad;
        float x1 = (float)((k.x + 1) * Frame.Tile) + pad, z1 = (float)((k.y + 1) * Frame.Tile) + pad;
        var verts = new List<float>(1 << 20);
        var areas = new List<int>(1 << 18);
        var liquids = new List<LiquidTri>();
        var cosSlope = MathF.Cos(s.MaxSlope / 180f * MathF.PI);

        void Tri(Vector3 a, Vector3 b, Vector3 c, int area, bool fixWinding)
        {
            var n = Vector3.Cross(b - a, c - a);
            var len = n.Length();
            if (len < 1e-9f) return;
            if (fixWinding && n.Y < 0) { (b, c) = (c, b); n = -n; }
            if (n.Y / len <= cosSlope) area = 0;
            verts.Add(a.X); verts.Add(a.Y); verts.Add(a.Z);
            verts.Add(b.X); verts.Add(b.Y); verts.Add(b.Z);
            verts.Add(c.X); verts.Add(c.Y); verts.Add(c.Z);
            areas.Add(area);
        }
        bool Overlaps(Vector3 mn, Vector3 mx) => mx.X >= x0 && mn.X <= x1 && mx.Z >= z0 && mn.Z <= z1;

        // terrain of this tile and the neighbours' border cells
        for (var ny = k.y - 1; ny <= k.y + 1; ny++)
        for (var nx = k.x - 1; nx <= k.x + 1; nx++)
        {
            if (!adts.TryGetValue((nx, ny), out var t)) continue;
            for (var ch = 0; ch < 256; ch++)
            {
                var h = t.Heights[ch];
                if (h == null) continue;
                int ix = ch % 16, iy = ch / 16;
                var cx = (nx * 16 + ix) * Frame.Chunk;
                var cz = (ny * 16 + iy) * Frame.Chunk;
                if (cx + Frame.Chunk < x0 || cx > x1 || cz + Frame.Chunk < z0 || cz > z1) continue;
                for (var r = 0; r < 8; r++)
                for (var col = 0; col < 8; col++)
                {
                    if (((t.Holes[ch] >> (r * 8 + col)) & 1) != 0) continue;
                    float px = (float)(cx + col * Frame.Unit), pz = (float)(cz + r * Frame.Unit), u = (float)Frame.Unit;
                    if (px + u < x0 || px > x1 || pz + u < z0 || pz > z1) continue;
                    var a = new Vector3(px, h[r * 17 + col], pz);
                    var b = new Vector3(px + u, h[r * 17 + col + 1], pz);
                    var cc = new Vector3(px + u, h[(r + 1) * 17 + col + 1], pz + u);
                    var d = new Vector3(px, h[(r + 1) * 17 + col], pz + u);
                    var m = new Vector3(px + u / 2, h[r * 17 + 9 + col], pz + u / 2);
                    var area = t.Road[(iy * 8 + r) * 128 + ix * 8 + col] >= s.RoadMin ? AreaRoad : AreaGround;
                    Tri(m, a, b, area, true); Tri(m, b, cc, area, true); Tri(m, cc, d, area, true); Tri(m, d, a, area, true);
                }
            }
            foreach (var l in t.Liquids)
                if (Overlaps(Vector3.Min(l.A, Vector3.Min(l.B, l.C)), Vector3.Max(l.A, Vector3.Max(l.B, l.C)))) liquids.Add(l);
        }

        // objects of the 3 x 3 tiles, once each (a placement is listed in every ADT it overlaps), by unique id
        var objs = new SortedDictionary<uint, Placement>();
        for (var ny = k.y - 1; ny <= k.y + 1; ny++)
        for (var nx = k.x - 1; nx <= k.x + 1; nx++)
            if (adts.TryGetValue((nx, ny), out var t))
                foreach (var p in t.Placements)
                    objs.TryAdd(p.UniqueId ^ (p.Wmo ? 0x80000000u : 0u), p);
        void Place(ModelMesh mesh, Xf xf, bool indoorAware)
        {
            if (mesh.Tris.Length == 0) return;
            var (mn, mx) = (new Vector3(float.MaxValue), new Vector3(float.MinValue));
            for (var i = 0; i < 8; i++)
            {
                var v = xf.M.Mul(new Vector3((i & 1) != 0 ? mesh.Max.X : mesh.Min.X, (i & 2) != 0 ? mesh.Max.Y : mesh.Min.Y,
                    (i & 4) != 0 ? mesh.Max.Z : mesh.Min.Z)) + xf.T;
                mn = Vector3.Min(mn, v); mx = Vector3.Max(mx, v);
            }
            if (!Overlaps(mn, mx)) return;
            res.Objects++;
            var w = new Vector3[mesh.Verts.Length / 3];
            for (var i = 0; i < w.Length; i++)
                w[i] = xf.M.Mul(new Vector3(mesh.Verts[i * 3], mesh.Verts[i * 3 + 1], mesh.Verts[i * 3 + 2])) + xf.T;
            for (var t = 0; t < mesh.Tris.Length / 3; t++)
            {
                Vector3 a = w[mesh.Tris[t * 3]], b = w[mesh.Tris[t * 3 + 1]], c = w[mesh.Tris[t * 3 + 2]];
                if (Math.Max(a.X, Math.Max(b.X, c.X)) < x0 || Math.Min(a.X, Math.Min(b.X, c.X)) > x1
                    || Math.Max(a.Z, Math.Max(b.Z, c.Z)) < z0 || Math.Min(a.Z, Math.Min(b.Z, c.Z)) > z1) continue;
                Tri(a, b, c, indoorAware && (mesh.TriFlags[t] & 1) != 0 ? AreaIndoor : AreaGround, false);
            }
        }
        foreach (var p in objs.Values)
        {
            var xf = PlacementXf(p);
            if (!p.Wmo)
            {
                if (m2s.TryGetValue(p.Fdid, out var m) && m != null) Place(m, xf, false);
                continue;
            }
            if (!wmos.TryGetValue(p.Fdid, out var w) || w.Error != null) continue;
            Place(w.Mesh, xf, true);
            foreach (var (a, b, c, type) in w.Liquids)
            {
                var l = new LiquidTri(xf.M.Mul(a) + xf.T, xf.M.Mul(b) + xf.T, xf.M.Mul(c) + xf.T, type);
                if (Overlaps(Vector3.Min(l.A, Vector3.Min(l.B, l.C)), Vector3.Max(l.A, Vector3.Max(l.B, l.C)))) liquids.Add(l);
            }
            // the doodads of set 0 (always shown) and of the placement's set
            for (var si = 0; si < w.Sets.Count; si++)
            {
                if (si != 0 && si != p.DoodadSet) continue;
                var (first, count) = w.Sets[si];
                for (var di = first; di < first + count && di < w.Doodads.Count; di++)
                {
                    var d = w.Doodads[di];
                    if (d.Fdid == 0 || !m2s.TryGetValue(d.Fdid, out var m) || m == null || m.Tris.Length == 0) continue;
                    var inner = Matrix3.Q(d.Rot) * Matrix3.Scale(d.Scale);
                    Place(m, new Xf(xf.M * inner, xf.M.Mul(d.Pos) + xf.T), false);
                }
            }
        }
        res.SolidTris = areas.Count;
        res.LiquidTris = liquids.Count;
        if (areas.Count == 0) return;

        var vArr = verts.ToArray();
        var aArr = areas.ToArray();
        float ymin = float.MaxValue, ymax = float.MinValue;
        for (var i = 1; i < vArr.Length; i += 3) { ymin = Math.Min(ymin, vArr[i]); ymax = Math.Max(ymax, vArr[i]); }
        foreach (var l in liquids)
        {
            ymin = Math.Min(ymin, Math.Min(l.A.Y, Math.Min(l.B.Y, l.C.Y)));
            ymax = Math.Max(ymax, Math.Max(l.A.Y, Math.Max(l.B.Y, l.C.Y)));
        }
        ymin -= 2; ymax += 2 + s.AgentHeight;
        for (var j = 0; j < s.Split; j++)
        for (var i = 0; i < s.Split; i++)
        {
            try
            {
                var tile = BuildTile(s, k.x * s.Split + i, k.y * s.Split + j, vArr, aArr, liquids, blocked, ymin, ymax);
                if (tile != null) res.Tiles.Add(tile.Value);
            }
            catch (Exception e)
            {
                res.Failed.Add($"{k.x * s.Split + i},{k.y * s.Split + j}: {e.Message}");
            }
        }
    }

    static (int tx, int tz, byte[] data, int polys, int verts, int dtris)? BuildTile(Settings s, int tx, int tz,
        float[] verts, int[] areas, List<LiquidTri> liquids, HashSet<int> blocked, float ymin, float ymax)
    {
        var cs = s.Cs;
        var tw = (float)(Frame.Tile / s.Split);
        var border = s.Border;
        var size = s.TileCells + 2 * border;
        var bmin = new RcVec3f(tx * tw - border * cs, ymin, tz * tw - border * cs);
        var bmax = new RcVec3f((tx + 1) * tw + border * cs, ymax, (tz + 1) * tw + border * cs);
        var ctx = new RcContext();
        var hf = new RcHeightfield(size, size, bmin, bmax, cs, s.Ch, border);
        RcRasterizations.RasterizeTriangles(ctx, verts, areas, areas.Length, hf, s.ClimbCells);
        RcFilters.FilterLowHangingWalkableObstacles(ctx, s.ClimbCells, hf);
        RcFilters.FilterLedgeSpans(ctx, s.HeightCells, s.ClimbCells, hf);
        RcFilters.FilterWalkableLowHeightSpans(ctx, s.HeightCells, hf);
        ApplyLiquids(s, hf, liquids, blocked);

        // watershed regions (TrinityCore's choice); where they fail (Recast: "overlaps may occur if you have narrow
        // spiral corridors"), the tile is built again with monotone regions, which cannot overlap
        RcCompactHeightfield chf;
        RcPolyMesh pmesh;
        try { (chf, pmesh) = Polygons(s, ctx, hf, false); }
        catch (Exception)
        {
            (chf, pmesh) = Polygons(s, ctx, hf, true);
            Interlocked.Increment(ref fallbacks);
        }
        if (pmesh.npolys == 0) return null;
        var dmesh = RcMeshDetails.BuildPolyMeshDetail(ctx, pmesh, chf, s.DetailSampleDist * cs, s.DetailMaxError * s.Ch);
        for (var i = 0; i < pmesh.npolys; i++)
            pmesh.flags[i] = pmesh.areas[i] switch
            {
                AreaRoad => FlagWalk | FlagRoad,
                AreaShallow => FlagWalk | FlagShallow,
                AreaDeep => FlagSwim,
                AreaIndoor => FlagWalk | FlagIndoor,
                AreaBlocked => FlagBlocked,
                _ => FlagWalk,
            };
        var p = new DtNavMeshCreateParams
        {
            verts = pmesh.verts, vertCount = pmesh.nverts, polys = pmesh.polys, polyAreas = pmesh.areas,
            polyFlags = pmesh.flags, polyCount = pmesh.npolys, nvp = pmesh.nvp,
            detailMeshes = dmesh?.meshes, detailVerts = dmesh?.verts, detailVertsCount = dmesh?.nverts ?? 0,
            detailTris = dmesh?.tris, detailTriCount = dmesh?.ntris ?? 0,
            tileX = tx, tileZ = tz, tileLayer = 0, bmin = pmesh.bmin, bmax = pmesh.bmax,
            walkableHeight = s.AgentHeight, walkableRadius = s.AgentRadius, walkableClimb = s.AgentClimb,
            cs = cs, ch = s.Ch, buildBvTree = true,
        };
        var data = DtNavMeshBuilder.CreateNavMeshData(p)
            ?? throw new InvalidOperationException($"tile {tx},{tz}: Detour refused the mesh ({pmesh.nverts} verts)");
        using var ms = new MemoryStream();
        using (var bw = new BinaryWriter(ms, System.Text.Encoding.UTF8, true))
            new DtMeshDataWriter().Write(bw, data, RcByteOrder.LITTLE_ENDIAN, false);
        return (tx, tz, ms.ToArray(), data.header.polyCount, data.header.vertCount, data.header.detailTriCount);
    }

    static (RcCompactHeightfield, RcPolyMesh) Polygons(Settings s, RcContext ctx, RcHeightfield hf, bool monotone)
    {
        var chf = RcCompacts.BuildCompactHeightfield(ctx, s.HeightCells, s.ClimbCells, hf);
        var empty = new RcPolyMesh { npolys = 0 };
        if (chf.spanCount == 0) return (chf, empty);
        RcAreas.ErodeWalkableArea(ctx, s.RadiusCells, chf);
        if (monotone) RcRegions.BuildRegionsMonotone(ctx, chf, s.MinRegion, s.MergeRegion);
        else
        {
            RcRegions.BuildDistanceField(ctx, chf);
            RcRegions.BuildRegions(ctx, chf, s.MinRegion, s.MergeRegion);
        }
        var cset = RcContours.BuildContours(ctx, chf, s.MaxError, s.TileCells + 1, RcBuildContoursFlags.RC_CONTOUR_TESS_WALL_EDGES);
        if (cset.conts.Count == 0) return (chf, empty);
        return (chf, RcMeshs.BuildPolyMesh(ctx, cset, DtDetour.DT_VERTS_PER_POLYGON));
    }

    static int fallbacks;

    /// <summary>Liquids on the spans, per column at the cell centre: the highest solid span top at or below the
    /// surface is the floor. Blocked liquid: the floor becomes blocked. At most swim_depth of water: the floor
    /// becomes shallow. Deeper: the floor is dropped and a one-cell span at the surface is added (deep). A column
    /// whose solid spans reach through the surface (a wall, a pier post) is left alone.</summary>
    static void ApplyLiquids(Settings s, RcHeightfield hf, List<LiquidTri> liquids, HashSet<int> blocked)
    {
        if (liquids.Count == 0) return;
        var cs = hf.cs;
        var surfaces = new Dictionary<int, List<(float y, int type)>>();
        foreach (var l in liquids)
        {
            var mn = Vector3.Min(l.A, Vector3.Min(l.B, l.C));
            var mx = Vector3.Max(l.A, Vector3.Max(l.B, l.C));
            int cx0 = Math.Max(0, (int)Math.Floor((mn.X - hf.bmin.X) / cs)), cx1 = Math.Min(hf.width - 1, (int)Math.Floor((mx.X - hf.bmin.X) / cs));
            int cz0 = Math.Max(0, (int)Math.Floor((mn.Z - hf.bmin.Z) / cs)), cz1 = Math.Min(hf.height - 1, (int)Math.Floor((mx.Z - hf.bmin.Z) / cs));
            for (var cz = cz0; cz <= cz1; cz++)
            for (var cx = cx0; cx <= cx1; cx++)
            {
                float px = hf.bmin.X + (cx + 0.5f) * cs, pz = hf.bmin.Z + (cz + 0.5f) * cs;
                var y = Bary(l, px, pz);
                if (y == null) continue;
                var key = cz * hf.width + cx;
                if (!surfaces.TryGetValue(key, out var list)) surfaces[key] = list = [];
                if (!list.Any(e => Math.Abs(e.y - y.Value) < 0.5f)) list.Add((y.Value, l.Type));
            }
        }
        var swim = (int)Math.Floor(s.SwimDepth / hf.ch);
        foreach (var key in surfaces.Keys.Order())
        {
            int cx = key % hf.width, cz = key / hf.width;
            foreach (var (y, type) in surfaces[key].OrderBy(e => e.y))
            {
                var sy = (int)Math.Floor((y - hf.bmin.Y) / hf.ch);
                if (sy < 1 || sy >= RcRecast.RC_SPAN_MAX_HEIGHT) continue;
                RcSpan? floor = null;
                var wall = false;
                for (var sp = hf.spans[key]; sp != null; sp = sp.next)
                {
                    if (sp.smin <= sy && sp.smax > sy) { wall = true; break; }
                    if (sp.smax <= sy) floor = sp;
                }
                if (wall) continue;
                var depth = floor == null ? int.MaxValue : sy - floor.smax;
                if (blocked.Contains(type))
                {
                    if (floor != null && floor.area != RcRecast.RC_NULL_AREA) floor.area = AreaBlocked;
                    continue;
                }
                if (floor != null && depth <= swim)
                {
                    if (floor.area != RcRecast.RC_NULL_AREA) floor.area = AreaShallow;
                    continue;
                }
                if (floor != null) floor.area = RcRecast.RC_NULL_AREA;
                RcRasterizations.AddSpan(hf, cx, cz, sy - 1, sy, AreaDeep, 0);
            }
        }
    }

    static float? Bary(LiquidTri t, float px, float pz)
    {
        float x1 = t.A.X, z1 = t.A.Z, x2 = t.B.X, z2 = t.B.Z, x3 = t.C.X, z3 = t.C.Z;
        var det = (z2 - z3) * (x1 - x3) + (x3 - x2) * (z1 - z3);
        if (Math.Abs(det) < 1e-9f) return null;
        var l1 = ((z2 - z3) * (px - x3) + (x3 - x2) * (pz - z3)) / det;
        var l2 = ((z3 - z1) * (px - x3) + (x1 - x3) * (pz - z3)) / det;
        var l3 = 1 - l1 - l2;
        const float e = -1e-4f;
        if (l1 < e || l2 < e || l3 < e) return null;
        return l1 * t.A.Y + l2 * t.B.Y + l3 * t.C.Y;
    }

    /// <summary>The file, see docs/data/client-extraction.md "Navmesh": header, settings, Detour parameters, an
    /// index per ADT tile and per ADT tile one zlib block of its Recast tiles (DtMeshDataWriter, little endian,
    /// the recast4j layout DtMeshDataReader reads). Version 2 adds the terrain chunks' AreaTable ids: one zlib
    /// block of i32 x, i32 y and 256 u32 (chunk iy * 16 + ix) per built ADT tile.</summary>
    static long Write(string path, Settings s, int mapId, string build, TileResult[] results)
    {
        var blocks = results.Where(r => r.Tiles.Count > 0).Select(r =>
        {
            using var raw = new MemoryStream();
            using (var z = new ZLibStream(raw, CompressionLevel.SmallestSize, true))
            using (var w = new BinaryWriter(z))
            {
                foreach (var t in r.Tiles)
                {
                    w.Write(t.tx); w.Write(t.tz); w.Write(t.data.Length); w.Write(t.data);
                }
            }
            return (r.X, r.Y, n: r.Tiles.Count, data: raw.ToArray());
        }).ToList();
        byte[] areaBlock;
        using (var raw = new MemoryStream())
        {
            using (var z = new ZLibStream(raw, CompressionLevel.SmallestSize, true))
            using (var aw = new BinaryWriter(z))
                foreach (var r in results)
                {
                    aw.Write(r.X); aw.Write(r.Y);
                    foreach (var id in r.AreaIds) aw.Write(id);
                }
            areaBlock = raw.ToArray();
        }
        var tmp = path + ".tmp";
        using (var f = File.Create(tmp))
        using (var w = new BinaryWriter(f))
        {
            w.Write("BNAV"u8.ToArray());
            w.Write(2u);
            w.Write(mapId);
            var b = System.Text.Encoding.UTF8.GetBytes(build);
            w.Write((byte)b.Length); w.Write(b);
            // settings
            w.Write(s.Cs); w.Write(s.Ch); w.Write(s.AgentHeight); w.Write(s.AgentRadius); w.Write(s.AgentClimb);
            w.Write(s.MaxSlope); w.Write(s.SwimDepth); w.Write(s.Split); w.Write(s.TileCells);
            // Detour navmesh parameters: origin, tile size, max tiles, max polys per tile
            w.Write(0f); w.Write(0f); w.Write(0f);
            w.Write((float)(Frame.Tile / s.Split)); w.Write((float)(Frame.Tile / s.Split));
            w.Write(64 * s.Split * 64 * s.Split);
            w.Write(1 << 16);
            w.Write(blocks.Count);
            long offset = 4 + 4 + 4 + 1 + b.Length + 9 * 4 + 7 * 4 + 4 + blocks.Count * 20L + 12;
            foreach (var bl in blocks)
            {
                w.Write(bl.X); w.Write(bl.Y); w.Write(bl.n); w.Write((int)offset); w.Write(bl.data.Length);
                offset += bl.data.Length;
            }
            w.Write(results.Length); w.Write((int)offset); w.Write(areaBlock.Length);
            foreach (var bl in blocks) w.Write(bl.data);
            w.Write(areaBlock);
        }
        File.Move(tmp, path, true);
        return new FileInfo(path).Length;
    }

    static void WriteSummary(string path, Settings s, int mapId, string dir, Client c, TileResult[] results,
        double buildSeconds, double totalSeconds, long size, ConcurrentDictionary<(int, int), AdtTile> adts,
        ConcurrentDictionary<uint, WmoModel> wmos, ConcurrentDictionary<uint, ModelMesh?> m2s)
    {
        var tmp = path + ".tmp";
        using (var f = File.Create(tmp))
        using (var w = new Utf8JsonWriter(f, new JsonWriterOptions { Indented = true }))
        {
            w.WriteStartObject();
            w.WriteNumber("map", mapId);
            w.WriteString("directory", dir);
            w.WriteString("product", c.Product);
            w.WriteString("build", c.Version);
            w.WriteStartObject("settings");
            w.WriteNumber("cs", Math.Round(s.Cs, 5)); w.WriteNumber("ch", Math.Round(s.Ch, 5));
            w.WriteNumber("agent_height", s.AgentHeight); w.WriteNumber("agent_radius", Math.Round(s.AgentRadius, 5));
            w.WriteNumber("agent_climb", s.AgentClimb); w.WriteNumber("max_slope", s.MaxSlope);
            w.WriteNumber("split", s.Split); w.WriteNumber("tile_cells", s.TileCells); w.WriteNumber("border", s.Border);
            w.WriteNumber("min_region", s.MinRegion); w.WriteNumber("merge_region", s.MergeRegion);
            w.WriteNumber("max_error", s.MaxError); w.WriteNumber("detail_sample_dist", s.DetailSampleDist);
            w.WriteNumber("detail_max_error", s.DetailMaxError); w.WriteNumber("swim_depth", s.SwimDepth);
            w.WriteNumber("road_min", s.RoadMin);
            w.WriteEndObject();
            w.WriteStartObject("totals");
            w.WriteNumber("adt_tiles", results.Length);
            w.WriteNumber("adt_tiles_with_mesh", results.Count(r => r.Tiles.Count > 0));
            w.WriteNumber("adt_tiles_failed", results.Count(r => r.Error != null));
            w.WriteNumber("recast_tiles", results.Sum(r => r.Tiles.Count));
            w.WriteNumber("recast_tiles_monotone", fallbacks);
            w.WriteNumber("recast_tiles_failed", results.Sum(r => r.Failed.Count));
            w.WriteNumber("polys", results.Sum(r => r.Tiles.Sum(t => t.polys)));
            w.WriteNumber("verts", results.Sum(r => r.Tiles.Sum(t => t.verts)));
            w.WriteNumber("detail_tris", results.Sum(r => r.Tiles.Sum(t => t.dtris)));
            w.WriteNumber("tile_bytes", results.Sum(r => r.Tiles.Sum(t => (long)t.data.Length)));
            w.WriteNumber("file_bytes", size);
            w.WriteNumber("wmos", wmos.Count);
            w.WriteNumber("m2s", m2s.Count);
            w.WriteNumber("m2s_with_collision", m2s.Values.Count(m => m is { Tris.Length: > 0 }));
            w.WriteNumber("build_seconds", Math.Round(buildSeconds, 1));
            w.WriteNumber("total_seconds", Math.Round(totalSeconds, 1));
            w.WriteEndObject();
            w.WriteStartArray("tiles");
            foreach (var r in results)
            {
                w.WriteStartObject();
                w.WriteNumber("x", r.X); w.WriteNumber("y", r.Y);
                w.WriteNumber("recast_tiles", r.Tiles.Count);
                w.WriteNumber("polys", r.Tiles.Sum(t => t.polys));
                w.WriteNumber("verts", r.Tiles.Sum(t => t.verts));
                w.WriteNumber("bytes", r.Tiles.Sum(t => t.data.Length));
                w.WriteNumber("solid_tris", r.SolidTris);
                w.WriteNumber("liquid_tris", r.LiquidTris);
                w.WriteNumber("objects", r.Objects);
                w.WriteNumber("ms", r.Ms);
                if (r.Error != null) w.WriteString("error", r.Error);
                if (r.Failed.Count > 0)
                {
                    w.WriteStartArray("failed");
                    foreach (var failed in r.Failed) w.WriteStringValue(failed);
                    w.WriteEndArray();
                }
                w.WriteEndObject();
            }
            w.WriteEndArray();
            w.WriteEndObject();
        }
        File.Move(tmp, path, true);
    }
}
