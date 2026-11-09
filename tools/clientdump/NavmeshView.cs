// Reads a .navmesh file (Navmesh.Write): top-down images coloured by area, and a height check of known points
// (the client's TaxiNodes) against the mesh. Opens no client.
using System.IO.Compression;
using System.Text.Json;
using DotRecast.Core;
using DotRecast.Core.Numerics;
using DotRecast.Detour;
using DotRecast.Detour.Io;

namespace ClientDump;

sealed class NavmeshFile
{
    public int MapId, Split, TileCells;
    public string Build = "";
    public float Cs, Ch, AgentHeight, AgentRadius, AgentClimb, MaxSlope, SwimDepth, TileWidth;
    public int MaxTiles, MaxPolys;
    public readonly Dictionary<(int x, int y), (int n, int offset, int length)> Index = [];
    public readonly Dictionary<(int x, int y), uint[]> AreaIds = []; // version 2: per ADT tile 256 chunk area ids

    /// <summary>The AreaTable id of the terrain chunk under a point of the recast frame; null when none.</summary>
    public int? AreaAt(double rx, double rz)
    {
        int ax = (int)Math.Floor(rx / Frame.Tile), ay = (int)Math.Floor(rz / Frame.Tile);
        if (!AreaIds.TryGetValue((ax, ay), out var ids)) return null;
        int cx = Math.Clamp((int)Math.Floor((rx - ax * Frame.Tile) / Frame.Chunk), 0, 15);
        int cy = Math.Clamp((int)Math.Floor((rz - ay * Frame.Tile) / Frame.Chunk), 0, 15);
        var id = ids[cy * 16 + cx];
        return id == 0 ? null : (int)id;
    }
    string path = "";

    public static NavmeshFile Open(string path)
    {
        var f = new NavmeshFile { path = path };
        using var r = new BinaryReader(File.OpenRead(path));
        if (new string(r.ReadChars(4)) != "BNAV") throw new InvalidDataException(path + " is not a navmesh file");
        var version = r.ReadUInt32();
        if (version is not (1 or 2)) throw new InvalidDataException($"navmesh version {version} not supported");
        f.MapId = r.ReadInt32();
        f.Build = System.Text.Encoding.UTF8.GetString(r.ReadBytes(r.ReadByte()));
        f.Cs = r.ReadSingle(); f.Ch = r.ReadSingle(); f.AgentHeight = r.ReadSingle(); f.AgentRadius = r.ReadSingle();
        f.AgentClimb = r.ReadSingle(); f.MaxSlope = r.ReadSingle(); f.SwimDepth = r.ReadSingle();
        f.Split = r.ReadInt32(); f.TileCells = r.ReadInt32();
        r.ReadSingle(); r.ReadSingle(); r.ReadSingle();
        f.TileWidth = r.ReadSingle(); r.ReadSingle();
        f.MaxTiles = r.ReadInt32(); f.MaxPolys = r.ReadInt32();
        var n = r.ReadInt32();
        for (var i = 0; i < n; i++)
        {
            int x = r.ReadInt32(), y = r.ReadInt32(), tiles = r.ReadInt32(), off = r.ReadInt32(), len = r.ReadInt32();
            f.Index[(x, y)] = (tiles, off, len);
        }
        if (version >= 2)
        {
            int m = r.ReadInt32(), off = r.ReadInt32(), len = r.ReadInt32();
            r.BaseStream.Seek(off, SeekOrigin.Begin);
            using var z = new ZLibStream(new MemoryStream(r.ReadBytes(len)), CompressionMode.Decompress);
            using var ar = new BinaryReader(z);
            for (var i = 0; i < m; i++)
            {
                int x = ar.ReadInt32(), y = ar.ReadInt32();
                var ids = new uint[256];
                for (var c = 0; c < 256; c++) ids[c] = ar.ReadUInt32();
                f.AreaIds[(x, y)] = ids;
            }
        }
        return f;
    }

    public List<DtMeshData> Read(int x, int y)
    {
        var list = new List<DtMeshData>();
        if (!Index.TryGetValue((x, y), out var e)) return list;
        using var fs = File.OpenRead(path);
        fs.Seek(e.offset, SeekOrigin.Begin);
        var block = new byte[e.length];
        fs.ReadExactly(block);
        using var z = new ZLibStream(new MemoryStream(block), CompressionMode.Decompress);
        using var r = new BinaryReader(z);
        for (var i = 0; i < e.n; i++)
        {
            r.ReadInt32(); r.ReadInt32();
            var data = r.ReadBytes(r.ReadInt32());
            list.Add(new DtMeshDataReader().Read(new BinaryReader(new MemoryStream(data)), DtDetour.DT_VERTS_PER_POLYGON));
        }
        return list;
    }

