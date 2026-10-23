// Stitches one map's minimap tiles into overview textures for Bastians_Map_Art (map.md "Imagery
// pipeline", roadmap B8.5): every `span` x `span` block of ADT tiles (default 8, so a 64x64 grid gives
// at most 8x8 overview cells) becomes one square texture with `pixels` pixels per ADT (default 64, so
// 512 px); ADTs the map lacks stay transparent. Levels 0-2 of the map come from the one stored texture
// through its mip chain. Output per map: `<Dir>_<cx>_<cy>.blp` (DXT1 with 1-bit alpha, mips) or `.tga`,
// plus `<Dir>_overview.json` listing the cells. Deterministic: cells and tiles in a fixed order,
// integer box filters, no timestamps; files are written only when their bytes change.
using System.Globalization;
using System.Text.Json;
using BLPSharp;

namespace ClientDump;

static class Overview
{
    sealed record Cell(int x, int y, string file, int adts, int bytes);

    sealed record Index(string map, int mapId, int span, int pixels, string format, bool mips, string alpha,
        int sourceTiles, int sourcePixels, List<Cell> cells, string? sea = null, int? art = null,
        List<double[]>? tiles = null, // per tile [x, y, share of sea]: the tile table skips all-sea tiles
        List<int[]>? masks = null); // [x, y] of the coast tiles with a mask in masks/<Dir>_<x>_<y>.blp

    /// <summary>"rrggbb" -> (r, g, b); the painted sea (every cell opaque,
    /// the unrendered and the near-black water in one flat tone, so level 0 needs no zone art).</summary>
    static (byte r, byte g, byte b)? ParseSea(string? sea)
    {
        if (sea is null) return null;
        var s = sea.TrimStart('#');
        if (s.Length != 6 || !int.TryParse(s, System.Globalization.NumberStyles.HexNumber, null, out var v))
            throw new ArgumentException("--sea must be six hex digits (rrggbb)");
        return ((byte)(v >> 16), (byte)((v >> 8) & 255), (byte)(v & 255));
    }

    const double AdtYards = 1600.0 / 3; // one ADT tile; the 64 x 64 grid is centred on the world origin
    const double MaskMinSea = 0.005; // a tile with less open sea than this gets no mask (pure land)

    /// <summary>The continent's parchment (mapart_art.py: `<Dir>_art.json`): Blizzard's map art layer
    /// decoded into one RGBA image and the affine map from map fraction to world yards, so a cell pixel the
    /// minimap tiles leave empty finds its parchment texel (the inside of a cell
    /// must match the zone art the Map draws around it).</summary>
    sealed class Art
    {
        public int UiMapId, W, H;
        public double Wx0, WxDx, WxDy, Wy0, WyDx, WyDy;
        public byte[] Rgba = Array.Empty<byte>();

        public static Art? Load(Client c, string? path)
        {
            if (path is null) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            var r = doc.RootElement;
            var art = new Art
            {
                UiMapId = r.GetProperty("uiMapId").GetInt32(),
                W = r.GetProperty("layerWidth").GetInt32(),
                H = r.GetProperty("layerHeight").GetInt32(),
                Wx0 = r.GetProperty("wx0").GetDouble(), WxDx = r.GetProperty("wxDx").GetDouble(), WxDy = r.GetProperty("wxDy").GetDouble(),
                Wy0 = r.GetProperty("wy0").GetDouble(), WyDx = r.GetProperty("wyDx").GetDouble(), WyDy = r.GetProperty("wyDy").GetDouble(),
            };
            int tw = r.GetProperty("tileWidth").GetInt32(), th = r.GetProperty("tileHeight").GetInt32();
            if (art.W <= 0 || art.H <= 0 || tw <= 0 || th <= 0) throw new ArgumentException($"{path}: empty art layer");
            art.Rgba = new byte[art.W * art.H * 4];
            foreach (var t in r.GetProperty("tiles").EnumerateArray())
            {
                int row = t[0].GetInt32(), col = t[1].GetInt32();
                var fdid = t[2].GetUInt32();
                using var blp = new MemoryStream(c.ReadFdid(fdid));
                var bgra = new BLPFile(blp).GetPixels(0, out var w, out var h);
                for (var y = 0; y < h; y++)
                {
                    var ly = row * th + y;
                    if (ly >= art.H) break;
                    for (var x = 0; x < w; x++)
                    {
                        var lx = col * tw + x;
                        if (lx >= art.W) break;
                        var s = (y * w + x) * 4;
                        var d = (ly * art.W + lx) * 4;
                        art.Rgba[d] = bgra[s + 2]; art.Rgba[d + 1] = bgra[s + 1]; art.Rgba[d + 2] = bgra[s]; art.Rgba[d + 3] = 255;
                    }
                }
            }
            return art;
        }

