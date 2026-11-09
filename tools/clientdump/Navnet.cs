// The local level of the world graph from one continent's navmesh (ADR 0026, world-graph.md §6.2, data.md "The
// build in two halves", W3a): waypoints (the given nodes, doors between indoors and outdoors, road junctions and
// bends, open ground about every 100 yards), the ways between neighbouring waypoints along the mesh with their
// facts, and the anchors of the given places. Opens no client: everything comes from the .navmesh file (version
// 2 carries the terrain chunks' AreaTable ids). Output JSON in world yards (x = wx, y = wy, z), 0.1 yards.
// Deterministic: fixed orders everywhere, parallel work goes into fixed slots.
using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using DotRecast.Core.Numerics;
using DotRecast.Detour;

namespace ClientDump;

static class Navnet
{
    sealed class Config
    {
        public double Spacing { get; set; } = 150;          // yards between ground waypoints (100 until the pack budget, 25.10.2026)
        public double WaterSpacing { get; set; } = 300;     // on water only (deep): every second lattice cell
        public double LayerGap { get; set; } = 12;          // yards between two walkable layers in one lattice cell
        public double MinLayerArea { get; set; } = 150;     // yd² of polygons a layer needs for a ground waypoint
        public double MinComponentArea { get; set; } = 10000; // yd²: smaller islands and roofs are dropped unless a node is on them
        public int Neighbours { get; set; } = 8;            // ways tried per waypoint
        public int Sectors { get; set; } = 8;               // and the nearest in each of this many directions (0: off)
        public double Radius { get; set; } = 400;           // yards searched for neighbours
        public double Stretch { get; set; } = 1.10;         // a way goes when the kept ones walk it within this factor
        public double BorderStretch { get; set; } = 1.25;   // the same for a way across a cluster border
        public double RoadCell { get; set; } = 2;           // yards per pixel of the road raster
        public int RoadClose { get; set; } = 2;             // pixels of closing (tree and lamp holes in the road)
        public double RoadMinBlob { get; set; } = 200;      // yd²: smaller road pieces are no road
        public double RoadSpur { get; set; } = 25;          // yards: shorter dead ends of the road skeleton are dropped
        public double RoadSimplify { get; set; } = 12;      // yards of Douglas-Peucker tolerance: what remains are bends
        public double RoadMaxGap { get; set; } = 200;       // yards: longer straight roads get waypoints in between
        public double RoadMerge { get; set; } = 25;         // yards: road waypoints closer than this are one
        public double DoorMerge { get; set; } = 8;          // yards: door candidates closer than this are one door
        public double GroundClear { get; set; } = 60;       // yards: no ground waypoint this near another waypoint
        public double NodeSnap { get; set; } = 30;          // yards a given node may be from the mesh
        public double PlaceSnap { get; set; } = 60;         // yards a place may be from the mesh
        public double AnchorRadius { get; set; } = 400;     // yards searched for an anchor's waypoint
        public int AnchorCandidates { get; set; } = 6;
        public double StitchRadius { get; set; } = 2000;    // yards searched when joining parts of one mesh region
        public int StitchCandidates { get; set; } = 12;
        public int MaxIter { get; set; } = 20000;           // A* nodes per way (a way needing more is not taken)
        public int StitchMaxIter { get; set; } = 200000;
        public double Simplify { get; set; } = 2;           // yards of tolerance for the bends of a way
        public double CostGround { get; set; } = 1;
        public double CostRoad { get; set; } = 0.55;        // nav.toml road_factor: paths keep to the roads
        public double CostShallow { get; set; } = 1.5;
        public double CostDeep { get; set; } = 3;           // nav.toml swim_factor
        public double CostIndoor { get; set; } = 1;
        public List<HiddenGround> Hidden { get; set; } = [];
    }

    /// <summary>A box of open ground the mesh can walk but nobody does: Forever's flat sheet of terrain 40 yards under
    /// Stormwind's streets (pipeline/config/nav.toml [[hidden.forever]]; route.md "The join"). World yards.</summary>
    sealed record HiddenGround(int Continent, double[] Wx, double[] Wy, double[] Z);

    sealed record NodeIn(string Id, int Continent, double Wx, double Wy, double? Wz = null);
    sealed record PlaceIn(string Ref, int I, double X, double Y, double? Z = null);

    sealed class Wp
    {
        public int Id;
        public string Kind = "";
        public string? Key;
        public long Ref;
        public RcVec3f P;  // recast frame
        public int Comp;
    }

    sealed class Way
    {
        public int A, B;
        public double Len, Road, Swim, Indoor, Up, Down;
        public int? Area;
        public List<RcVec3f> Points = []; // bends, recast frame, without the ends
    }

    static float[] costs = [];
    static DtQueryDefaultFilter filter = null!;
    static NavmeshFile file = null!;
    static DtNavMesh mesh = null!;
    static int[] tileBase = [];
    static long[] refOf = [];
    static byte[] areaOf = [];
    static int[] compOf = [];
    static float[] polyArea = [];
    static bool[] keptComp = [];

    static int Gid(long r) => tileBase[DtDetour.DecodePolyIdTile(r)] + DtDetour.DecodePolyIdPoly(r);

    public static void Run(string meshPath, string nodesPath, string? placesPath, string? configPath, string outPath,
        string? client, string? pngPath, string? pngTiles)
    {
        var total = Stopwatch.StartNew();
        var json = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };
        var cfg = configPath != null ? JsonSerializer.Deserialize<Config>(File.ReadAllText(configPath), json) ?? new Config() : new Config();
        file = NavmeshFile.Open(meshPath);
        if (file.AreaIds.Count == 0) Console.Error.WriteLine("warning: navmesh version 1 has no area ids (rebuild it): areas stay null");
        client ??= file.Build.StartsWith("1.") ? "forever" : "retail";
        var continent = file.MapId;
        var nodes = (JsonSerializer.Deserialize<List<NodeIn>>(File.ReadAllText(nodesPath), json) ?? [])
            .Where(n => n.Continent == continent).ToList();
        var places = placesPath != null ? JsonSerializer.Deserialize<List<PlaceIn>>(File.ReadAllText(placesPath), json) ?? [] : [];

