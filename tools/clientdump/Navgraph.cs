// The walk network of one map (ADR 0025, route.md "Walk network"): from the cells `terrain` wrote, the walkable
// ground, a lattice of nodes plus the pipeline's nodes, and per node the cheapest paths over the cells to its
// nearest nodes. Road cells cost less, so paths keep to the roads; swimming costs more. Output: JSON with the
// snapped nodes and the edges (length, swum length, cost, the path simplified), and optionally a PNG to look at.
// Deterministic: the same inputs give the same JSON (each node's search is independent; results are sorted).
using System.Text.Json;
using System.IO.Compression;

namespace ClientDump;

static class Navgraph
{
    const int TileCells = 128, TileArea = TileCells * TileCells;
    const double Origin = 32 * 1600.0 / 3; // world yards of the grid's north-west corner
    const double CellYards = 1600.0 / 3 / TileCells;
    const byte Blocked = 0, Walk = 1, Swim = 2;

    sealed class Config
    {
        public double MaxSlope { get; set; } = 50;
        public double SwimDepth { get; set; } = 1.6;
        public double SwimFactor { get; set; } = 3.0;
        public double RoadFactor { get; set; } = 0.55;
        public double RoadMin { get; set; } = 0.35;
        public bool DeepBlocked { get; set; } = true;
        public int[] BlockedLiquids { get; set; } = [];
        public int[] OceanLiquids { get; set; } = []; // the sea: wading only, no swimming (the client's
                                                      // "deep" flag is not set on the open sea, 25.10.2026)
        public double Lattice { get; set; } = 400;
        public double LatticeSnap { get; set; } = 150;
        public double RoadSnap { get; set; } = 120;
        public int Neighbours { get; set; } = 8;
        public double Radius { get; set; } = 900;
        public double Prune { get; set; } = 1.02;
        public double Simplify { get; set; } = 6;
        public int MinIsland { get; set; } = 200;
        public double HeightTolerance { get; set; } = 10; // a node with a height snaps only to ground this near
    }

    sealed record NodeIn(string Id, double Wx, double Wy, double Snap, double? Wz = null);

    sealed class Grid
    {
        public int[] Slot = new int[64 * 64];
        public int[] TileOf = []; // slot -> tile index y * 64 + x
        public byte[] Kind = [];
        public bool[] Road = [];
        public short[] Height = [];
        public int[] Comp = [];
        public int[] CompSize = [];
        public int MinR = int.MaxValue, MaxR, MinC = int.MaxValue, MaxC;

        public int Idx(int r, int c)
        {
            if (r < 0 || c < 0 || r >= 64 * TileCells || c >= 64 * TileCells) return -1;
            var s = Slot[(r / TileCells) * 64 + c / TileCells];
            return s < 0 ? -1 : s * TileArea + (r % TileCells) * TileCells + c % TileCells;
        }
    }

    public static void Run(string terrainPath, string nodesPath, string configPath, string outPath, string? pngPath)
    {
        var json = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };
        var cfg = JsonSerializer.Deserialize<Config>(File.ReadAllText(configPath), json) ?? new Config();
        var inputs = JsonSerializer.Deserialize<List<NodeIn>>(File.ReadAllText(nodesPath), json) ?? [];
        var g = Load(terrainPath, cfg);
        Components(g, cfg);
        Console.WriteLine($"navgraph: {g.Kind.Length / TileArea} tiles, {g.CompSize.Count(n => n >= cfg.MinIsland)} land masses");

        // the nodes: the pipeline's first (their order is theirs), then the lattice
        var nodes = new List<(string id, int cell, bool lattice)>();
        var taken = new Dictionary<int, int>();
        var dropped = new List<string>();
        foreach (var n in inputs)
        {
            // a node above or below the ground (a city in a building: Ironforge) is not on the cells
            var cell = Snap(g, cfg, n.Wx, n.Wy, n.Snap, 0, n.Wz);
            if (cell < 0) { dropped.Add(n.Id); continue; }
            taken.TryAdd(cell, nodes.Count);
            nodes.Add((n.Id, cell, false));
        }
        var step = cfg.Lattice;
        var (north, south) = (Origin - g.MinR * CellYards, Origin - (g.MaxR + 1) * CellYards);
        var (west, east) = (Origin - g.MinC * CellYards, Origin - (g.MaxC + 1) * CellYards);
        for (var wx = Math.Floor(north / step) * step; wx > south; wx -= step)
        for (var wy = Math.Floor(west / step) * step; wy > east; wy -= step)
        {
            var cell = Snap(g, cfg, wx, wy, cfg.LatticeSnap, cfg.RoadSnap);
            if (cell < 0 || taken.ContainsKey(cell)) continue;
            taken[cell] = nodes.Count;
            nodes.Add(($"n:{Math.Round(wx)}:{Math.Round(wy)}", cell, true));
        }
        Console.WriteLine($"nodes: {nodes.Count} ({nodes.Count(n => !n.lattice)} given, {dropped.Count} given ones off the ground)");