        /// <summary>The parchment texel under a world point (bilinear), false outside the art.</summary>
        public bool Sample(double wx, double wy, out byte r, out byte g, out byte b)
        {
            r = g = b = 0;
            var det = WxDx * WyDy - WxDy * WyDx;
            if (Math.Abs(det) < 1e-9) return false;
            double dx = wx - Wx0, dy = wy - Wy0;
            var fx = (dx * WyDy - WxDy * dy) / det;
            var fy = (WxDx * dy - WyDx * dx) / det;
            if (fx < 0 || fx >= 1 || fy < 0 || fy >= 1) return false;
            double px = fx * W - 0.5, py = fy * H - 0.5;
            int x0 = (int)Math.Floor(px), y0 = (int)Math.Floor(py);
            double ax = px - x0, ay = py - y0, sumR = 0, sumG = 0, sumB = 0;
            for (var j = 0; j < 2; j++)
            for (var i = 0; i < 2; i++)
            {
                int xx = Math.Clamp(x0 + i, 0, W - 1), yy = Math.Clamp(y0 + j, 0, H - 1);
                var weight = (i == 0 ? 1 - ax : ax) * (j == 0 ? 1 - ay : ay);
                var s = (yy * W + xx) * 4;
                sumR += Rgba[s] * weight; sumG += Rgba[s + 1] * weight; sumB += Rgba[s + 2] * weight;
            }
            r = (byte)Math.Round(sumR); g = (byte)Math.Round(sumG); b = (byte)Math.Round(sumB);
            return true;
        }
    }

