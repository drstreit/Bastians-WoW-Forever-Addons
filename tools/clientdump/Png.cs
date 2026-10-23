// Minimal PNG writer (RGBA, 8 bit, no filter) so the tool needs no image library.
using System.IO.Compression;

namespace ClientDump;

static class Png
{
    public static void Write(string path, byte[] bgra, int w, int h)
    {
        var raw = new byte[h * (1 + w * 4)];
        for (var y = 0; y < h; y++)
        {
            var o = y * (1 + w * 4);
            for (var x = 0; x < w; x++)
            {
                var s = (y * w + x) * 4;
                raw[o + 1 + x * 4] = bgra[s + 2];
                raw[o + 2 + x * 4] = bgra[s + 1];
                raw[o + 3 + x * 4] = bgra[s];
                raw[o + 4 + x * 4] = bgra[s + 3];
            }
        }
        using var z = new MemoryStream();
        using (var zs = new ZLibStream(z, CompressionLevel.Optimal, true)) zs.Write(raw);

        var ihdr = new byte[13];
        Be(ihdr, 0, (uint)w); Be(ihdr, 4, (uint)h);
        ihdr[8] = 8; ihdr[9] = 6; // 8 bit RGBA

        var tmp = path + ".tmp";
        using (var fs = File.Create(tmp))
        {
            fs.Write([0x89, (byte)'P', (byte)'N', (byte)'G', 0x0D, 0x0A, 0x1A, 0x0A]);
            Chunk(fs, "IHDR", ihdr);
            Chunk(fs, "IDAT", z.ToArray());
            Chunk(fs, "IEND", []);
        }
        File.Move(tmp, path, true);
    }

    static void Chunk(Stream s, string type, byte[] data)
    {
        var len = new byte[4]; Be(len, 0, (uint)data.Length);
        var t = System.Text.Encoding.ASCII.GetBytes(type);
        var crc = new byte[4];
        Be(crc, 0, ~Update(Update(0xFFFFFFFF, t), data));
        s.Write(len); s.Write(t); s.Write(data); s.Write(crc);
    }

    static uint Update(uint c, byte[] data)
    {
        foreach (var b in data)
        {
            c ^= b;
            for (var k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
        }
        return c;
    }

    static void Be(byte[] b, int o, uint v)
    {
        b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v;
    }
}