        // the mesh, its polygons and their regions
        var sw = Stopwatch.StartNew();
        var keys = file.Index.Keys.OrderBy(k => k.y).ThenBy(k => k.x).ToList();
        var datas = new List<DtMeshData>[keys.Count];
        Parallel.For(0, keys.Count, i => datas[i] = file.Read(keys[i].x, keys[i].y));
        mesh = file.NewMesh();
        foreach (var list in datas) foreach (var d in list) mesh.AddTile(d, 0, 0, out _);
        tileBase = new int[mesh.GetMaxTiles()];
        var n = 0;
        for (var i = 0; i < mesh.GetMaxTiles(); i++)
        {
            var t = mesh.GetTile(i);
            if (t?.data == null) continue;
            tileBase[i] = n;
            n += t.data.header.polyCount;
        }
        refOf = new long[n]; areaOf = new byte[n]; polyArea = new float[n];
        var parent = new int[n];
        for (var i = 0; i < n; i++) parent[i] = i;
        int Find(int x) { while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; }
        for (var i = 0; i < mesh.GetMaxTiles(); i++)
        {
            var t = mesh.GetTile(i);
            if (t?.data == null) continue;
            for (var ip = 0; ip < t.data.header.polyCount; ip++)
            {
                var p = t.data.polys[ip];
                var g = tileBase[i] + ip;
                refOf[g] = DtDetour.EncodePolyId(t.salt, t.index, ip);
                areaOf[g] = (byte)p.GetArea();
                polyArea[g] = PolyArea(t, p);
            }
        }
        // before the regions: what is hidden joins nothing, and every query's filter leaves it out
        var hiddenBoxes = cfg.Hidden.Where(h => h.Continent == file.MapId).ToList();
        var hidden = 0;
        if (hiddenBoxes.Count > 0)
            for (var i = 0; i < mesh.GetMaxTiles(); i++)
            {
                var t = mesh.GetTile(i);
                if (t?.data == null) continue;
                for (var ip = 0; ip < t.data.header.polyCount; ip++)
                {
                    var g = tileBase[i] + ip;
                    if (areaOf[g] is not (Navmesh.AreaGround or Navmesh.AreaRoad)) continue;
                    var c = mesh.GetPolyCenter(refOf[g]);
                    var (wx, wy, wz) = Frame.ToWorld(c.X, c.Y, c.Z);
                    if (!hiddenBoxes.Any(h => wx >= h.Wx[0] && wx <= h.Wx[1] && wy >= h.Wy[0] && wy <= h.Wy[1] && wz >= h.Z[0] && wz <= h.Z[1])) continue;
                    areaOf[g] = Navmesh.AreaBlocked;
                    t.data.polys[ip].flags = Navmesh.FlagBlocked;
                    hidden++;
                }
            }
        if (hiddenBoxes.Count > 0) Console.WriteLine($"hidden ground: {hidden} polygons left out");
        for (var i = 0; i < mesh.GetMaxTiles(); i++)
        {
            var t = mesh.GetTile(i);
            if (t?.data == null) continue;
            for (var ip = 0; ip < t.data.header.polyCount; ip++)
            {
                var g = tileBase[i] + ip;
                if (areaOf[g] == Navmesh.AreaBlocked) continue;
                for (var j = t.data.polys[ip].firstLink; j != DtDetour.DT_NULL_LINK; j = t.links[j].next)
                {
                    var o = Gid(t.links[j].refs);
                    if (areaOf[o] == Navmesh.AreaBlocked) continue;
                    int ra = Find(g), rb = Find(o);
                    if (ra != rb) parent[Math.Max(ra, rb)] = Math.Min(ra, rb);
                }
            }
        }
        compOf = new int[n];
        var compArea = new Dictionary<int, double>();
        for (var i = 0; i < n; i++)
        {
            compOf[i] = Find(i);
            compArea[compOf[i]] = compArea.GetValueOrDefault(compOf[i]) + polyArea[i];
        }
        keptComp = new bool[n];
        foreach (var (c, a) in compArea) if (a >= cfg.MinComponentArea) keptComp[c] = true;
        costs = new float[64];
        Array.Fill(costs, 1f);
        costs[Navmesh.AreaGround] = (float)cfg.CostGround; costs[Navmesh.AreaRoad] = (float)cfg.CostRoad;
        costs[Navmesh.AreaShallow] = (float)cfg.CostShallow; costs[Navmesh.AreaDeep] = (float)cfg.CostDeep;
        costs[Navmesh.AreaIndoor] = (float)cfg.CostIndoor;
        filter = new DtQueryDefaultFilter(0xffff & ~Navmesh.FlagBlocked, Navmesh.FlagBlocked, costs);
        var query = new ThreadLocal<DtNavMeshQuery>(() => new DtNavMeshQuery(mesh));
        Console.WriteLine($"navnet: map {continent} ({client} {file.Build}), {keys.Count} ADT tiles, {n} polys, " +
            $"{compArea.Count} regions, {compArea.Count(kv => kv.Value >= cfg.MinComponentArea)} of at least " +
            $"{cfg.MinComponentArea} yd², loaded in {sw.Elapsed.TotalSeconds:0.0} s");

        // 1. the given nodes (their regions are kept whatever their size)
        sw.Restart();
        var wps = new List<Wp>();
        var unplaced = new List<string>();
        foreach (var nd in nodes)
        {
            var (rx, _, rz) = Frame.FromWorld(nd.Wx, nd.Wy, 0);
            var s = Snap(query.Value!, rx, nd.Wz, rz, cfg.NodeSnap, false, false);
            if (s == null) { unplaced.Add($"{nd.Id} (no mesh within {cfg.NodeSnap} yards)"); continue; }
            keptComp[compOf[Gid(s.Value.r)]] = true;
            wps.Add(new Wp { Kind = "node", Key = nd.Id, Ref = s.Value.r, P = s.Value.p, Comp = compOf[Gid(s.Value.r)] });
        }
        var nodeCount = wps.Count;

        // 2. doors: where an indoor polygon meets a walkable outdoor one
        var doors = Doors(cfg, query.Value!);
        wps.AddRange(doors);

        // 3. roads: junctions, ends and bends of the road skeleton
        var roads = Roads(cfg, query.Value!, wps);
        wps.AddRange(roads);

        // 4. open ground, one per lattice cell and walkable layer
        var ground = Ground(cfg, query, wps);
        wps.AddRange(ground);
        for (var i = 0; i < wps.Count; i++) wps[i].Id = i + 1;
        Console.WriteLine($"waypoints: {wps.Count} ({nodeCount} node, {doors.Count} door, {roads.Count} road, {ground.Count} ground) " +
            $"in {sw.Elapsed.TotalSeconds:0.0} s; {unplaced.Count} nodes not on the mesh");
        foreach (var u in unplaced) Console.WriteLine("  node not placed: " + u);