    public static void Run(Client c, string defsDir, string map, string outDir,
        string? wdtFdidArg, string? listfile, int pixels, int span, string format, bool mips, string alpha = "dxt1",
        string? seaArg = null, string? artPath = null)
    {
        if (alpha is not ("dxt1" or "dxt5")) throw new ArgumentException("--alpha must be dxt1 or dxt5");
        var sea = ParseSea(seaArg);
        var art = Art.Load(c, artPath);
        long parchment = 0; // cell pixels that got the parchment
        var artDump = Environment.GetEnvironmentVariable("CLIENTDUMP_ART_DUMP"); // a TGA of the assembled art, for a look
        if (art is not null && !string.IsNullOrEmpty(artDump))
            Blp.WriteTga(artDump, art.Rgba, art.W, art.H);
        if (pixels < 4 || (pixels & (pixels - 1)) != 0) throw new ArgumentException("--pixels must be a power of two, 4 or more");
        if (span < 1 || 64 % span != 0) throw new ArgumentException("--span must divide 64");
        if (format is not ("blp" or "tga")) throw new ArgumentException("--format must be blp or tga");
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture; // "3.4 MB" in every locale
        var (id, dir, tiles) = Minimap.ListTiles(c, defsDir, map, wdtFdidArg, listfile);
        Directory.CreateDirectory(outDir);
        var size = pixels * span;
        var cells = new List<Cell>();
        var sourcePixels = 0;
        var black = 0;
        long dark = 0; // output pixels of near-black water (see Blit): the sea's get parchment, lakes keep theirs
        double errorSum = 0; long errorCount = 0, alphaBad = 0;
        var started = DateTime.UtcNow;

        // pass 1: every tile decoded and box-filtered once, near-black water marked (alpha 0)
        var tileRgba = new Dictionary<(int x, int y), byte[]>();
        foreach (var t in tiles)
        {
            using var blp = new MemoryStream(c.ReadFdid(t.fdid));
            var bgra = new BLPFile(blp).GetPixels(0, out var w, out var h);
            if (sourcePixels == 0) sourcePixels = w;
            if (IsBlack(bgra)) { black++; continue; } // unrendered ocean: no tile at all
            var rgba = new byte[pixels * pixels * 4];
            dark += Blit(rgba, pixels, 0, 0, pixels, bgra, w, h);
            tileRgba[(t.x, t.y)] = rgba;
        }
        // the sea is the near-black water connected to the grid's edge or to a missing tile; enclosed
        // near-black water is a lake and keeps its colour (the continent art painted Redridge's lake
        // orange, )
        var grid = 64 * pixels;
        var seaMask = SeaMask(tileRgba, pixels, out var lakes);
        var tileSea = new List<double[]>(); // per tile [x, y, share of its pixels that are sea]
        // per coast tile a mask: white where the
        // tile stays, transparent where it is sea; the Map masks the native tile with it, so the parchment
        // cell underneath shows through the water. One texel per stitched pixel, no mips (only drawn magnified).
        var masksDir = Path.Combine(outDir, "masks");
        var masks = new List<int[]>();
        Directory.CreateDirectory(masksDir);
        foreach (var t in tiles.OrderBy(t => t.x).ThenBy(t => t.y))
        {
            if (!tileRgba.TryGetValue((t.x, t.y), out var rgba)) { tileSea.Add(new double[] { t.x, t.y, 1 }); continue; }
            var n = 0;
            var maskRgba = new byte[pixels * pixels * 4];
            for (var py = 0; py < pixels; py++)
            for (var px = 0; px < pixels; px++)
            {
                var isSea = rgba[(py * pixels + px) * 4 + 3] == 0 && seaMask[(t.y * pixels + py) * grid + t.x * pixels + px];
                if (isSea) { n++; continue; }
                var m = (py * pixels + px) * 4;
                maskRgba[m] = 255; maskRgba[m + 1] = 255; maskRgba[m + 2] = 255; maskRgba[m + 3] = 255;
            }
            var share = n / (double)(pixels * pixels);
            tileSea.Add(new double[] { t.x, t.y, Math.Round(share, 3) });
            if (share >= MaskMinSea && n < pixels * pixels)
            {
                // with the full mip chain like the cells: the Forever client did not load the
                // single-level mask (22.10.2026, /bprobe mask: the masked tile vanished, the mask was blank)
                var maskLevels = new List<(byte[] rgba, int w, int h)> { (maskRgba, pixels, pixels) };
                for (var (lr, ls) = (maskRgba, pixels); ls > 1;)
                {
                    (lr, ls) = Halve(lr, ls);
                    maskLevels.Add((lr, ls, ls));
                }
                Blp.Write(Path.Combine(masksDir, $"{dir}_{t.x}_{t.y}.blp"), maskLevels, alpha: true);
                masks.Add(new[] { t.x, t.y });
            }
        }

        // pass 2: the cells, from the cached tiles
        var groups = tileRgba.Keys.GroupBy(k => (cx: k.x / span, cy: k.y / span)).OrderBy(g => g.Key.cx).ThenBy(g => g.Key.cy);
        foreach (var g in groups)
        {
            var canvas = new byte[size * size * 4];
            var adts = 0;
            foreach (var key in g.OrderBy(k => k.x).ThenBy(k => k.y))
            {
                var rgba = tileRgba[key];
                int ox = (key.x % span) * pixels, oy = (key.y % span) * pixels;
                for (var py = 0; py < pixels; py++)
                for (var px = 0; px < pixels; px++)
                {
                    var s = (py * pixels + px) * 4;
                    var d = ((oy + py) * size + ox + px) * 4;
                    canvas[d] = rgba[s]; canvas[d + 1] = rgba[s + 1]; canvas[d + 2] = rgba[s + 2];
                    var isSea = rgba[s + 3] == 0 && seaMask[(key.y * pixels + py) * grid + key.x * pixels + px];
                    canvas[d + 3] = isSea ? (byte)0 : (byte)255;
                }
                adts++;
            }
            if (adts == 0) continue; // only black tiles in this cell
            if (art is not null)
                for (var py = 0; py < size; py++)
                for (var px = 0; px < size; px++)
                {
                    var d = (py * size + px) * 4;
                    if (canvas[d + 3] != 0) continue;
                    // the pixel's world point: column x grows east (falling wy), row y south (falling wx)
                    var wx = (32.0 - (g.Key.cy * span + (py + 0.5) / pixels)) * AdtYards;
                    var wy = (32.0 - (g.Key.cx * span + (px + 0.5) / pixels)) * AdtYards;
                    if (art.Sample(wx, wy, out var pr, out var pg, out var pb))
                    {
                        canvas[d] = pr; canvas[d + 1] = pg; canvas[d + 2] = pb; canvas[d + 3] = 255;
                        parchment++;
                    }
                }
            var holes = false;
            if (sea is { } tone)
            {
                for (var p = 0; p < canvas.Length; p += 4)
                    if (canvas[p + 3] == 0) { canvas[p] = tone.r; canvas[p + 1] = tone.g; canvas[p + 2] = tone.b; canvas[p + 3] = 255; }
            }
            else
            {
                for (var p = 3; p < canvas.Length; p += 4) if (canvas[p] == 0) { holes = true; break; }
            }
            var file = $"{dir}_{g.Key.cx}_{g.Key.cy}.{format}";
            var path = Path.Combine(outDir, file);
            int bytes;
            if (format == "blp")
            {
                var levels = new List<(byte[] rgba, int w, int h)> { (canvas, size, size) };
                if (mips)
                    for (var (rgba, s) = (canvas, size); s > 1;)
                    {
                        (rgba, s) = Halve(rgba, s);
                        levels.Add((rgba, s, s));
                    }
                var partial = sea is null && (adts < span * span || holes);
                var written = Blp.Write(path, levels, alpha: partial, dxt5: partial && alpha == "dxt5");
                bytes = written.Length;
                if (!(partial && alpha == "dxt5"))
                    SelfCheck(written, canvas, size, ref errorSum, ref errorCount, ref alphaBad);
            }
            else
            {
                Blp.WriteTga(path, canvas, size, size);
                bytes = 18 + size * size * 4;
            }
            cells.Add(new Cell(g.Key.cx, g.Key.cy, file, adts, bytes));
        }
        var index = new Index(dir, id, span, pixels, format, mips && format == "blp", alpha, tiles.Count, sourcePixels, cells,
            sea is null ? null : seaArg!.TrimStart('#').ToLowerInvariant(), art?.UiMapId, tileSea, masks);
        var json = JsonSerializer.Serialize(index, new JsonSerializerOptions { WriteIndented = true });
        var indexPath = Path.Combine(outDir, $"{dir}_overview.json");
        var tmp = indexPath + ".tmp";
        File.WriteAllText(tmp, json + "\n");
        File.Move(tmp, indexPath, true);
        var total = cells.Sum(x => (long)x.bytes);
        Console.WriteLine($"overview {dir}: {tiles.Count} ADT tiles ({sourcePixels} px, {black} black skipped, {dark} dark-water pixels of which {lakes} lakes kept, {parchment} parchment pixels{(art is null ? "" : $" from UiMap {art.UiMapId}")}, {tileSea.Count(t => t[2] >= 0.98)} all-sea tiles, {masks.Count} coast masks) -> {cells.Count} cells of {size} px, "
            + $"{total / 1024.0 / 1024.0:F1} MB, {(DateTime.UtcNow - started).TotalSeconds:F0} s -> {indexPath}");
        if (format == "blp")
            Console.WriteLine($"self-check (DXT1 decode vs. canvas): mean error {errorSum / Math.Max(1, errorCount):F2} per channel, "
                + $"{alphaBad} alpha mismatches");
    }

