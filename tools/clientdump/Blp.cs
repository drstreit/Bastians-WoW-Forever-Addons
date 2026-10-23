// BLP2 writer (DXT1 payload, optional mip chain) and a 32-bit TGA writer for the overview textures.
// Layout from the wowdev wiki (BLP): 'BLP2', type 1, encoding 2 = DXT, alphaDepth 0 | 1, alphaEncoding
// 0 = DXT1, hasMips, width, height, 16 mip offsets, 16 mip sizes, a 256-entry palette (unused, zero).
// The header is 1172 bytes; the mips follow it in order. Files are written to a temp name, then moved.
namespace ClientDump;

static class Blp
{
    public const int HeaderSize = 1172;

    /// <summary>Writes the RGBA image and its smaller mips (largest first) as DXT1 BLP2, or as DXT5 with an
    /// 8-bit alpha channel when `dxt5` is set (twice the bytes); returns the bytes.</summary>
    public static byte[] Write(string path, IReadOnlyList<(byte[] rgba, int w, int h)> levels, bool alpha, bool dxt5 = false)
    {
        if (levels.Count == 0 || levels.Count > 16) throw new ArgumentException("1..16 mip levels");
        var payloads = levels.Select(l => dxt5 ? Dxt1.EncodeDxt5(l.rgba, l.w, l.h) : Dxt1.Encode(l.rgba, l.w, l.h)).ToList();
        var header = new byte[HeaderSize];
        header[0] = (byte)'B'; header[1] = (byte)'L'; header[2] = (byte)'P'; header[3] = (byte)'2';
        Le(header, 4, 1);                  // type: 1 = not JPEG
        header[8] = 2;                     // encoding: DXT
        header[9] = (byte)(dxt5 ? 8 : alpha ? 1 : 0); // alphaDepth
        header[10] = (byte)(dxt5 ? 7 : 0);            // alphaEncoding: 0 = DXT1, 7 = DXT5
        header[11] = (byte)(levels.Count > 1 ? 1 : 0); // hasMips
        Le(header, 12, (uint)levels[0].w);
        Le(header, 16, (uint)levels[0].h);
        var offset = (uint)HeaderSize;
        for (var i = 0; i < payloads.Count; i++)
        {
            Le(header, 20 + i * 4, offset);
            Le(header, 84 + i * 4, (uint)payloads[i].Length);
            offset += (uint)payloads[i].Length;
        }
        var all = new byte[offset];
        header.CopyTo(all, 0);
        var at = HeaderSize;
        foreach (var p in payloads) { p.CopyTo(all, at); at += p.Length; }
        WriteAtomic(path, all);
        return all;
    }

    /// <summary>Uncompressed 32-bit TGA, bottom-left origin (the common layout), no mips.</summary>
    public static void WriteTga(string path, byte[] rgba, int w, int h)
    {
        var all = new byte[18 + w * h * 4];
        all[2] = 2; // uncompressed true colour
        all[12] = (byte)w; all[13] = (byte)(w >> 8);
        all[14] = (byte)h; all[15] = (byte)(h >> 8);
        all[16] = 32;
        all[17] = 8; // 8 alpha bits, bottom-left origin
        for (var y = 0; y < h; y++)
        {
            var src = (h - 1 - y) * w * 4;
            var dst = 18 + y * w * 4;
            for (var x = 0; x < w; x++)
            {
                all[dst + x * 4] = rgba[src + x * 4 + 2];
                all[dst + x * 4 + 1] = rgba[src + x * 4 + 1];
                all[dst + x * 4 + 2] = rgba[src + x * 4];
                all[dst + x * 4 + 3] = rgba[src + x * 4 + 3];
            }
        }
        WriteAtomic(path, all);
    }

    static void WriteAtomic(string path, byte[] bytes)
    {
        if (File.Exists(path) && File.ReadAllBytes(path).AsSpan().SequenceEqual(bytes)) return;
        var tmp = path + ".tmp";
        File.WriteAllBytes(tmp, bytes);
        File.Move(tmp, path, true);
    }

    static void Le(byte[] b, int o, uint v)
    {
        b[o] = (byte)v; b[o + 1] = (byte)(v >> 8); b[o + 2] = (byte)(v >> 16); b[o + 3] = (byte)(v >> 24);
    }
}