        // 5. ways between neighbours
        sw.Restart();
        var grid = new Dictionary<(int, int), List<int>>();
        const double bucket = 100;
        for (var i = 0; i < wps.Count; i++)
        {
            var key = ((int)Math.Floor(wps[i].P.X / bucket), (int)Math.Floor(wps[i].P.Z / bucket));
            if (!grid.TryGetValue(key, out var l)) grid[key] = l = [];
            l.Add(i);
        }
        IEnumerable<int> Near(RcVec3f p, double radius)
        {
            int bx0 = (int)Math.Floor((p.X - radius) / bucket), bx1 = (int)Math.Floor((p.X + radius) / bucket);
            int bz0 = (int)Math.Floor((p.Z - radius) / bucket), bz1 = (int)Math.Floor((p.Z + radius) / bucket);
            for (var bz = bz0; bz <= bz1; bz++)
            for (var bx = bx0; bx <= bx1; bx++)
                if (grid.TryGetValue((bx, bz), out var l))
                    foreach (var i in l) yield return i;
        }
        double Dist(RcVec3f a, RcVec3f b) => Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Z - b.Z) * (a.Z - b.Z) + 4 * (a.Y - b.Y) * (a.Y - b.Y));
        var pairs = new SortedSet<(int, int)>();
        for (var i = 0; i < wps.Count; i++)
        {
            var a = wps[i];
            var near = Near(a.P, cfg.Radius).Where(j => j != i && wps[j].Comp == a.Comp)
                .Select(j => (j, d: Dist(a.P, wps[j].P))).Where(e => e.d <= cfg.Radius)
                .OrderBy(e => e.d).ThenBy(e => e.j).ToList();
            foreach (var e in near.Take(cfg.Neighbours))
                pairs.Add((Math.Min(i, e.j), Math.Max(i, e.j)));
            // the nearest in each direction too: along a dense road the nearest few are all road waypoints
            // in a row, and the open ground beside it got no way (Elwynn's road
            // to Northshire, 417 yards over the network for 339 over the mesh)
            if (cfg.Sectors > 0)
            {
                var seen = new bool[cfg.Sectors];
                foreach (var e in near)
                {
                    var q = wps[e.j].P;
                    var angle = Math.Atan2(q.Z - a.P.Z, q.X - a.P.X) + Math.PI;
                    var sector = Math.Min((int)(angle / (2 * Math.PI) * cfg.Sectors), cfg.Sectors - 1);
                    if (seen[sector]) continue;
                    seen[sector] = true;
                    pairs.Add((Math.Min(i, e.j), Math.Max(i, e.j)));
                }
            }
        }
        var pairList = pairs.ToList();
        var found = new Way?[pairList.Count];
        Parallel.For(0, pairList.Count, () => (new long[1 << 16], new DtStraightPath[(1 << 16) + 4]), (k, _, buf) =>
        {
            var (i, j) = pairList[k];
            found[k] = Walk(query.Value!, wps[i], wps[j], cfg.MaxIter, buf.Item1, buf.Item2, cfg);
            if (found[k] != null) { found[k]!.A = i; found[k]!.B = j; }
            return buf;
        }, _ => { });
        var ways = found.Where(w => w != null).Select(w => w!).ToList();
        Console.WriteLine($"ways: {pairList.Count} pairs tried, {ways.Count} walked in {sw.Elapsed.TotalSeconds:0.0} s");

        // 6. a greedy spanner (replaces ADR 0025's triangle prune, 25.10.2026): the ways, shortest first, are
        // kept only when the network kept so far has no path between their ends within stretch times their
        // length; a way across a cluster border (2 x 2 ADT tiles, world-graph.md §6.2) needs border_stretch.
        // Every walk over the result is at most stretch (border_stretch) times the walk over all ways.
        var adj = new Dictionary<int, Dictionary<int, Way>>();
        void Link(Way w)
        {
            if (!adj.TryGetValue(w.A, out var da)) adj[w.A] = da = [];
            if (!adj.TryGetValue(w.B, out var db)) adj[w.B] = db = [];
            da[w.B] = w; db[w.A] = w;
        }
        (int, int) Cluster(RcVec3f p) => ((int)Math.Floor(p.X / Frame.Tile / 2), (int)Math.Floor(p.Z / Frame.Tile / 2));
        var pruned = 0;
        var dist = new Dictionary<int, double>();
        var heap = new PriorityQueue<int, double>();
        bool Within(int a, int b, double limit)
        {
            dist.Clear(); heap.Clear();
            dist[a] = 0; heap.Enqueue(a, 0);
            while (heap.TryDequeue(out var u, out var du))
            {
                if (u == b) return true;
                if (du > dist[u]) continue;
                if (!adj.TryGetValue(u, out var nb)) continue;
                foreach (var (v, w) in nb)
                {
                    var dv = du + w.Len;
                    if (dv > limit || dv >= dist.GetValueOrDefault(v, double.MaxValue)) continue;
                    dist[v] = dv; heap.Enqueue(v, dv);
                }
            }
            return false;
        }
        foreach (var w in ways.OrderBy(w => w.Len).ThenBy(w => w.A).ThenBy(w => w.B))
        {
            var stretch = Cluster(wps[w.A].P) != Cluster(wps[w.B].P) ? cfg.BorderStretch : cfg.Stretch;
            if (Within(w.A, w.B, stretch * w.Len)) { pruned++; continue; }
            Link(w);
        }

        // 7. stitch: every mesh region's waypoints into one network
        sw.Restart();
        var uf = new int[wps.Count];
        for (var i = 0; i < uf.Length; i++) uf[i] = i;
        int F(int x) { while (uf[x] != x) { uf[x] = uf[uf[x]]; x = uf[x]; } return x; }
        void U(int a, int b) { int ra = F(a), rb = F(b); if (ra != rb) uf[Math.Max(ra, rb)] = Math.Min(ra, rb); }
        foreach (var (a, d) in adj) foreach (var b in d.Keys) U(a, b);
        int stitched = 0, unjoined = 0;
        var pathBuf = new long[1 << 16];
        var spBuf = new DtStraightPath[(1 << 16) + 4];
        foreach (var comp in wps.Select(w => w.Comp).Distinct().Order().ToList())
        {
            var members = Enumerable.Range(0, wps.Count).Where(i => wps[i].Comp == comp).ToList();
            var failedGroups = new HashSet<int>();
            while (true)
            {
                var groups = members.GroupBy(F).Where(g => !failedGroups.Contains(g.Key)).OrderBy(g => g.Count()).ThenBy(g => g.Key).ToList();
                if (members.Select(F).Distinct().Count() <= 1 || groups.Count == 0) break;
                var g = groups[0];
                var inG = g.ToHashSet();
                var cands = new List<(double d, int u, int v)>();
                var step = Math.Max(1, inG.Count / 200); // a large part: every step-th of its waypoints
                foreach (var u in g.OrderBy(x => x).Where((_, i) => i % step == 0))
                    foreach (var v in Near(wps[u].P, cfg.StitchRadius))
                    {
                        if (wps[v].Comp != comp || F(v) == g.Key) continue;
                        var d = Dist(wps[u].P, wps[v].P);
                        if (d <= cfg.StitchRadius) cands.Add((d, u, v));
                    }
                Way? best = null;
                foreach (var (_, u, v) in cands.OrderBy(c => c.d).ThenBy(c => c.u).ThenBy(c => c.v).Take(cfg.StitchCandidates))
                {
                    var w = Walk(query.Value!, wps[Math.Min(u, v)], wps[Math.Max(u, v)], cfg.StitchMaxIter, pathBuf, spBuf, cfg);
                    if (w == null) continue;
                    w.A = Math.Min(u, v); w.B = Math.Max(u, v);
                    if (best == null || w.Len < best.Len) best = w;
                }
                if (best == null) { failedGroups.Add(g.Key); unjoined++; continue; }
                Link(best);
                U(best.A, best.B);
                stitched++;
            }
        }
        var finalWays = adj.SelectMany(kv => kv.Value.Values).Distinct().OrderBy(w => w.A).ThenBy(w => w.B).ToList();
        var parts = wps.GroupBy(w => w.Comp).Sum(g => g.Select(w => F(w.Id - 1)).Distinct().Count());
        var crossing = finalWays.Count(w => Cluster(wps[w.A].P) != Cluster(wps[w.B].P));
        Console.WriteLine($"ways: {pruned} pruned, {stitched} added to join parts ({unjoined} parts left alone) in " +
            $"{sw.Elapsed.TotalSeconds:0.0} s; {finalWays.Count} ways; {wps.Select(w => w.Comp).Distinct().Count()} mesh regions " +
            $"with waypoints, {parts} network parts; {crossing} ways cross a cluster border");

        // the mesh is undirected (Detour links both ways): a sample of reverse walks confirms no way is one-way
        var reverseFail = 0;
        foreach (var w in finalWays.Where((_, i) => i % Math.Max(1, finalWays.Count / 500) == 0))
            if (Walk(query.Value!, wps[w.B], wps[w.A], cfg.StitchMaxIter, pathBuf, spBuf, cfg) == null) reverseFail++;

        // 8. anchors
        sw.Restart();
        var anchors = new (Way? way, int wp, string? why)[places.Count];
        Parallel.For(0, places.Count, () => (new long[1 << 16], new DtStraightPath[(1 << 16) + 4]), (k, _, buf) =>
        {
            var pl = places[k];
            var q = query.Value!;
            var (rx, _, rz) = Frame.FromWorld(pl.X, pl.Y, 0);
            var s = Snap(q, rx, pl.Z, rz, cfg.PlaceSnap, true, false);
            if (s == null)
            {
                anchors[k] = (null, 0, Snap(q, rx, pl.Z, rz, cfg.PlaceSnap, false, false) != null
                    ? "on ground the network does not reach (an island or a roof)"
                    : $"no walkable ground within {cfg.PlaceSnap} yards");
                return buf;
            }
            var start = new Wp { Ref = s.Value.r, P = s.Value.p, Comp = compOf[Gid(s.Value.r)] };
            Way? best = null;
            var bestWp = 0;
            foreach (var j in Near(start.P, cfg.AnchorRadius).Where(j => wps[j].Comp == start.Comp)
                         .Select(j => (j, d: Dist(start.P, wps[j].P))).Where(e => e.d <= cfg.AnchorRadius)
                         .OrderBy(e => e.d).ThenBy(e => e.j).Take(cfg.AnchorCandidates).Select(e => e.j))
            {
                var w = Walk(q, start, wps[j], cfg.MaxIter, buf.Item1, buf.Item2, cfg);
                if (w != null && (best == null || w.Len < best.Len)) { best = w; bestWp = wps[j].Id; }
            }
            anchors[k] = best != null ? (best, bestWp, null) : (null, 0, $"no waypoint reachable within {cfg.AnchorRadius} yards");
            return buf;
        }, _ => { });
        Console.WriteLine($"anchors: {anchors.Count(a => a.way != null)} of {places.Count} places in {sw.Elapsed.TotalSeconds:0.0} s; " +
            $"reverse check: {reverseFail} of {finalWays.Count / Math.Max(1, finalWays.Count / 500)} sampled ways fail backwards");

        var join = JoinField(query, wps, n);
        Write(outPath, client, file.Build, continent, wps, finalWays, places, anchors, join);
        Console.WriteLine($"-> {outPath} ({new FileInfo(outPath).Length / 1048576.0:0.0} MB), total {total.Elapsed.TotalSeconds:0} s");
        if (pngPath != null) Png(pngPath, pngTiles, wps, finalWays);
    }

    static float PolyArea(DtMeshTile t, DtPoly p)
    {
        double a = 0;
        var v = t.data.verts;
        for (var k = 0; k < p.vertCount; k++)
        {
            int i0 = p.verts[k] * 3, i1 = p.verts[(k + 1) % p.vertCount] * 3;
            a += v[i0] * v[i1 + 2] - v[i1] * v[i0 + 2];
        }
        return (float)Math.Abs(a / 2);
    }

    /// <summary>The nearest walkable point within radius across: with a height, the nearest in 3D (height counts
    /// double); without one, the nearest across and of those within 3 yards of it the highest (a dock over the
    /// sea bed). keptOnly: only regions the network keeps; roadOnly: only road polygons.</summary>
    static (long r, RcVec3f p)? Snap(DtNavMeshQuery q, double rx, double? wz, double rz, double radius, bool keptOnly, bool roadOnly)
    {
        var center = new RcVec3f((float)rx, (float)(wz ?? 0), (float)rz);
        var ext = new RcVec3f((float)radius, wz != null ? 20f : 4000f, (float)radius);
        var polys = new long[8192];
        q.QueryPolygons(center, ext, filter, polys, out var count, polys.Length);
        var cands = new List<(double d, double dy, long r, RcVec3f p)>();
        for (var i = 0; i < count; i++)
        {
            var g = Gid(polys[i]);
            if (keptOnly && !keptComp[compOf[g]]) continue;
            if (roadOnly && areaOf[g] != Navmesh.AreaRoad) continue;
            var c = mesh.GetPolyCenter(polys[i]);
            q.ClosestPointOnPoly(polys[i], new RcVec3f(center.X, wz != null ? center.Y : c.Y, center.Z), out var cp, out _);
            var d = Math.Sqrt((cp.X - rx) * (cp.X - rx) + (cp.Z - rz) * (cp.Z - rz));
            if (d > radius) continue;
            cands.Add((d, wz != null ? Math.Abs(cp.Y - wz.Value) : 0, polys[i], cp));
        }
        if (cands.Count == 0) return null;
        if (wz != null)
        {
            var b = cands.OrderBy(c => c.d + 2 * c.dy).ThenBy(c => c.r).First();
            return (b.r, b.p);
        }
        var min = cands.Min(c => c.d);
        var top = cands.Where(c => c.d <= min + 3).OrderByDescending(c => c.p.Y).ThenBy(c => c.r).First();
        return (top.r, top.p);
    }

    /// <summary>A walk between two waypoints over the mesh (sliced A*, at most maxIter nodes), or null; with the
    /// facts of data.md: 3D length, yards on road, deep water and indoors, climbed and dropped, the AreaTable id
    /// under most of it, the bends.</summary>
    static Way? Walk(DtNavMeshQuery q, Wp a, Wp b, int maxIter, long[] path, DtStraightPath[] sp, Config cfg)
    {
        if (a.Ref == b.Ref)
            return Facts(q, [new DtStraightPath(a.P, 0, a.Ref), new DtStraightPath(b.P, 0, b.Ref)], 2, cfg);
        q.InitSlicedFindPath(a.Ref, b.Ref, a.P, b.P, filter, 0);
        var st = q.UpdateSlicedFindPath(maxIter, out _);
        if (st.InProgress() || st.Failed()) return null;
        q.FinalizeSlicedFindPath(path, out var n, path.Length);
        if (n == 0 || path[n - 1] != b.Ref) return null;
        q.FindStraightPath(a.P, b.P, path, n, sp, out var sn, sp.Length, DtStraightPathOptions.DT_STRAIGHTPATH_ALL_CROSSINGS);
        if (sn < 2) return null;
        return Facts(q, sp, sn, cfg);
    }

    static Way Facts(DtNavMeshQuery q, DtStraightPath[] sp, int sn, Config cfg)
    {
        var w = new Way();
        var pts = new List<RcVec3f>(sn);
        for (var i = 0; i < sn; i++)
        {
            // a crossing's height is interpolated between polygon vertices, which can be yards off the ground on
            // a slope (seen: 14 yards at Northshire): take the detail surface of the polygon entered, else the last
            var p = sp[i].pos;
            foreach (var r in new[] { sp[i].refs, i > 0 ? sp[i - 1].refs : 0 })
            {
                if (r == 0 || q.ClosestPointOnPoly(r, p, out var cp, out _).Failed()) continue;
                if ((cp.X - p.X) * (cp.X - p.X) + (cp.Z - p.Z) * (cp.Z - p.Z) > 0.25) continue;
                p.Y = cp.Y;
                break;
            }
            pts.Add(p);
        }
        var byArea = new Dictionary<int, double>();
        for (var i = 0; i + 1 < pts.Count; i++)
        {
            var (p0, p1) = (pts[i], pts[i + 1]);
            var len = RcVec3f.Distance(p0, p1);
            w.Len += len;
            var dy = p1.Y - p0.Y;
            if (dy > 0) w.Up += dy; else w.Down -= dy;
            var area = sp[i].refs != 0 ? areaOf[Gid(sp[i].refs)] : 0;
            if (area == Navmesh.AreaRoad) w.Road += len;
            else if (area == Navmesh.AreaDeep) w.Swim += len;
            else if (area == Navmesh.AreaIndoor) w.Indoor += len;
            var at = file.AreaAt((p0.X + p1.X) / 2, (p0.Z + p1.Z) / 2);
            if (at != null) byArea[at.Value] = byArea.GetValueOrDefault(at.Value) + len;
        }
        if (byArea.Count > 0) w.Area = byArea.OrderByDescending(kv => kv.Value).ThenBy(kv => kv.Key).First().Key;
        var keep = new bool[pts.Count];
        keep[0] = keep[^1] = true;
        Dp(pts, 0, pts.Count - 1, cfg.Simplify, keep);
        for (var i = 1; i + 1 < pts.Count; i++) if (keep[i]) w.Points.Add(pts[i]);
        return w;
    }

    static void Dp(List<RcVec3f> p, int a, int b, double tol, bool[] keep)
    {
        if (b <= a + 1) return;
        double best = -1; var bi = -1;
        for (var i = a + 1; i < b; i++)
        {
            var d = SegDist(p[i], p[a], p[b]);
            if (d > best) { best = d; bi = i; }
        }
        if (best <= tol) return;
        keep[bi] = true;
        Dp(p, a, bi, tol, keep); Dp(p, bi, b, tol, keep);
    }

    static double SegDist(RcVec3f p, RcVec3f a, RcVec3f b)
    {
        var ab = b - a; var ap = p - a;
        var l2 = RcVec3f.Dot(ab, ab);
        var t = l2 > 0 ? Math.Clamp(RcVec3f.Dot(ap, ab) / l2, 0, 1) : 0;
        return RcVec3f.Distance(p, a + ab * (float)t);
    }

    /// <summary>Doors: the midpoints of the polygon edges where indoor meets walkable outdoor ground, merged
    /// within door_merge yards (a wide gate gives a few).</summary>
    static List<Wp> Doors(Config cfg, DtNavMeshQuery q)
    {
        var cand = new List<RcVec3f>();
        for (var i = 0; i < mesh.GetMaxTiles(); i++)
        {
            var t = mesh.GetTile(i);
            if (t?.data == null) continue;
            for (var ip = 0; ip < t.data.header.polyCount; ip++)
            {
                var g = tileBase[i] + ip;
                if (areaOf[g] != Navmesh.AreaIndoor || !keptComp[compOf[g]]) continue;
                var p = t.data.polys[ip];
                for (var j = p.firstLink; j != DtDetour.DT_NULL_LINK; j = t.links[j].next)
                {
                    var l = t.links[j];
                    var o = Gid(l.refs);
                    if (areaOf[o] is Navmesh.AreaIndoor or Navmesh.AreaBlocked) continue;
                    int va = p.verts[l.edge] * 3, vb = p.verts[(l.edge + 1) % p.vertCount] * 3;
                    var a = new RcVec3f(t.data.verts[va], t.data.verts[va + 1], t.data.verts[va + 2]);
                    var b = new RcVec3f(t.data.verts[vb], t.data.verts[vb + 1], t.data.verts[vb + 2]);
                    var f = l.side == 0xff ? 0.5f : (l.bmin + l.bmax) / 2f / 255f;
                    cand.Add(a + (b - a) * f);
                }
            }
        }
        var merged = Merge(cand, cfg.DoorMerge, 3);
        var outList = new List<Wp>();
        foreach (var c in merged)
        {
            var s = Snap(q, c.X, c.Y, c.Z, 3, true, false);
            if (s != null) outList.Add(new Wp { Kind = "door", Ref = s.Value.r, P = s.Value.p, Comp = compOf[Gid(s.Value.r)] });
        }
        return outList;
    }

    /// <summary>Points within radius across (and dy in height) joined by single linkage; the means, in a fixed order.</summary>
    static List<RcVec3f> Merge(List<RcVec3f> pts, double radius, double dy)
    {
        var order = pts.Select((p, i) => (p, i)).OrderBy(e => e.p.X).ThenBy(e => e.p.Z).ThenBy(e => e.p.Y).Select(e => e.p).ToList();
        var uf = Enumerable.Range(0, order.Count).ToArray();
        int F(int x) { while (uf[x] != x) { uf[x] = uf[uf[x]]; x = uf[x]; } return x; }
        var grid = new Dictionary<(int, int), List<int>>();
        for (var i = 0; i < order.Count; i++)
        {
            var k = ((int)Math.Floor(order[i].X / radius), (int)Math.Floor(order[i].Z / radius));
            for (var dz = -1; dz <= 1; dz++)
            for (var dx = -1; dx <= 1; dx++)
                if (grid.TryGetValue((k.Item1 + dx, k.Item2 + dz), out var l))
                    foreach (var j in l)
                    {
                        var p = order[i]; var o = order[j];
                        if ((p.X - o.X) * (p.X - o.X) + (p.Z - o.Z) * (p.Z - o.Z) <= radius * radius && Math.Abs(p.Y - o.Y) <= dy)
                        {
                            int ra = F(i), rb = F(j);
                            if (ra != rb) uf[Math.Max(ra, rb)] = Math.Min(ra, rb);
                        }
                    }
            if (!grid.TryGetValue(k, out var own)) grid[k] = own = [];
            own.Add(i);
        }
        return Enumerable.Range(0, order.Count).GroupBy(F).OrderBy(g => g.Key).Select(g =>
        {
            var s = new RcVec3f();
            foreach (var i in g) s += order[i];
            return s * (1f / g.Count());
        }).ToList();
    }

    /// <summary>Roads: the road polygons drawn onto a raster (road_cell yards), closed over small holes, small
    /// pieces dropped, thinned to a skeleton (Zhang-Suen); its junctions, ends and the Douglas-Peucker bends of
    /// each stretch (plus a point every road_max_gap yards) become road waypoints, merged within road_merge.</summary>
    static List<Wp> Roads(Config cfg, DtNavMeshQuery q, List<Wp> existing)
    {
        var cell = cfg.RoadCell;
        double minX = double.MaxValue, minZ = double.MaxValue, maxX = double.MinValue, maxZ = double.MinValue;
        var roadPolys = new List<(DtMeshTile t, DtPoly p)>();
        for (var i = 0; i < mesh.GetMaxTiles(); i++)
        {
            var t = mesh.GetTile(i);
            if (t?.data == null) continue;
            for (var ip = 0; ip < t.data.header.polyCount; ip++)
            {
                var g = tileBase[i] + ip;
                if (areaOf[g] != Navmesh.AreaRoad || !keptComp[compOf[g]]) continue;
                var p = t.data.polys[ip];
                roadPolys.Add((t, p));
                for (var k = 0; k < p.vertCount; k++)
                {
                    var v = p.verts[k] * 3;
                    minX = Math.Min(minX, t.data.verts[v]); maxX = Math.Max(maxX, t.data.verts[v]);
                    minZ = Math.Min(minZ, t.data.verts[v + 2]); maxZ = Math.Max(maxZ, t.data.verts[v + 2]);
                }
            }
        }
        if (roadPolys.Count == 0) return [];
        const int pad = 8;
        minX -= pad * cell; minZ -= pad * cell;
        int w = (int)Math.Ceiling((maxX - minX) / cell) + pad, h = (int)Math.Ceiling((maxZ - minZ) / cell) + pad;
        var img = new byte[(long)w * h];
        foreach (var (t, p) in roadPolys)
        {
            var xs = new double[p.vertCount]; var zs = new double[p.vertCount];
            for (var k = 0; k < p.vertCount; k++) { xs[k] = (t.data.verts[p.verts[k] * 3] - minX) / cell; zs[k] = (t.data.verts[p.verts[k] * 3 + 2] - minZ) / cell; }
            int x0 = (int)Math.Floor(xs.Min()), x1 = (int)Math.Ceiling(xs.Max()), z0 = (int)Math.Floor(zs.Min()), z1 = (int)Math.Ceiling(zs.Max());
            for (var z = z0; z <= z1; z++)
            for (var x = x0; x <= x1; x++)
            {
                double cx = x + 0.5, cz = z + 0.5;
                int pos = 0, neg = 0;
                for (var k = 0; k < p.vertCount; k++)
                {
                    var k1 = (k + 1) % p.vertCount;
                    var cr = (xs[k1] - xs[k]) * (cz - zs[k]) - (zs[k1] - zs[k]) * (cx - xs[k]);
                    if (cr > 1e-9) pos++; else if (cr < -1e-9) neg++;
                }
                if (pos == 0 || neg == 0) img[(long)z * w + x] = 1;
            }
        }
        // closing: dilate then erode (square, road_close pixels)
        for (var r = 0; r < cfg.RoadClose; r++) img = Morph(img, w, h, true);
        for (var r = 0; r < cfg.RoadClose; r++) img = Morph(img, w, h, false);
        // small pieces
        var minPix = (int)(cfg.RoadMinBlob / (cell * cell));
        var seen = new bool[img.Length];
        var stack = new Stack<long>();
        var blob = new List<long>();
        for (long i = 0; i < img.Length; i++)
        {
            if (img[i] == 0 || seen[i]) continue;
            blob.Clear(); stack.Push(i); seen[i] = true;
            while (stack.Count > 0)
            {
                var c = stack.Pop(); blob.Add(c);
                long cx = c % w, cz = c / w;
                for (var dz = -1; dz <= 1; dz++)
                for (var dx = -1; dx <= 1; dx++)
                {
                    long nx = cx + dx, nz = cz + dz;
                    if (nx < 0 || nz < 0 || nx >= w || nz >= h) continue;
                    var o = nz * w + nx;
                    if (img[o] != 0 && !seen[o]) { seen[o] = true; stack.Push(o); }
                }
            }
            if (blob.Count < minPix) foreach (var c in blob) img[c] = 0;
        }
        Thin(img, w, h);

        // the skeleton's graph
        int Deg(long i)
        {
            long x = i % w, z = i / w; var d = 0;
            for (var dz = -1; dz <= 1; dz++) for (var dx = -1; dx <= 1; dx++)
                if ((dx != 0 || dz != 0) && img[(z + dz) * w + x + dx] != 0) d++;
            return d;
        }
        IEnumerable<long> Nb(long i)
        {
            long x = i % w, z = i / w;
            for (var dz = -1; dz <= 1; dz++) for (var dx = -1; dx <= 1; dx++)
                if ((dx != 0 || dz != 0) && img[(z + dz) * w + x + dx] != 0) yield return (z + dz) * w + x + dx;
        }
        var skel = new List<long>();
        for (long i = 0; i < img.Length; i++) if (img[i] != 0) skel.Add(i);
        var isNode = new HashSet<long>(skel.Where(i => Deg(i) != 2));
        var visited = new HashSet<long>();
        var chains = new List<List<long>>();
        foreach (var s in skel.Where(isNode.Contains))
            foreach (var m in Nb(s))
            {
                if (isNode.Contains(m) || visited.Contains(m)) continue;
                var chain = new List<long> { s, m };
                visited.Add(m);
                var (prev, cur) = (s, m);
                while (!isNode.Contains(cur))
                {
                    var next = Nb(cur).Where(o => o != prev && !visited.Contains(o) && o != s)
                        .OrderBy(o => isNode.Contains(o) ? 0 : 1).ThenBy(o => o).FirstOrDefault(-1);
                    if (next < 0) break;
                    chain.Add(next);
                    if (!isNode.Contains(next)) visited.Add(next);
                    (prev, cur) = (cur, next);
                }
                chains.Add(chain);
            }
        foreach (var s in skel.Where(i => !isNode.Contains(i) && !visited.Contains(i))) // closed rings
        {
            if (visited.Contains(s)) continue;
            var chain = new List<long> { s };
            visited.Add(s);
            var cur = s;
            while (true)
            {
                var next = Nb(cur).Where(o => !visited.Contains(o)).OrderBy(o => o).FirstOrDefault(-1);
                if (next < 0) break;
                chain.Add(next); visited.Add(next); cur = next;
            }
            chain.Add(s);
            if (chain.Count > 3) chains.Add(chain);
        }
        double Yards(List<long> c)
        {
            double l = 0;
            for (var i = 1; i < c.Count; i++) l += (c[i] % w != c[i - 1] % w && c[i] / w != c[i - 1] / w ? Math.Sqrt(2) : 1) * cell;
            return l;
        }
        var pts = new List<(RcVec3f p, int prio)>();
        RcVec3f At(long i) => new((float)(minX + (i % w + 0.5) * cell), 0, (float)(minZ + (i / w + 0.5) * cell));
        foreach (var c in chains)
        {
            var len = Yards(c);
            var endA = Deg(c[0]) == 1; var endB = Deg(c[^1]) == 1;
            if ((endA || endB) && len < cfg.RoadSpur) continue; // a spur or a crumb
            var p = c.Select(At).ToList();
            var keep = new bool[p.Count];
            keep[0] = keep[^1] = true;
            Dp(p, 0, p.Count - 1, cfg.RoadSimplify, keep);
            var kept = Enumerable.Range(0, p.Count).Where(i => keep[i]).ToList();
            pts.Add((p[0], Deg(c[0]) >= 3 ? 0 : 1));
            pts.Add((p[^1], Deg(c[^1]) >= 3 ? 0 : 1));
            for (var k = 0; k + 1 < kept.Count; k++)
            {
                if (k > 0) pts.Add((p[kept[k]], 2));
                var seg = RcVec3f.Distance(p[kept[k]], p[kept[k + 1]]);
                var parts = (int)Math.Ceiling(seg / cfg.RoadMaxGap);
                for (var s = 1; s < parts; s++) pts.Add((p[kept[k]] + (p[kept[k + 1]] - p[kept[k]]) * ((float)s / parts), 3));
            }
        }
        // merge: junctions first, then ends, bends, fillers; nothing near a node or a door
        var chosen = new List<RcVec3f>();
        var cgrid = new Dictionary<(int, int), List<RcVec3f>>();
        bool Free(RcVec3f p, double r)
        {
            int bx = (int)Math.Floor(p.X / r), bz = (int)Math.Floor(p.Z / r);
            for (var dz = -1; dz <= 1; dz++) for (var dx = -1; dx <= 1; dx++)
                if (cgrid.TryGetValue((bx + dx, bz + dz), out var l) && l.Any(o => (o.X - p.X) * (o.X - p.X) + (o.Z - p.Z) * (o.Z - p.Z) < r * r))
                    return false;
            return true;
        }
        void Take(RcVec3f p, double r)
        {
            var k = ((int)Math.Floor(p.X / r), (int)Math.Floor(p.Z / r));
            if (!cgrid.TryGetValue(k, out var l)) cgrid[k] = l = [];
            l.Add(p);
        }
        foreach (var e in existing) Take(e.P, cfg.RoadMerge);
        var outList = new List<Wp>();
        foreach (var (p, _) in pts.OrderBy(e => e.prio).ThenBy(e => e.p.X).ThenBy(e => e.p.Z))
        {
            if (!Free(p, cfg.RoadMerge)) continue;
            var s = Snap(q, p.X, null, p.Z, 6, true, true);
            if (s == null) continue;
            Take(p, cfg.RoadMerge);
            outList.Add(new Wp { Kind = "road", Ref = s.Value.r, P = s.Value.p, Comp = compOf[Gid(s.Value.r)] });
        }
        return outList;
    }

    static byte[] Morph(byte[] img, int w, int h, bool dilate)
    {
        var o = new byte[img.Length];
        Parallel.For(1, h - 1, z =>
        {
            for (var x = 1; x < w - 1; x++)
            {
                var any = false; var all = true;
                for (var dz = -1; dz <= 1; dz++)
                for (var dx = -1; dx <= 1; dx++)
                {
                    var v = img[(long)(z + dz) * w + x + dx] != 0;
                    any |= v; all &= v;
                }
                o[(long)z * w + x] = (byte)((dilate ? any : all) ? 1 : 0);
            }
        });
        return o;
    }

    /// <summary>Zhang-Suen thinning in place (the raster keeps a border of empty pixels).</summary>
    static void Thin(byte[] img, int w, int h)
    {
        var fg = new List<long>();
        for (long i = 0; i < img.Length; i++) if (img[i] != 0) fg.Add(i);
        var changed = true;
        while (changed)
        {
            changed = false;
            for (var sub = 0; sub < 2; sub++)
            {
                var del = new List<long>();
                foreach (var i in fg)
                {
                    if (img[i] == 0) continue;
                    long x = i % w, z = i / w;
                    if (x < 1 || z < 1 || x >= w - 1 || z >= h - 1) continue;
                    int P(int dx, int dz) => img[(z + dz) * w + x + dx] != 0 ? 1 : 0;
                    int p2 = P(0, -1), p3 = P(1, -1), p4 = P(1, 0), p5 = P(1, 1), p6 = P(0, 1), p7 = P(-1, 1), p8 = P(-1, 0), p9 = P(-1, -1);
                    var b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
                    if (b < 2 || b > 6) continue;
                    var a = (p2 == 0 && p3 == 1 ? 1 : 0) + (p3 == 0 && p4 == 1 ? 1 : 0) + (p4 == 0 && p5 == 1 ? 1 : 0) + (p5 == 0 && p6 == 1 ? 1 : 0)
                        + (p6 == 0 && p7 == 1 ? 1 : 0) + (p7 == 0 && p8 == 1 ? 1 : 0) + (p8 == 0 && p9 == 1 ? 1 : 0) + (p9 == 0 && p2 == 1 ? 1 : 0);
                    if (a != 1) continue;
                    if (sub == 0 ? (p2 * p4 * p6 != 0 || p4 * p6 * p8 != 0) : (p2 * p4 * p8 != 0 || p2 * p6 * p8 != 0)) continue;
                    del.Add(i);
                }
                foreach (var i in del) img[i] = 0;
                if (del.Count > 0) changed = true;
            }
            fg = fg.Where(i => img[i] != 0).ToList();
        }
    }

    /// <summary>Open ground: per lattice cell (spacing yards, aligned to the world) and walkable layer of a kept
    /// region with min_layer_area of polygons, the point nearest the cell's centre; water-only layers on every
    /// third cell; none within ground_clear yards of another waypoint of its layer.</summary>
    static List<Wp> Ground(Config cfg, ThreadLocal<DtNavMeshQuery> query, List<Wp> existing)
    {
        var s = cfg.Spacing;
        var cells = new List<(int ix, int iz)>();
        var perTile = (int)Math.Round(Frame.Tile / s);
        foreach (var (x, y) in file.Index.Keys.OrderBy(k => k.y).ThenBy(k => k.x))
        {
            int ix0 = (int)Math.Floor(x * Frame.Tile / s), ix1 = (int)Math.Ceiling((x + 1) * Frame.Tile / s);
            int iz0 = (int)Math.Floor(y * Frame.Tile / s), iz1 = (int)Math.Ceiling((y + 1) * Frame.Tile / s);
            for (var iz = iz0; iz < iz1; iz++)
            for (var ix = ix0; ix < ix1; ix++)
            {
                var (cx, cz) = ((ix + 0.5) * s, (iz + 0.5) * s);
                if ((int)Math.Floor(cx / Frame.Tile) == x && (int)Math.Floor(cz / Frame.Tile) == y) cells.Add((ix, iz));
            }
        }
        var found = new List<Wp>[cells.Count];
        var waterStep = Math.Max(1, (int)Math.Round(cfg.WaterSpacing / s));
        Parallel.For(0, cells.Count, k =>
        {
            var q = query.Value!;
            var (ix, iz) = cells[k];
            var (cx, cz) = ((ix + 0.5) * s, (iz + 0.5) * s);
            var polys = new long[16384];
            q.QueryPolygons(new RcVec3f((float)cx, 0, (float)cz), new RcVec3f((float)(s / 2), 4000, (float)(s / 2)), filter, polys, out var count, polys.Length);
            var cands = new List<(int comp, float y, double d, long r, RcVec3f p, int g)>();
            for (var i = 0; i < count; i++)
            {
                var g = Gid(polys[i]);
                if (!keptComp[compOf[g]]) continue;
                var c = mesh.GetPolyCenter(polys[i]);
                q.ClosestPointOnPoly(polys[i], new RcVec3f((float)cx, c.Y, (float)cz), out var cp, out _);
                if (Math.Abs(cp.X - cx) > s / 2 || Math.Abs(cp.Z - cz) > s / 2) continue;
                cands.Add((compOf[g], cp.Y, Math.Sqrt((cp.X - cx) * (cp.X - cx) + (cp.Z - cz) * (cp.Z - cz)), polys[i], cp, g));
            }
            var list = new List<Wp>();
            foreach (var byComp in cands.GroupBy(c => c.comp).OrderBy(g => g.Key))
            {
                var sorted = byComp.OrderBy(c => c.y).ThenBy(c => c.r).ToList();
                var start = 0;
                for (var i = 1; i <= sorted.Count; i++)
                {
                    if (i < sorted.Count && sorted[i].y - sorted[i - 1].y <= cfg.LayerGap) continue;
                    var layer = sorted.GetRange(start, i - start);
                    start = i;
                    if (layer.Sum(c => polyArea[c.g]) < cfg.MinLayerArea) continue;
                    var water = layer.All(c => areaOf[c.g] == Navmesh.AreaDeep);
                    if (water && (ix % waterStep != 0 || iz % waterStep != 0)) continue;
                    var best = layer.OrderBy(c => c.d).ThenBy(c => c.r).First();
                    list.Add(new Wp { Kind = "ground", Ref = best.r, P = best.p, Comp = best.comp });
                }
            }
            found[k] = list;
        });
        var clear = cfg.GroundClear;
        var grid = new Dictionary<(int, int), List<Wp>>();
        void Take(Wp w)
        {
            var key = ((int)Math.Floor(w.P.X / clear), (int)Math.Floor(w.P.Z / clear));
            if (!grid.TryGetValue(key, out var l)) grid[key] = l = [];
            l.Add(w);
        }
        foreach (var e in existing) Take(e);
        var outList = new List<Wp>();
        foreach (var w in found.SelectMany(l => l))
        {
            int bx = (int)Math.Floor(w.P.X / clear), bz = (int)Math.Floor(w.P.Z / clear);
            var near = false;
            for (var dz = -1; dz <= 1 && !near; dz++) for (var dx = -1; dx <= 1 && !near; dx++)
                if (grid.TryGetValue((bx + dx, bz + dz), out var l))
                    near = l.Any(o => o.Comp == w.Comp && Math.Abs(o.P.Y - w.P.Y) <= cfg.LayerGap
                        && (o.P.X - w.P.X) * (o.P.X - w.P.X) + (o.P.Z - w.P.Z) * (o.P.Z - w.P.Z) < clear * clear);
            if (near) continue;
            outList.Add(w);
        }
        return outList;
    }

    static string N(double v) => Math.Round(v, 1).ToString("0.0", CultureInfo.InvariantCulture);

    static void WritePoint(Utf8JsonWriter w, RcVec3f p)
    {
        var (wx, wy, wz) = Frame.ToWorld(p.X, p.Y, p.Z);
        w.WriteStartArray();
        w.WriteRawValue(N(wx)); w.WriteRawValue(N(wy)); w.WriteRawValue(N(wz));
        w.WriteEndArray();
    }

    static void Write(string path, string client, string build, int continent, List<Wp> wps, List<Way> ways,
        List<PlaceIn> places, (Way? way, int wp, string? why)[] anchors, List<int> join)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var tmp = path + ".tmp";
        using (var f = File.Create(tmp))
        using (var w = new Utf8JsonWriter(f))
        {
            w.WriteStartObject();
            w.WriteNumber("version", 1);
            w.WriteString("client", client);
            w.WriteString("build", build);
            w.WriteNumber("continent", continent);
            w.WriteStartArray("waypoints");
            foreach (var p in wps)
            {
                var (wx, wy, wz) = Frame.ToWorld(p.P.X, p.P.Y, p.P.Z);
                w.WriteStartObject();
                w.WriteNumber("id", p.Id);
                w.WritePropertyName("x"); w.WriteRawValue(N(wx));
                w.WritePropertyName("y"); w.WriteRawValue(N(wy));
                w.WritePropertyName("z"); w.WriteRawValue(N(wz));
                w.WriteString("kind", p.Kind);
                if (p.Key != null) w.WriteString("key", p.Key); else w.WriteNull("key");
                var area = file.AreaAt(p.P.X, p.P.Z);
                if (area != null) w.WriteNumber("area", area.Value); else w.WriteNull("area");
                w.WriteEndObject();
            }
            w.WriteEndArray();
            w.WriteStartArray("ways");
            foreach (var x in ways)
            {
                w.WriteStartObject();
                w.WriteNumber("a", wps[x.A].Id); w.WriteNumber("b", wps[x.B].Id);
                w.WritePropertyName("len"); w.WriteRawValue(N(x.Len));
                w.WritePropertyName("road"); w.WriteRawValue(N(x.Road));
                w.WritePropertyName("swim"); w.WriteRawValue(N(x.Swim));
                w.WritePropertyName("up"); w.WriteRawValue(N(x.Up));
                w.WritePropertyName("down"); w.WriteRawValue(N(x.Down));
                w.WritePropertyName("indoor"); w.WriteRawValue(N(x.Indoor));
                w.WriteBoolean("oneway", false);
                if (x.Area != null) w.WriteNumber("area", x.Area.Value); else w.WriteNull("area");
                w.WriteStartArray("points");
                foreach (var p in x.Points) WritePoint(w, p);
                w.WriteEndArray();
                w.WriteEndObject();
            }
            w.WriteEndArray();
            w.WriteStartArray("anchors");
            for (var i = 0; i < places.Count; i++)
            {
                if (anchors[i].way == null) continue;
                w.WriteStartObject();
                w.WriteString("ref", places[i].Ref);
                w.WriteNumber("i", places[i].I);
                w.WriteNumber("wp", anchors[i].wp);
                w.WritePropertyName("len"); w.WriteRawValue(N(anchors[i].way!.Len));
                w.WriteStartArray("points");
                foreach (var p in anchors[i].way!.Points) WritePoint(w, p);
                w.WriteEndArray();
                w.WriteEndObject();
            }
            w.WriteEndArray();
            w.WriteStartArray("join");
            foreach (var v in join) w.WriteNumberValue(v);
            w.WriteEndArray();
            w.WriteStartArray("unanchored");
            for (var i = 0; i < places.Count; i++)
            {
                if (anchors[i].way != null) continue;
                w.WriteStartObject();
                w.WriteString("ref", places[i].Ref);
                w.WriteNumber("i", places[i].I);
                w.WriteString("why", anchors[i].why);
                w.WriteEndObject();
            }
            w.WriteEndArray();
            w.WriteEndObject();
        }
        File.Move(tmp, path, true);
    }

    /// <summary>The join field (route.md "The join"): for each 33-yard cell of each cluster that has walkable
    /// ground, the waypoint of that cluster nearest on foot, found by a search over the mesh's polygons from all
    /// the cluster's waypoints at once. As flat triples col, row, waypoint id (cells of 1/16 ADT tile in the recast
    /// frame). A place on the far side of a ridge is near in a straight line and far on foot; the runtime has no
    /// mesh and joins the character by this.</summary>
    static List<int> JoinField(ThreadLocal<DtNavMeshQuery> query, List<Wp> wps, int n)
    {
        const int cellsPerCluster = 32;
        const double margin = 200, limit = 900;
        var cell = Frame.Tile / 16;
        var centers = new RcVec3f[n];
        Parallel.For(0, n, g => centers[g] = mesh.GetPolyCenter(refOf[g]));
        var groups = wps.Select((w, i) => (w, i))
            .GroupBy(e => ((int)Math.Floor(e.w.P.X / Frame.Tile / 2), (int)Math.Floor(e.w.P.Z / Frame.Tile / 2)))
            .OrderBy(g => g.Key).ToList();
        var parts = new List<int>[groups.Count];
        var cells = 0;
        var differ = 0;
        Parallel.For(0, groups.Count, gi =>
        {
            var q = query.Value!;
            var (kx, kz) = groups[gi].Key;
            double x0 = kx * 2 * Frame.Tile, z0 = kz * 2 * Frame.Tile, span = 2 * Frame.Tile;
            var best = new Dictionary<int, (float d, int wp)>();
            var open = new PriorityQueue<int, float>();
            foreach (var (w, i) in groups[gi])
            {
                var g = Gid(w.Ref);
                if (best.TryGetValue(g, out var b) && b.d == 0) continue;
                best[g] = (0, i);
                open.Enqueue(g, 0);
            }
            while (open.TryDequeue(out var g, out var d))
            {
                var at = best[g];
                if (d > at.d || at.d > limit) continue;
                var r = refOf[g];
                var t = mesh.GetTile(DtDetour.DecodePolyIdTile(r));
                for (var j = t.data.polys[DtDetour.DecodePolyIdPoly(r)].firstLink; j != DtDetour.DT_NULL_LINK; j = t.links[j].next)
                {
                    var o = Gid(t.links[j].refs);
                    if (areaOf[o] == Navmesh.AreaBlocked) continue;
                    var c = centers[o];
                    if (c.X < x0 - margin || c.X > x0 + span + margin || c.Z < z0 - margin || c.Z > z0 + span + margin) continue;
                    var nd = at.d + RcVec3f.Distance(centers[g], c) * Math.Max(0.1f, costs[areaOf[o]]);
                    if (best.TryGetValue(o, out var old) && old.d <= nd) continue;
                    best[o] = (nd, at.wp);
                    open.Enqueue(o, nd);
                }
            }
            var part = new List<int>();
            var polys = new long[4096];
            int found = 0, other = 0;
            for (var cz = 0; cz < cellsPerCluster; cz++)
            for (var cx = 0; cx < cellsPerCluster; cx++)
            {
                double px = x0 + (cx + 0.5) * cell, pz = z0 + (cz + 0.5) * cell;
                q.QueryPolygons(new RcVec3f((float)px, 0, (float)pz), new RcVec3f((float)(cell / 2), 4000, (float)(cell / 2)), filter, polys, out var count, polys.Length);
                (float d, int wp)? under = null, near = null;
                for (var i = 0; i < count; i++)
                {
                    if (!best.TryGetValue(Gid(polys[i]), out var b)) continue;
                    q.ClosestPointOnPoly(polys[i], new RcVec3f((float)px, centers[Gid(polys[i])].Y, (float)pz), out _, out var over);
                    if (over && (under == null || b.d < under.Value.d)) under = b;
                    if (near == null || b.d < near.Value.d) near = b;
                }
                var pick = under ?? near;
                if (pick == null) continue;
                part.Add((kx * 2 * 16) + cx);
                part.Add((kz * 2 * 16) + cz);
                part.Add(wps[pick.Value.wp].Id);
                found++;
                // what the straight line would have taken instead, for the report
                var straight = groups[gi].OrderBy(e => (e.w.P.X - px) * (e.w.P.X - px) + (e.w.P.Z - pz) * (e.w.P.Z - pz)).First().i;
                if (straight != pick.Value.wp) other++;
            }
            parts[gi] = part;
            Interlocked.Add(ref cells, found);
            Interlocked.Add(ref differ, other);
        });
        Console.WriteLine($"join field: {cells} cells, {differ} ({100.0 * differ / Math.Max(1, cells):0.0} %) join another waypoint than the straight line");
        return parts.SelectMany(p => p).ToList();
    }

    /// <summary>The mesh image of an ADT tile range with the ways (white) and the waypoints (node red, door
    /// magenta, road yellow, ground cyan) over it.</summary>
    static void Png(string pngPath, string? tilesArg, List<Wp> wps, List<Way> ways)
    {
        var t = (tilesArg ?? throw new ArgumentException("--png-tiles x0,y0,x1,y1 is required with --png")).Split(',').Select(int.Parse).ToArray();
        var (px, w, h, minX, minZ, ppy, _, _, _) = NavmeshView.Render(file, t[0] * Frame.Tile, (t[2] + 1) * Frame.Tile,
            t[1] * Frame.Tile, (t[3] + 1) * Frame.Tile, float.MinValue, float.MaxValue, null);
        void Dot(double x, double z, byte r, byte g, byte b, int rad)
        {
            int cx = (int)((x - minX) * ppy), cz = (int)((z - minZ) * ppy);
            for (var dz = -rad; dz <= rad; dz++) for (var dx = -rad; dx <= rad; dx++)
            {
                int xx = cx + dx, zz = cz + dz;
                if (xx < 0 || zz < 0 || xx >= w || zz >= h) continue;
                var i = (zz * w + xx) * 4;
                px[i] = b; px[i + 1] = g; px[i + 2] = r;
            }
        }
        void Line(RcVec3f a, RcVec3f b)
        {
            var steps = (int)Math.Ceiling(RcVec3f.Distance(a, b) * ppy) + 1;
            for (var s = 0; s <= steps; s++)
            {
                var p = a + (b - a) * ((float)s / steps);
                Dot(p.X, p.Z, 240, 240, 240, 0);
            }
        }
        foreach (var way in ways)
        {
            var pts = new List<RcVec3f> { wps[way.A].P };
            pts.AddRange(way.Points);
            pts.Add(wps[way.B].P);
            for (var i = 0; i + 1 < pts.Count; i++) Line(pts[i], pts[i + 1]);
        }
        foreach (var p in wps)
        {
            var (r, g, b) = p.Kind switch { "node" => (255, 40, 40), "door" => (255, 0, 255), "road" => (255, 220, 0), _ => (0, 230, 255) };
            Dot(p.P.X, p.P.Z, (byte)r, (byte)g, (byte)b, p.Kind == "node" ? 3 : 2);
        }
        ClientDump.Png.Write(pngPath, px, w, h);
        Console.WriteLine($"{pngPath}: {w} x {h} px");
    }
}