    /// <summary>Which pixels of the whole 64 x 64 grid (at `pixels` per ADT) are sea: near-black water (alpha 0
    /// in the cached tiles) or a missing tile, connected four-ways to the grid's edge or to a missing tile.
    /// Enclosed near-black water (lakes, dark caves) is not sea; `lakes` counts those pixels.</summary>
    static bool[] SeaMask(Dictionary<(int x, int y), byte[]> tiles, int pixels, out long lakes)
    {
        var n = 64 * pixels;
        var open = new bool[n * n];
        var sea = new bool[n * n];
        var stack = new Stack<int>();
        void Seed(int i) { if (open[i] && !sea[i]) { sea[i] = true; stack.Push(i); } }
        for (var ty = 0; ty < 64; ty++)
        for (var tx = 0; tx < 64; tx++)
        {
            tiles.TryGetValue((tx, ty), out var rgba);
            for (var py = 0; py < pixels; py++)
            for (var px = 0; px < pixels; px++)
            {
                var i = (ty * pixels + py) * n + tx * pixels + px;
                if (rgba is null) { open[i] = true; Seed(i); }
                else if (rgba[(py * pixels + px) * 4 + 3] == 0) open[i] = true;
            }
        }
        for (var i = 0; i < n; i++) { Seed(i); Seed((n - 1) * n + i); Seed(i * n); Seed(i * n + n - 1); }
        while (stack.Count > 0)
        {
            var i = stack.Pop();
            int x = i % n, y = i / n;
            if (x > 0) Seed(i - 1);
            if (x < n - 1) Seed(i + 1);
            if (y > 0) Seed(i - n);
            if (y < n - 1) Seed(i + n);
        }
        lakes = 0;
        for (var i = 0; i < open.Length; i++) if (open[i] && !sea[i]) lakes++;
        return sea;
    }