        // per node, the cheapest paths to its nearest nodes (in parallel; each search on its own window)
        var found = new List<Edge>[nodes.Count];
        Parallel.For(0, nodes.Count, () => new Search(g, cfg), (i, _, search) =>
        {
            found[i] = search.From(i, nodes[i].cell, taken);
            return search;
        }, _ => { });
        var edges = new Dictionary<(int, int), Edge>();
        foreach (var list in found)
        foreach (var e in list)
        {
            var key = (Math.Min(e.A, e.B), Math.Max(e.A, e.B));
            if (!edges.TryGetValue(key, out var old) || e.Cost < old.Cost) edges[key] = e;
        }
        var kept = Prune(edges, cfg.Prune);
        var stitched = Stitch(g, cfg, nodes, kept);
        Console.WriteLine($"edges: {edges.Count} found, {kept.Count - stitched} kept after pruning, {stitched} stitched");

        var outNodes = nodes.Select(n =>
        {
            var (wx, wy) = Centre(g, n.cell);
            return new Dictionary<string, object> { ["id"] = n.id, ["wx"] = Math.Round(wx, 1), ["wy"] = Math.Round(wy, 1), ["lattice"] = n.lattice };
        }).ToList();
        var outEdges = kept.Select(e =>
        {
            var pts = Simplify(e.Cells.Select(c => Centre(g, c)).ToList(), cfg.Simplify);
            var (a, b) = e.A < e.B ? (e.A, e.B) : (e.B, e.A);
            if (e.A > e.B) pts.Reverse();
            return new Dictionary<string, object>
            {
                ["a"] = a, ["b"] = b, ["len"] = Math.Round(e.Len, 1), ["swim"] = Math.Round(e.SwimLen, 1),
                ["cost"] = Math.Round(e.Cost, 1),
                ["pts"] = pts.Skip(1).SkipLast(1).Select(p => new[] { Math.Round(p.wx, 1), Math.Round(p.wy, 1) }).ToList(),
            };
        }).ToList();
        var doc = new Dictionary<string, object> { ["nodes"] = outNodes, ["edges"] = outEdges, ["dropped"] = dropped };
        var tmp = outPath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(doc));
        File.Move(tmp, outPath, true);
        Console.WriteLine($"-> {outPath}");
        if (pngPath != null) Picture(g, nodes, kept, pngPath);
    }

    sealed class Edge
    {
        public int A, B;
        public double Cost, Len, SwimLen;
        public List<int> Cells = [];
    }

    static Grid Load(string path, Config cfg)
    {
        var g = new Grid();
        Array.Fill(g.Slot, -1);
        using var gz = new GZipStream(File.OpenRead(path), CompressionMode.Decompress);
        using var r = new BinaryReader(gz);
        if (new string(r.ReadChars(4)) != "BTER" || r.ReadUInt32() != 1) throw new InvalidDataException("not a terrain v1 file");
        var tiles = r.ReadInt32();
        g.Kind = new byte[tiles * TileArea];
        g.TileOf = new int[tiles];
        g.Road = new bool[tiles * TileArea];
        g.Height = new short[tiles * TileArea];
        var blockedLiquid = cfg.BlockedLiquids.ToHashSet();
        var ocean = cfg.OceanLiquids.ToHashSet();
        var maxSlope = cfg.MaxSlope;
        for (var t = 0; t < tiles; t++)
        {
            int x = r.ReadInt32(), y = r.ReadInt32();
            g.Slot[y * 64 + x] = t;
            g.TileOf[t] = y * 64 + x;
            g.MinR = Math.Min(g.MinR, y * TileCells); g.MaxR = Math.Max(g.MaxR, y * TileCells + TileCells - 1);
            g.MinC = Math.Min(g.MinC, x * TileCells); g.MaxC = Math.Max(g.MaxC, x * TileCells + TileCells - 1);
            for (var i = 0; i < TileArea; i++)
            {
                var height = r.ReadInt16();
                var slope = r.ReadByte();
                var flags = r.ReadByte();
                var liquid = r.ReadUInt16();
                var surface = r.ReadInt16();
                var road = r.ReadByte();
                byte kind;
                if ((flags & 9) != 0) kind = Blocked; // no terrain, or a hole (a building or a cave sits there)
                else if ((flags & 2) != 0 && blockedLiquid.Contains(liquid)) kind = Blocked;
                else if ((flags & 2) != 0 && (flags & 4) != 0 && cfg.DeepBlocked) kind = Blocked; // open sea
                else if ((flags & 2) != 0 && surface - height > cfg.SwimDepth)
                    kind = ocean.Contains(liquid) ? Blocked : Swim;
                else kind = slope > maxSlope ? Blocked : Walk;
                g.Kind[t * TileArea + i] = kind;
                g.Height[t * TileArea + i] = height;
                g.Road[t * TileArea + i] = kind == Walk && road >= cfg.RoadMin * 255;
            }
        }
        return g;
    }

    static readonly (int dr, int dc, double d)[] Steps =
    [
        (-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1),
        (-1, -1, Math.Sqrt(2)), (-1, 1, Math.Sqrt(2)), (1, -1, Math.Sqrt(2)), (1, 1, Math.Sqrt(2)),
    ];

    static (int r, int c) RowCol(Grid g, int idx)
    {
        var t = g.TileOf[idx / TileArea];
        var local = idx % TileArea;
        return ((t / 64) * TileCells + local / TileCells, (t % 64) * TileCells + local % TileCells);
    }

    static (double wx, double wy) Centre(Grid g, int idx)
    {
        var (r, c) = RowCol(g, idx);
        return (Origin - (r + 0.5) * CellYards, Origin - (c + 0.5) * CellYards);
    }

    /// <summary>Land masses: 8-connected walkable or swimmable cells; nodes only go on big ones.</summary>
    static void Components(Grid g, Config cfg)
    {
        g.Comp = new int[g.Kind.Length];
        Array.Fill(g.Comp, -1);
        var sizes = new List<int>();
        var stack = new Stack<(int r, int c)>();
        var tileOf = g.TileOf;
        for (var idx = 0; idx < g.Kind.Length; idx++)
        {
            if (g.Kind[idx] == Blocked || g.Comp[idx] >= 0) continue;
            var id = sizes.Count;
            var size = 0;
            var t = tileOf[idx / TileArea];
            var local = idx % TileArea;
            stack.Push(((t / 64) * TileCells + local / TileCells, (t % 64) * TileCells + local % TileCells));
            g.Comp[idx] = id;
            while (stack.Count > 0)
            {
                var (r, c) = stack.Pop();
                size++;
                foreach (var (dr, dc, _) in Steps)
                {
                    var n = g.Idx(r + dr, c + dc);
                    if (n < 0 || g.Kind[n] == Blocked || g.Comp[n] >= 0) continue;
                    g.Comp[n] = id;
                    stack.Push((r + dr, c + dc));
                }
            }
            sizes.Add(size);
        }
        g.CompSize = sizes.ToArray();
    }

    /// <summary>The cell for a node: the nearest walkable cell of a big land mass within `radius` yards; with
    /// `roadRadius`, the nearest road cell within that distance first.</summary>
    static int Snap(Grid g, Config cfg, double wx, double wy, double radius, double roadRadius,
        double? wz = null)
    {
        var r0 = (int)Math.Floor((Origin - wx) / CellYards);
        var c0 = (int)Math.Floor((Origin - wy) / CellYards);
        var reach = (int)Math.Ceiling(Math.Max(radius, roadRadius) / CellYards);
        int best = -1, bestRoad = -1;
        double bestD = double.MaxValue, bestRoadD = double.MaxValue;
        for (var dr = -reach; dr <= reach; dr++)
        for (var dc = -reach; dc <= reach; dc++)
        {
            var idx = g.Idx(r0 + dr, c0 + dc);
            if (idx < 0 || g.Kind[idx] != Walk || g.CompSize[g.Comp[idx]] < cfg.MinIsland) continue;
            if (wz is double z && Math.Abs(g.Height[idx] - z) > cfg.HeightTolerance) continue;
            var d = Math.Sqrt(dr * dr + dc * dc) * CellYards;
            if (d <= radius && d < bestD) { bestD = d; best = idx; }
            if (g.Road[idx] && d <= roadRadius && d < bestRoadD) { bestRoadD = d; bestRoad = idx; }
        }
        return bestRoad >= 0 ? bestRoad : best;
    }

    /// <summary>A bounded Dijkstra on a square window around the source, reused across sources of one thread.</summary>
    sealed class Search(Grid g, Config cfg)
    {
        readonly int side = 2 * (int)Math.Ceiling(cfg.Radius / CellYards) + 1;
        double[] dist = [];
        int[] parent = [];
        int[] stamp = [];
        int run;

        public List<Edge> From(int source, int cell, Dictionary<int, int> nodeAt)
        {
            if (dist.Length == 0)
            {
                dist = new double[side * side];
                parent = new int[side * side];
                stamp = new int[side * side];
            }
            run++;
            var half = side / 2;
            var (r0, c0) = RowCol(g, cell);
            var heap = new PriorityQueue<int, (double, int)>();
            int Local(int r, int c) => (r - r0 + half) * side + (c - c0 + half);
            var start = Local(r0, c0);
            dist[start] = 0; parent[start] = -1; stamp[start] = run;
            heap.Enqueue(start, (0, start));
            var result = new List<Edge>();
            var done = new HashSet<int>();
            while (heap.TryDequeue(out var cur, out var pri))
            {
                if (pri.Item1 > dist[cur]) continue;
                int r = cur / side - half + r0, c = cur % side - half + c0;
                var idx = g.Idx(r, c);
                if (cur != start && nodeAt.TryGetValue(idx, out var other) && other != source && done.Add(other))
                {
                    result.Add(Trace(source, other, cur, r0, c0));
                    if (result.Count >= cfg.Neighbours) break;
                }
                foreach (var (dr, dc, d) in Steps)
                {
                    int nr = r + dr, nc = c + dc;
                    if (Math.Abs(nr - r0) > half || Math.Abs(nc - c0) > half) continue;
                    var nidx = g.Idx(nr, nc);
                    if (nidx < 0 || g.Kind[nidx] == Blocked) continue;
                    if (dr != 0 && dc != 0) // no corner cutting past a blocked cell
                    {
                        var a = g.Idx(r + dr, c);
                        var b = g.Idx(r, c + dc);
                        if (a < 0 || b < 0 || g.Kind[a] == Blocked || g.Kind[b] == Blocked) continue;
                    }
                    var factor = g.Kind[nidx] == Swim ? cfg.SwimFactor : g.Road[nidx] ? cfg.RoadFactor : 1.0;
                    var nd = dist[cur] + d * CellYards * factor;
                    var loc = Local(nr, nc);
                    if (stamp[loc] == run && dist[loc] <= nd) continue;
                    stamp[loc] = run; dist[loc] = nd; parent[loc] = cur;
                    heap.Enqueue(loc, (nd, loc));
                }
            }
            return result;
        }

        Edge Trace(int source, int target, int at, int r0, int c0)
        {
            var half = side / 2;
            var e = new Edge { A = source, B = target, Cost = dist[at] };
            var cells = new List<int>();
            for (var p = at; p >= 0; p = parent[p])
                cells.Add(g.Idx(p / side - half + r0, p % side - half + c0));
            cells.Reverse();
            for (var i = 1; i < cells.Count; i++)
            {
                var (ar, ac) = RowCol(g, cells[i - 1]);
                var (br, bc) = RowCol(g, cells[i]);
                var d = Math.Sqrt((ar - br) * (ar - br) + (ac - bc) * (ac - bc)) * CellYards;
                e.Len += d;
                if (g.Kind[cells[i]] == Swim) e.SwimLen += d;
            }
            e.Cells = cells;
            return e;
        }
    }

    /// <summary>The network as connected as the land: wherever one land mass holds several parts of the
    /// network (the nearest-neighbour search did not reach across a long pass), a search from the smallest
    /// part over the whole land mass adds the cheapest path to another part, until one part is left.
    /// Returns the number of edges added.</summary>
    static int Stitch(Grid g, Config cfg, List<(string id, int cell, bool lattice)> nodes, List<Edge> edges)
    {
        var parent = Enumerable.Range(0, nodes.Count).ToArray();
        int Find(int x) { while (parent[x] != x) x = parent[x] = parent[parent[x]]; return x; }
        foreach (var e in edges) parent[Find(e.A)] = Find(e.B);
        var nodeAt = new Dictionary<int, int>();
        for (var i = 0; i < nodes.Count; i++) nodeAt.TryAdd(nodes[i].cell, i);
        var dist = new float[g.Kind.Length];
        var from = new int[g.Kind.Length];
        var stamp = new int[g.Kind.Length];
        var run = 0;
        var added = 0;
        while (true)
        {
            // the parts per land mass; the smallest part of a land mass with several
            var parts = new Dictionary<int, Dictionary<int, List<int>>>();
            for (var i = 0; i < nodes.Count; i++)
            {
                var mass = g.Comp[nodes[i].cell];
                if (!parts.TryGetValue(mass, out var byRoot)) parts[mass] = byRoot = [];
                var root = Find(i);
                if (!byRoot.TryGetValue(root, out var list)) byRoot[root] = list = [];
                list.Add(i);
            }
            var split = parts.Where(kv => kv.Value.Count > 1).OrderBy(kv => kv.Key).Select(kv => kv.Value).FirstOrDefault();
            if (split == null) break;
            var part = split.OrderBy(kv => kv.Value.Count).ThenBy(kv => kv.Key).First().Value;
            var root0 = Find(part[0]);
            run++;
            var heap = new PriorityQueue<int, (float, int)>();
            foreach (var i in part)
            {
                var c = nodes[i].cell;
                dist[c] = 0; from[c] = -1; stamp[c] = run;
                heap.Enqueue(c, (0, c));
            }
            var hit = -1;
            while (heap.TryDequeue(out var cur, out var pri))
            {
                if (pri.Item1 > dist[cur]) continue;
                if (nodeAt.TryGetValue(cur, out var other) && Find(other) != root0) { hit = cur; break; }
                var (r, c) = RowCol(g, cur);
                foreach (var (dr, dc, d) in Steps)
                {
                    var n = g.Idx(r + dr, c + dc);
                    if (n < 0 || g.Kind[n] == Blocked) continue;
                    if (dr != 0 && dc != 0)
                    {
                        var a = g.Idx(r + dr, c);
                        var b = g.Idx(r, c + dc);
                        if (a < 0 || b < 0 || g.Kind[a] == Blocked || g.Kind[b] == Blocked) continue;
                    }
                    var factor = g.Kind[n] == Swim ? cfg.SwimFactor : g.Road[n] ? cfg.RoadFactor : 1.0;
                    var nd = (float)(dist[cur] + d * CellYards * factor);
                    if (stamp[n] == run && dist[n] <= nd) continue;
                    stamp[n] = run; dist[n] = nd; from[n] = cur;
                    heap.Enqueue(n, (nd, n));
                }
            }
            if (hit < 0)
            {
                // nothing else reachable from this part (a split the land masses do not show): merge
                // it away so the loop ends; it stays a part of its own
                foreach (var i in split.Keys.ToList()) parent[Find(i)] = Find(split.Keys.First());
                continue;
            }
            var cells = new List<int>();
            for (var p = hit; p >= 0; p = from[p]) cells.Add(p);
            cells.Reverse();
            var e = new Edge { A = nodeAt[cells[0]], B = nodeAt[hit], Cost = dist[hit], Cells = cells };
            for (var i = 1; i < cells.Count; i++)
            {
                var (ar, ac) = RowCol(g, cells[i - 1]);
                var (br, bc) = RowCol(g, cells[i]);
                var d = Math.Sqrt((ar - br) * (ar - br) + (ac - bc) * (ac - bc)) * CellYards;
                e.Len += d;
                if (g.Kind[cells[i]] == Swim) e.SwimLen += d;
            }
            edges.Add(e);
            parent[Find(e.A)] = Find(e.B);
            added++;
        }
        return added;
    }

    /// <summary>Drops an edge a-c when some b with edges a-b and b-c is (nearly) as cheap: the network keeps the
    /// short links, the long ones are their sum. Ordered by cost, so the result does not depend on threads.</summary>
    static List<Edge> Prune(Dictionary<(int, int), Edge> edges, double slack)
    {
        var adj = new Dictionary<int, Dictionary<int, double>>();
        foreach (var ((a, b), e) in edges)
        {
            (adj.TryGetValue(a, out var x) ? x : adj[a] = []).Add(b, e.Cost);
            (adj.TryGetValue(b, out var y) ? y : adj[b] = []).Add(a, e.Cost);
        }
        var kept = new List<Edge>();
        foreach (var ((a, c), e) in edges.OrderBy(kv => kv.Key))
        {
            var redundant = false;
            foreach (var (b, ab) in adj[a])
            {
                if (b == c || !adj[b].TryGetValue(c, out var bc)) continue;
                if (ab < e.Cost && bc < e.Cost && ab + bc <= e.Cost * slack) { redundant = true; break; }
            }
            if (!redundant) kept.Add(e);
        }
        return kept;
    }

    /// <summary>Douglas-Peucker in world yards.</summary>
    static List<(double wx, double wy)> Simplify(List<(double wx, double wy)> pts, double tolerance)
    {
        if (pts.Count < 3) return pts;
        var keep = new bool[pts.Count];
        keep[0] = keep[^1] = true;
        var stack = new Stack<(int, int)>();
        stack.Push((0, pts.Count - 1));
        while (stack.Count > 0)
        {
            var (i, j) = stack.Pop();
            double best = 0; var at = -1;
            var (ax, ay) = pts[i]; var (bx, by) = pts[j];
            double dx = bx - ax, dy = by - ay, len = Math.Sqrt(dx * dx + dy * dy);
            for (var k = i + 1; k < j; k++)
            {
                var (px, py) = pts[k];
                var d = len == 0 ? Math.Sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay))
                    : Math.Abs(dy * (px - ax) - dx * (py - ay)) / len;
                if (d > best) { best = d; at = k; }
            }
            if (at >= 0 && best > tolerance) { keep[at] = true; stack.Push((i, at)); stack.Push((at, j)); }
        }
        return pts.Where((_, k) => keep[k]).ToList();
    }

    /// <summary>The cells and the network, two cells per pixel: steep or missing ground dark, water blue, roads
    /// orange, edges red, nodes white.</summary>
    static void Picture(Grid g, List<(string id, int cell, bool lattice)> nodes, List<Edge> edges, string path)
    {
        const int Scale = 2;
        int w = (g.MaxC - g.MinC + 1) / Scale, h = (g.MaxR - g.MinR + 1) / Scale;
        var px = new byte[w * h * 4];
        void Put(int r, int c, byte b, byte gr, byte red)
        {
            int y = (r - g.MinR) / Scale, x = (c - g.MinC) / Scale;
            if (x < 0 || y < 0 || x >= w || y >= h) return;
            var o = (y * w + x) * 4;
            px[o] = b; px[o + 1] = gr; px[o + 2] = red; px[o + 3] = 255;
        }
        for (var r = g.MinR; r <= g.MaxR; r += Scale)
        for (var c = g.MinC; c <= g.MaxC; c += Scale)
        {
            var idx = g.Idx(r, c);
            if (idx < 0) continue;
            switch (g.Kind[idx])
            {
                case Blocked: Put(r, c, 60, 60, 60); break;
                case Swim: Put(r, c, 200, 120, 40); break;
                default:
                    if (g.Road[idx]) Put(r, c, 40, 150, 240);
                    else Put(r, c, 150, 200, 170);
                    break;
            }
        }
        foreach (var e in edges)
        foreach (var cell in e.Cells)
        {
            var (r, c) = RowCol(g, cell);
            Put(r, c, 30, 30, 220);
        }
        foreach (var n in nodes)
        {
            var (r, c) = RowCol(g, n.cell);
            for (var dr = -2; dr <= 2; dr++)
            for (var dc = -2; dc <= 2; dc++)
                if (n.lattice) Put(r + dr, c + dc, 255, 255, 255);
                else Put(r + dr * 2, c + dc * 2, 255, 0, 255);
        }
        Png.Write(path, px, w, h);
        Console.WriteLine($"picture -> {path} ({w}x{h})");
    }
}