    public DtNavMesh NewMesh()
    {
        var mesh = new DtNavMesh();
        mesh.Init(new DtNavMeshParams
        {
            orig = new RcVec3f(0, 0, 0), tileWidth = TileWidth, tileHeight = TileWidth, maxTiles = MaxTiles, maxPolys = MaxPolys,
        }, DtDetour.DT_VERTS_PER_POLYGON);
        return mesh;
    }
}

static class NavmeshView
{
    // ground, road, shallow, deep, indoor, blocked (RGB)
    static readonly byte[][] Colours =
    [
        [40, 40, 44], [92, 158, 74], [222, 190, 96], [120, 196, 222], [40, 90, 200], [176, 112, 210], [220, 50, 40],
    ];

    /// <summary>--tiles x0,y0,x1,y1 (ADT tiles) or --at wx,wy,radius (world yards); --z zmin,zmax keeps the
    /// highest mesh between the two heights (a city under the ground); --ppy pixels per yard.</summary>
    public static void Png(string meshPath, string outPath, string? tilesArg, string? atArg, string? zArg, string? ppyArg)
    {
        var f = NavmeshFile.Open(meshPath);
        double minX, minZ, maxX, maxZ;
        if (atArg != null)
        {
            var a = atArg.Split(',').Select(v => double.Parse(v, System.Globalization.CultureInfo.InvariantCulture)).ToArray();
            var (rx, _, rz) = Frame.FromWorld(a[0], a[1], 0);
            (minX, maxX, minZ, maxZ) = (rx - a[2], rx + a[2], rz - a[2], rz + a[2]);
        }
        else
        {
            var t = (tilesArg ?? throw new ArgumentException("--tiles or --at is required")).Split(',').Select(int.Parse).ToArray();
            (minX, maxX, minZ, maxZ) = (t[0] * Frame.Tile, (t[2] + 1) * Frame.Tile, t[1] * Frame.Tile, (t[3] + 1) * Frame.Tile);
        }
        float zmin = float.MinValue, zmax = float.MaxValue;
        if (zArg != null)
        {
            var z = zArg.Split(',').Select(v => float.Parse(v, System.Globalization.CultureInfo.InvariantCulture)).ToArray();
            (zmin, zmax) = (z[0], z[1]);
        }
        double? ppyGiven = ppyArg != null ? double.Parse(ppyArg, System.Globalization.CultureInfo.InvariantCulture) : null;
        var (px, w, h, _, _, ppy, polys, hlo, hhi) = Render(f, minX, maxX, minZ, maxZ, zmin, zmax, ppyGiven);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(outPath))!);
        ClientDump.Png.Write(outPath, px, w, h);
        Console.WriteLine($"{outPath}: {w} x {h} px, {ppy:0.##} px per yard, {polys} polys, heights {hlo:0}..{hhi:0}" +
            (zArg != null ? $" (kept {zmin}..{zmax})" : ""));
    }

    /// <summary>The mesh between the bounds (recast frame) drawn top down: BGRA pixels and the mapping.</summary>
    public static (byte[] px, int w, int h, double minX, double minZ, double ppy, int polys, float hlo, float hhi) Render(
        NavmeshFile f, double minX, double maxX, double minZ, double maxZ, float zmin, float zmax, double? ppyGiven)
    {
        var ppy = ppyGiven ?? Math.Min(4, 2048 / Math.Max(maxX - minX, maxZ - minZ));
        int w = (int)Math.Ceiling((maxX - minX) * ppy), h = (int)Math.Ceiling((maxZ - minZ) * ppy);
        var zbuf = new float[w * h];
        Array.Fill(zbuf, float.MinValue);
        var poly = new int[w * h];
        var area = new byte[w * h];
        var polyId = 0;
        float hlo = float.MaxValue, hhi = float.MinValue;
        int ax0 = (int)Math.Floor(minX / Frame.Tile), ax1 = (int)Math.Floor((maxX - 1e-6) / Frame.Tile);
        int az0 = (int)Math.Floor(minZ / Frame.Tile), az1 = (int)Math.Floor((maxZ - 1e-6) / Frame.Tile);
        var polys = 0;
        for (var ay = az0; ay <= az1; ay++)
        for (var ax = ax0; ax <= ax1; ax++)
        foreach (var d in f.Read(ax, ay))
        {
            for (var pi = 0; pi < d.header.polyCount; pi++)
            {
                var p = d.polys[pi];
                polyId++;
                var dm = d.detailMeshes[pi];
                var drew = false;
                for (var ti = 0; ti < dm.triCount; ti++)
                {
                    var tb = (dm.triBase + ti) * 4;
                    var v = new RcVec3f[3];
                    for (var k = 0; k < 3; k++)
                    {
                        var idx = d.detailTris[tb + k];
                        v[k] = idx < p.vertCount
                            ? new RcVec3f(d.verts[p.verts[idx] * 3], d.verts[p.verts[idx] * 3 + 1], d.verts[p.verts[idx] * 3 + 2])
                            : new RcVec3f(d.detailVerts[(dm.vertBase + idx - p.vertCount) * 3],
                                d.detailVerts[(dm.vertBase + idx - p.vertCount) * 3 + 1],
                                d.detailVerts[(dm.vertBase + idx - p.vertCount) * 3 + 2]);
                    }
                    drew |= Raster(v, minX, minZ, ppy, w, h, zbuf, poly, area, polyId, (byte)p.GetArea(), zmin, zmax);
                }
                if (!drew) continue;
                polys++;
                for (var k = 0; k < p.vertCount; k++)
                {
                    var y = d.verts[p.verts[k] * 3 + 1];
                    if (y < zmin || y > zmax) continue;
                    hlo = Math.Min(hlo, y); hhi = Math.Max(hhi, y);
                }
            }
        }
        var px = new byte[w * h * 4];
        var range = Math.Max(1, hhi - hlo);
        for (var i = 0; i < w * h; i++)
        {
            var c = Colours[Math.Min(area[i], (byte)6)];
            var shade = area[i] == 0 ? 1.0 : 0.55 + 0.45 * (zbuf[i] - hlo) / range;
            int x = i % w, y = i / w;
            var edge = area[i] != 0 && ((x + 1 < w && poly[i + 1] != poly[i]) || (y + 1 < h && poly[i + w] != poly[i]));
            if (edge) shade *= 0.6;
            px[i * 4] = (byte)Math.Clamp(c[2] * shade, 0, 255);
            px[i * 4 + 1] = (byte)Math.Clamp(c[1] * shade, 0, 255);
            px[i * 4 + 2] = (byte)Math.Clamp(c[0] * shade, 0, 255);
            px[i * 4 + 3] = 255;
        }
        return (px, w, h, minX, minZ, ppy, polys, hlo, hhi);
    }

    static bool Raster(RcVec3f[] v, double minX, double minZ, double ppy, int w, int h, float[] zbuf, int[] poly,
        byte[] area, int id, byte a, float zmin, float zmax)
    {
        double X(RcVec3f p) => (p.X - minX) * ppy;
        double Z(RcVec3f p) => (p.Z - minZ) * ppy;
        double x1 = X(v[0]), z1 = Z(v[0]), x2 = X(v[1]), z2 = Z(v[1]), x3 = X(v[2]), z3 = Z(v[2]);
        var det = (z2 - z3) * (x1 - x3) + (x3 - x2) * (z1 - z3);
        if (Math.Abs(det) < 1e-12) return false;
        int px0 = Math.Max(0, (int)Math.Floor(Math.Min(x1, Math.Min(x2, x3)))), px1 = Math.Min(w - 1, (int)Math.Ceiling(Math.Max(x1, Math.Max(x2, x3))));
        int pz0 = Math.Max(0, (int)Math.Floor(Math.Min(z1, Math.Min(z2, z3)))), pz1 = Math.Min(h - 1, (int)Math.Ceiling(Math.Max(z1, Math.Max(z2, z3))));
        var drew = false;
        for (var pz = pz0; pz <= pz1; pz++)
        for (var px = px0; px <= px1; px++)
        {
            double cx = px + 0.5, cz = pz + 0.5;
            var l1 = ((z2 - z3) * (cx - x3) + (x3 - x2) * (cz - z3)) / det;
            var l2 = ((z3 - z1) * (cx - x3) + (x1 - x3) * (cz - z3)) / det;
            var l3 = 1 - l1 - l2;
            if (l1 < -1e-6 || l2 < -1e-6 || l3 < -1e-6) continue;
            var y = (float)(l1 * v[0].Y + l2 * v[1].Y + l3 * v[2].Y);
            if (y < zmin || y > zmax) continue;
            var i = pz * w + px;
            if (y <= zbuf[i]) continue;
            zbuf[i] = y; poly[i] = id; area[i] = a;
            drew = true;
        }
        return drew;
    }

    /// <summary>Where one can walk, as a raster for the city plans (map.md "City plans"): a byte per pixel, bits
    /// 1 ground, 2 road, 4 indoor, 8 shallow water, 16 deep water, 32 passage. Every floor over a pixel counts. Only
    /// ground joined to a large region (a roof nobody reaches is no way). A passage is an indoor part of the mesh
    /// that meets the outdoors at places more than `span` yards apart: a tunnel or gate, not a shop.</summary>
    public static void Walk(string meshPath, string outPath, string originArg, string sizeArg, double ppy, string? seedArg, double span = 25)
    {
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        var o = originArg.Split(',').Select(x => double.Parse(x, inv)).ToArray();
        var s = sizeArg.Split(',').Select(x => int.Parse(x, inv)).ToArray();
        double minX = o[0], minZ = o[1];
        int w = s[0], h = s[1];
        var f = NavmeshFile.Open(meshPath);
        var mesh = f.NewMesh();
        int ax0 = (int)Math.Floor(minX / Frame.Tile) - 1, ax1 = (int)Math.Floor((minX + w / ppy) / Frame.Tile) + 1;
        int az0 = (int)Math.Floor(minZ / Frame.Tile) - 1, az1 = (int)Math.Floor((minZ + h / ppy) / Frame.Tile) + 1;
        for (var ay = az0; ay <= az1; ay++)
        for (var ax = ax0; ax <= ax1; ax++)
            if (f.Index.ContainsKey((ax, ay)))
                foreach (var d in f.Read(ax, ay)) mesh.AddTile(d, 0, 0, out _);
        var tileBase = new int[mesh.GetMaxTiles()];
        var n = 0;
        for (var i = 0; i < mesh.GetMaxTiles(); i++)
        {
            var t = mesh.GetTile(i);
            if (t?.data == null) continue;
            tileBase[i] = n;
            n += t.data.header.polyCount;
        }
        int Gid(long r) => tileBase[DtDetour.DecodePolyIdTile(r)] + DtDetour.DecodePolyIdPoly(r);
        var area = new byte[n];
        var centers = new RcVec3f[n];
        var size = new double[n];
        var parent = new int[n];
        var indoorParent = new int[n];
        for (var i = 0; i < n; i++) { parent[i] = i; indoorParent[i] = i; }
        int Find(int[] p, int x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; } return x; }
        void Each(Action<DtMeshTile, int, DtPoly, int> fn)
        {
            for (var i = 0; i < mesh.GetMaxTiles(); i++)
            {
                var t = mesh.GetTile(i);
                if (t?.data == null) continue;
                for (var ip = 0; ip < t.data.header.polyCount; ip++) fn(t, ip, t.data.polys[ip], tileBase[i] + ip);
            }
        }
        Each((t, ip, p, g) =>
        {
            area[g] = (byte)p.GetArea();
            centers[g] = mesh.GetPolyCenter(DtDetour.EncodePolyId(t.salt, t.index, ip));
            double a = 0;
            for (var k = 0; k < p.vertCount; k++)
            {
                int i0 = p.verts[k] * 3, i1 = p.verts[(k + 1) % p.vertCount] * 3;
                a += t.data.verts[i0] * t.data.verts[i1 + 2] - t.data.verts[i1] * t.data.verts[i0 + 2];
            }
            size[g] = Math.Abs(a / 2);
        });
        void Union(int[] p, int a, int b) { int ra = Find(p, a), rb = Find(p, b); if (ra != rb) p[Math.Max(ra, rb)] = Math.Min(ra, rb); }
        Each((t, ip, p, g) =>
        {
            if (area[g] == Navmesh.AreaBlocked) return;
            for (var j = p.firstLink; j != DtDetour.DT_NULL_LINK; j = t.links[j].next)
            {
                var o2 = Gid(t.links[j].refs);
                if (area[o2] == Navmesh.AreaBlocked) continue;
                Union(parent, g, o2);
                if (area[g] == Navmesh.AreaIndoor && area[o2] == Navmesh.AreaIndoor) Union(indoorParent, g, o2);
            }
        });
        var regionSize = new Dictionary<int, double>();
        for (var i = 0; i < n; i++)
        {
            var r = Find(parent, i);
            regionSize[r] = regionSize.GetValueOrDefault(r) + size[i];
        }
        // the corners of the places where an indoor part meets the outdoors
        var box = new Dictionary<int, (float x0, float z0, float x1, float z1)>();
        Each((t, ip, p, g) =>
        {
            if (area[g] != Navmesh.AreaIndoor) return;
            for (var j = p.firstLink; j != DtDetour.DT_NULL_LINK; j = t.links[j].next)
            {
                var o2 = Gid(t.links[j].refs);
                if (area[o2] == Navmesh.AreaIndoor || area[o2] == Navmesh.AreaBlocked) continue;
                var c = centers[o2];
                var r = Find(indoorParent, g);
                box[r] = box.TryGetValue(r, out var b)
                    ? (Math.Min(b.x0, c.X), Math.Min(b.z0, c.Z), Math.Max(b.x1, c.X), Math.Max(b.z1, c.Z))
                    : (c.X, c.Z, c.X, c.Z);
            }
        });
        // with a seed (recast x,y,z on a street), only what can be walked to from it: a city lies over
        // terrain nobody reaches (Stormwind's streets stand 40 yards above a hidden ground sheet)
        var seedRegion = -1;
        if (seedArg != null)
        {
            var sv = seedArg.Split(',').Select(x => float.Parse(x, inv)).ToArray();
            var q = new DtNavMeshQuery(mesh);
            q.FindNearestPoly(new RcVec3f(sv[0], sv[1], sv[2]), new RcVec3f(5, 5, 5), new DtQueryDefaultFilter(), out var sr, out _, out _);
            if (sr == 0) throw new ArgumentException("no mesh at the seed");
            seedRegion = Find(parent, Gid(sr));
        }
        var raster = new byte[w * h];
        var zHigh = new float[w * h];
        var zLow = new float[w * h];
        Array.Fill(zHigh, float.NaN);
        Array.Fill(zLow, float.NaN);
        int passages = 0;
        var counted = new HashSet<int>();
        Each((t, ip, p, g) =>
        {
            if (area[g] == Navmesh.AreaBlocked || regionSize[Find(parent, g)] < 2000) return;
            if (seedRegion >= 0 && Find(parent, g) != seedRegion) return;
            byte bits = area[g] switch
            {
                Navmesh.AreaGround => 1,
                Navmesh.AreaRoad => 2,
                Navmesh.AreaIndoor => 4,
                Navmesh.AreaShallow => 8,
                Navmesh.AreaDeep => 16,
                _ => 0,
            };
            if (area[g] == Navmesh.AreaIndoor && box.TryGetValue(Find(indoorParent, g), out var b)
                && Math.Max(b.x1 - b.x0, b.z1 - b.z0) > span)
            {
                bits |= 32;
                if (counted.Add(Find(indoorParent, g))) passages++;
            }
            var dm = t.data.detailMeshes[ip];
            for (var ti = 0; ti < dm.triCount; ti++)
            {
                var tb = (dm.triBase + ti) * 4;
                var v = new (double x, double z, double y)[3];
                for (var k = 0; k < 3; k++)
                {
                    var idx = t.data.detailTris[tb + k];
                    v[k] = idx < p.vertCount
                        ? (t.data.verts[p.verts[idx] * 3], t.data.verts[p.verts[idx] * 3 + 2], t.data.verts[p.verts[idx] * 3 + 1])
                        : (t.data.detailVerts[(dm.vertBase + idx - p.vertCount) * 3], t.data.detailVerts[(dm.vertBase + idx - p.vertCount) * 3 + 2], t.data.detailVerts[(dm.vertBase + idx - p.vertCount) * 3 + 1]);
                    v[k] = ((v[k].x - minX) * ppy, (v[k].z - minZ) * ppy, v[k].y);
                }
                double det = (v[1].z - v[2].z) * (v[0].x - v[2].x) + (v[2].x - v[1].x) * (v[0].z - v[2].z);
                if (Math.Abs(det) < 1e-12) continue;
                int px0 = Math.Max(0, (int)Math.Floor(v.Min(q => q.x))), px1 = Math.Min(w - 1, (int)Math.Ceiling(v.Max(q => q.x)));
                int pz0 = Math.Max(0, (int)Math.Floor(v.Min(q => q.z))), pz1 = Math.Min(h - 1, (int)Math.Ceiling(v.Max(q => q.z)));
                for (var pz = pz0; pz <= pz1; pz++)
                for (var px = px0; px <= px1; px++)
                {
                    double cx = px + 0.5, cz = pz + 0.5;
                    var l1 = ((v[1].z - v[2].z) * (cx - v[2].x) + (v[2].x - v[1].x) * (cz - v[2].z)) / det;
                    var l2 = ((v[2].z - v[0].z) * (cx - v[2].x) + (v[0].x - v[2].x) * (cz - v[2].z)) / det;
                    if (l1 < -1e-6 || l2 < -1e-6 || 1 - l1 - l2 < -1e-6) continue;
                    raster[pz * w + px] |= bits;
                    var y = (float)(l1 * v[0].y + l2 * v[1].y + (1 - l1 - l2) * v[2].y);
                    var at = pz * w + px;
                    if (float.IsNaN(zHigh[at]) || y > zHigh[at]) zHigh[at] = y;
                    if (float.IsNaN(zLow[at]) || y < zLow[at]) zLow[at] = y;
                }
            }
        });
        File.WriteAllBytes(outPath, raster);
        void Floats(string path, float[] a) { var b = new byte[a.Length * 4]; Buffer.BlockCopy(a, 0, b, 0, b.Length); File.WriteAllBytes(path, b); }
        Floats(outPath + ".high", zHigh);
        Floats(outPath + ".low", zLow);
        Console.WriteLine($"navmesh-walk: {w} x {h}, {n} polys, {passages} passages -> {outPath}");
    }

    /// <summary>A walk from one world point to another over the mesh (blocked liquid excluded): whether the goal
    /// is reached, the corridor's polygons by area and the length of the straight path.</summary>
    public static void Path(string meshPath, string fromArg, string toArg, bool corners)
    {
        var f = NavmeshFile.Open(meshPath);
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        RcVec3f P(string a)
        {
            var v = a.Split(',').Select(x => double.Parse(x, inv)).ToArray();
            var (rx, ry, rz) = Frame.FromWorld(v[0], v[1], v[2]);
            return new RcVec3f((float)rx, (float)ry, (float)rz);
        }
        RcVec3f a = P(fromArg), b = P(toArg);
        var mesh = f.NewMesh();
        int x0 = (int)Math.Floor(Math.Min(a.X, b.X) / Frame.Tile) - 1, x1 = (int)Math.Floor(Math.Max(a.X, b.X) / Frame.Tile) + 1;
        int y0 = (int)Math.Floor(Math.Min(a.Z, b.Z) / Frame.Tile) - 1, y1 = (int)Math.Floor(Math.Max(a.Z, b.Z) / Frame.Tile) + 1;
        for (var y = y0; y <= y1; y++)
        for (var x = x0; x <= x1; x++)
            foreach (var d in f.Read(x, y)) mesh.AddTile(d, 0, 0, out _);
        var areaCost = Enumerable.Repeat(1f, 64).ToArray();
        var filter = new DtQueryDefaultFilter(0xffff & ~Navmesh.FlagBlocked, Navmesh.FlagBlocked, areaCost);
        var q = new DtNavMeshQuery(mesh);
        var ext = new RcVec3f(3, 10, 3);
        q.FindNearestPoly(a, ext, filter, out var sa, out var pa, out _);
        q.FindNearestPoly(b, ext, filter, out var sb, out var pb, out _);
        if (sa == 0 || sb == 0) { Console.WriteLine($"path: no mesh at the {(sa == 0 ? "start" : "goal")}"); return; }
        var path = new long[1 << 16];
        q.FindPath(sa, sb, pa, pb, filter, path, out var n, path.Length);
        var reached = n > 0 && path[n - 1] == sb;
        var byArea = new SortedDictionary<string, int>();
        for (var i = 0; i < n; i++)
        {
            mesh.GetTileAndPolyByRef(path[i], out _, out var poly);
            var name = Navmesh.AreaNames[Math.Min(poly.GetArea(), 6)];
            byArea[name] = byArea.GetValueOrDefault(name) + 1;
        }
        var straight = new DtStraightPath[4096];
        q.FindStraightPath(pa, pb, path, n, straight, out var sn, straight.Length, 0);
        double len = 0;
        for (var i = 1; i < sn; i++) len += RcVec3f.Distance(straight[i - 1].pos, straight[i].pos);
        var direct = RcVec3f.Distance(pa, pb);
        Console.WriteLine($"path: {(reached ? "reached" : "NOT reached")}, {n} polys ({string.Join(", ", byArea.Select(kv => $"{kv.Key} {kv.Value}"))}), " +
            $"{sn} corners, {len:0} yards walked for {direct:0} straight ({(direct > 0 ? len / direct : 0):0.00}x)");
        for (var i = 0; i < sn; i++)
            if (corners || (!reached && i == sn - 1))
            {
                var (wx, wy, wz) = Frame.ToWorld(straight[i].pos.X, straight[i].pos.Y, straight[i].pos.Z);
                mesh.GetTileAndPolyByRef(straight[i].refs, out _, out var cp);
                Console.WriteLine($"  {(i == sn - 1 && !reached ? "ends" : "corner")} {wx:0},{wy:0},{wz:0} {(cp != null ? Navmesh.AreaNames[Math.Min(cp.GetArea(), 6)] : "")}");
            }
    }

    /// <summary>Every taxi node of the mesh's map (a clientdump TaxiNodes JSON) against the mesh: the nearest
    /// polygon within 3 yards across and 10 up or down, its height difference and area.</summary>
    public static void Check(string meshPath, string taxiPath)
    {
        var f = NavmeshFile.Open(meshPath);
        var mesh = f.NewMesh();
        var loaded = new HashSet<(int, int)>();
        using var doc = JsonDocument.Parse(File.ReadAllBytes(taxiPath));
        var rows = doc.RootElement.GetProperty("rows").EnumerateArray()
            .Where(r => r.GetProperty("ContinentID").GetInt32() == f.MapId).ToList();
        var filter = new DtQueryDefaultFilter();
        int ok = 0, near = 0, none = 0, outside = 0;
        var diffs = new List<double>();
        foreach (var r in rows)
        {
            var pos = r.GetProperty("Pos").EnumerateArray().Select(e => e.GetDouble()).ToArray();
            var (rx, ry, rz) = Frame.FromWorld(pos[0], pos[1], pos[2]);
            int ax = (int)Math.Floor(rx / Frame.Tile), ay = (int)Math.Floor(rz / Frame.Tile);
            if (!f.Index.ContainsKey((ax, ay))) { outside++; continue; }
            for (var dy = -1; dy <= 1; dy++)
            for (var dx = -1; dx <= 1; dx++)
                if (loaded.Add((ax + dx, ay + dy)))
                    foreach (var d in f.Read(ax + dx, ay + dy)) mesh.AddTile(d, 0, 0, out _);
            var q = new DtNavMeshQuery(mesh);
            q.FindNearestPoly(new RcVec3f((float)rx, (float)ry, (float)rz), new RcVec3f(3, 10, 3), filter,
                out var refId, out var pt, out _);
            var name = r.GetProperty("Name_lang").GetString();
            if (refId == 0)
            {
                none++;
                Console.WriteLine($"  {r.GetProperty("ID").GetInt32(),4} {name}: no mesh within 3 / 10 yards (z {pos[2]:0.0})");
                continue;
            }
            mesh.GetTileAndPolyByRef(refId, out _, out var p);
            var dz = pt.Y - ry;
            var dxy = Math.Sqrt((pt.X - rx) * (pt.X - rx) + (pt.Z - rz) * (pt.Z - rz));
            diffs.Add(Math.Abs(dz));
            if (Math.Abs(dz) <= 2 && dxy <= 2) ok++; else near++;
            Console.WriteLine($"  {r.GetProperty("ID").GetInt32(),4} {name}: dz {dz:+0.0;-0.0}, {dxy:0.0} yards across, " +
                $"area {Navmesh.AreaNames[Math.Min(p.GetArea(), 6)]}");
        }
        diffs.Sort();
        Console.WriteLine($"check: {rows.Count} taxi nodes on map {f.MapId}: {ok} on the mesh (within 2 yards), {near} near, " +
            $"{none} without mesh, {outside} outside the built tiles" +
            (diffs.Count > 0 ? $"; |dz| median {diffs[diffs.Count / 2]:0.00}" : ""));
    }
}