    /// <summary>Blizzard ships solid black minimap tiles for unrendered ocean (seen on Forever 21.10.2026 as
    /// black blocks on the continent map); such a tile is left transparent. Every pixel under 16 counts.</summary>
    static bool IsBlack(byte[] bgra)
    {
        for (var i = 0; i < bgra.Length; i += 4)
            if (bgra[i] > 15 || bgra[i + 1] > 15 || bgra[i + 2] > 15) return false;
        return true;
    }

    /// <summary>Deep water in Blizzard's rendered tiles is near black (south of Tanaris, Kalimdor tiles
    /// 28/52 and 36/51 decoded 21.10.2026: a black band across the continent map); an output pixel whose
    /// channels all stay at or under this stays transparent, so the zone art shows there as it does for
    /// the unrendered ocean. Land is far brighter.</summary>
    const int DarkWater = 15;

    /// <summary>Box-downsamples a BGRA tile to `pixels` square and writes it into the RGBA canvas, opaque
    /// except for near-black deep water (DarkWater). Returns the number of pixels left transparent.</summary>
    static long Blit(byte[] canvas, int size, int ox, int oy, int pixels, byte[] bgra, int w, int h)
    {
        long dark = 0;
        for (var y = 0; y < pixels; y++)
        for (var x = 0; x < pixels; x++)
        {
            int x1 = x * w / pixels, x2 = Math.Max(x1 + 1, (x + 1) * w / pixels);
            int y1 = y * h / pixels, y2 = Math.Max(y1 + 1, (y + 1) * h / pixels);
            long r = 0, g = 0, b = 0, n = 0;
            for (var sy = y1; sy < y2 && sy < h; sy++)
            for (var sx = x1; sx < x2 && sx < w; sx++)
            {
                var s = (sy * w + sx) * 4;
                b += bgra[s]; g += bgra[s + 1]; r += bgra[s + 2]; n++;
            }
            if (n == 0) continue;
            var d = ((oy + y) * size + ox + x) * 4;
            canvas[d] = (byte)(r / n); canvas[d + 1] = (byte)(g / n); canvas[d + 2] = (byte)(b / n);
            if (r / n <= DarkWater && g / n <= DarkWater && b / n <= DarkWater) { dark++; continue; }
            canvas[d + 3] = 255;
        }
        return dark;
    }

    /// <summary>The next mip: 2x2 box over the opaque children only (no dark fringes), opaque if any child is.</summary>
    static (byte[] rgba, int size) Halve(byte[] rgba, int size)
    {
        var half = size / 2;
        var output = new byte[half * half * 4];
        for (var y = 0; y < half; y++)
        for (var x = 0; x < half; x++)
        {
            int r = 0, g = 0, b = 0, n = 0;
            for (var dy = 0; dy < 2; dy++)
            for (var dx = 0; dx < 2; dx++)
            {
                var s = ((y * 2 + dy) * size + x * 2 + dx) * 4;
                if (rgba[s + 3] < 128) continue;
                r += rgba[s]; g += rgba[s + 1]; b += rgba[s + 2]; n++;
            }
            if (n == 0) continue;
            var d = (y * half + x) * 4;
            output[d] = (byte)(r / n); output[d + 1] = (byte)(g / n); output[d + 2] = (byte)(b / n); output[d + 3] = 255;
        }
        return (output, half);
    }

    /// <summary>Decodes mip 0 of the written BLP with our decoder and with BLPSharp; accumulates the error.</summary>
    static void SelfCheck(byte[] blp, byte[] canvas, int size, ref double errorSum, ref long errorCount, ref long alphaBad)
    {
        var mip0 = blp.AsSpan(Blp.HeaderSize, size * size / 2).ToArray();
        var ours = Dxt1.Decode(mip0, size, size);
        using var stream = new MemoryStream(blp);
        var theirs = new BLPFile(stream).GetPixels(0, out var w, out var h); // BGRA
        if (w != size || h != size) throw new InvalidOperationException($"BLPSharp read {w}x{h}, expected {size}");
        for (var i = 0; i < size * size; i++)
        {
            var opaque = canvas[i * 4 + 3] >= 128;
            if (opaque != (ours[i * 4 + 3] >= 128) || opaque != (theirs[i * 4 + 3] >= 128)) alphaBad++;
            if (!opaque) continue;
            for (var k = 0; k < 3; k++)
            {
                errorSum += Math.Abs(canvas[i * 4 + k] - ours[i * 4 + k]);
                errorSum += Math.Abs(canvas[i * 4 + k] - theirs[i * 4 + 2 - k]);
                errorCount += 2;
            }
        }
    }
}
