// The Bastian map's cells as game textures (ADR 0027): every raw RGBA file tools/mapstyle wrote ("RGBA", u32 width,
// u32 height, then the pixels; square, a power of two) becomes a BLP2 with DXT1 and its full mip chain beside it, by
// the encoder of the overview cells (Overview.cs, Dxt1.cs, Blp.cs). The cells are opaque (the sea is drawn).
namespace ClientDump;

static class BlpCells
{
    public static void Run(string dir, int threads)
    {
        var files = Directory.GetFiles(dir, "*.rgba", SearchOption.AllDirectories).Order().ToArray();
        long bytes = 0;
        Parallel.ForEach(files, new ParallelOptions { MaxDegreeOfParallelism = threads }, f =>
        {
            var raw = File.ReadAllBytes(f);
            if (raw.Length < 12 || raw[0] != 'R' || raw[1] != 'G' || raw[2] != 'B' || raw[3] != 'A')
                throw new InvalidDataException($"{f}: not an RGBA cell");
            int w = BitConverter.ToInt32(raw, 4), h = BitConverter.ToInt32(raw, 8);
            if (w != h || (w & (w - 1)) != 0) throw new InvalidDataException($"{f}: {w} x {h} is not a square power of two");
            var rgba = raw[12..];
            var levels = new List<(byte[] rgba, int w, int h)> { (rgba, w, w) };
            for (var (px, s) = (rgba, w); s > 1;)
            {
                (px, s) = Overview.Halve(px, s);
                levels.Add((px, s, s));
            }
            var written = Blp.Write(Path.ChangeExtension(f, ".blp"), levels, alpha: false);
            Interlocked.Add(ref bytes, written.Length);
        });
        Console.WriteLine($"blp: {files.Length} cells, {bytes / 1048576.0:0.0} MB");
    }
}
