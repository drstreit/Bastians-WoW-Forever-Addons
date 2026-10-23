// DXT1 (BC1) block encoder with 1-bit alpha for the overview textures (map.md "Imagery pipeline").
// Per 4x4 block: the principal axis of the opaque pixels gives the first endpoints, rounds of index
// assignment and least-squares refinement improve them (the stb_dxt approach). A block with a
// transparent pixel uses the three-colour mode (c0 <= c1, index 3 = transparent), otherwise the
// four-colour mode (c0 > c1). Deterministic: integer and double math in a fixed order, no randomness.
namespace ClientDump;

static class Dxt1
{
    /// <summary>Encodes RGBA (row-major, 4 bytes per pixel) into BC1 blocks; sizes below 4 are padded.</summary>
    public static byte[] Encode(byte[] rgba, int width, int height)
    {
        var bw = Math.Max(1, (width + 3) / 4);
        var bh = Math.Max(1, (height + 3) / 4);
        var output = new byte[bw * bh * 8];
        var block = new int[16 * 4]; // r, g, b, a per pixel
        for (var by = 0; by < bh; by++)
        for (var bx = 0; bx < bw; bx++)
        {
            for (var py = 0; py < 4; py++)
            for (var px = 0; px < 4; px++)
            {
                var x = Math.Min(bx * 4 + px, width - 1);
                var y = Math.Min(by * 4 + py, height - 1);
                var s = (y * width + x) * 4;
                var d = (py * 4 + px) * 4;
                block[d] = rgba[s]; block[d + 1] = rgba[s + 1]; block[d + 2] = rgba[s + 2]; block[d + 3] = rgba[s + 3];
            }
            EncodeBlock(block, output, (by * bw + bx) * 8);
        }
        return output;
    }

    /// <summary>Encodes RGBA into BC3 (DXT5) blocks: an 8-byte alpha block (a0 = 255, a1 = 0, 3-bit
    /// indices 0 = opaque, 1 = transparent) in front of the BC1 colour block of the same pixels.</summary>
    public static byte[] EncodeDxt5(byte[] rgba, int width, int height)
    {
        var colour = Encode(rgba, width, height);
        var bw = Math.Max(1, (width + 3) / 4);
        var bh = Math.Max(1, (height + 3) / 4);
        var output = new byte[bw * bh * 16];
        for (var by = 0; by < bh; by++)
        for (var bx = 0; bx < bw; bx++)
        {
            var o = (by * bw + bx) * 16;
            output[o] = 255; // a0
            output[o + 1] = 0; // a1: a0 > a1, so indices 0 and 1 are the endpoints
            ulong bits = 0;
            for (var i = 0; i < 16; i++)
            {
                var x = Math.Min(bx * 4 + i % 4, width - 1);
                var y = Math.Min(by * 4 + i / 4, height - 1);
                var transparent = rgba[(y * width + x) * 4 + 3] < 128;
                if (transparent) bits |= 1UL << (i * 3);
            }
            for (var k = 0; k < 6; k++) output[o + 2 + k] = (byte)(bits >> (k * 8));
            Array.Copy(colour, (by * bw + bx) * 8, output, o + 8, 8);
        }
        return output;
    }

    /// <summary>Decodes BC1 blocks back to RGBA (for the self-check after writing).</summary>
    public static byte[] Decode(byte[] blocks, int width, int height)
    {
        var bw = Math.Max(1, (width + 3) / 4);
        var bh = Math.Max(1, (height + 3) / 4);
        var rgba = new byte[width * height * 4];
        var p = new int[12];
        for (var by = 0; by < bh; by++)
        for (var bx = 0; bx < bw; bx++)
        {
            var o = (by * bw + bx) * 8;
            int c0 = blocks[o] | (blocks[o + 1] << 8), c1 = blocks[o + 2] | (blocks[o + 3] << 8);
            var three = c0 <= c1;
            Palette(c0, c1, three, p);
            uint bits = (uint)(blocks[o + 4] | (blocks[o + 5] << 8) | (blocks[o + 6] << 16) | (blocks[o + 7] << 24));
            for (var i = 0; i < 16; i++)
            {
                int x = bx * 4 + i % 4, y = by * 4 + i / 4;
                if (x >= width || y >= height) continue;
                var idx = (int)((bits >> (i * 2)) & 3);
                var d = (y * width + x) * 4;
                if (three && idx == 3) { rgba[d] = rgba[d + 1] = rgba[d + 2] = 0; rgba[d + 3] = 0; continue; }
                rgba[d] = (byte)p[idx * 3]; rgba[d + 1] = (byte)p[idx * 3 + 1]; rgba[d + 2] = (byte)p[idx * 3 + 2]; rgba[d + 3] = 255;
            }
        }
        return rgba;
    }

    static void EncodeBlock(int[] px, byte[] output, int offset)
    {
        var opaque = new bool[16];
        var count = 0;
        for (var i = 0; i < 16; i++)
        {
            opaque[i] = px[i * 4 + 3] >= 128;
            if (opaque[i]) count++;
        }
        if (count == 0)
        {
            // all transparent: c0 = c1 = 0, every index 3
            output[offset] = 0; output[offset + 1] = 0; output[offset + 2] = 0; output[offset + 3] = 0;
            output[offset + 4] = 0xFF; output[offset + 5] = 0xFF; output[offset + 6] = 0xFF; output[offset + 7] = 0xFF;
            return;
        }
        var threeColour = count < 16;

        // principal axis through the opaque pixels
        double mr = 0, mg = 0, mb = 0;
        for (var i = 0; i < 16; i++)
            if (opaque[i]) { mr += px[i * 4]; mg += px[i * 4 + 1]; mb += px[i * 4 + 2]; }
        mr /= count; mg /= count; mb /= count;
        double crr = 0, crg = 0, crb = 0, cgg = 0, cgb = 0, cbb = 0;
        for (var i = 0; i < 16; i++)
        {
            if (!opaque[i]) continue;
            double r = px[i * 4] - mr, g = px[i * 4 + 1] - mg, b = px[i * 4 + 2] - mb;
            crr += r * r; crg += r * g; crb += r * b; cgg += g * g; cgb += g * b; cbb += b * b;
        }
        double ax = 1, ay = 1, az = 1;
        for (var k = 0; k < 8; k++)
        {
            double nx = crr * ax + crg * ay + crb * az;
            double ny = crg * ax + cgg * ay + cgb * az;
            double nz = crb * ax + cgb * ay + cbb * az;
            var len = Math.Sqrt(nx * nx + ny * ny + nz * nz);
            if (len < 1e-9) break;
            ax = nx / len; ay = ny / len; az = nz / len;
        }
        double lo = 0, hi = 0;
        int loIdx = -1, hiIdx = -1;
        for (var i = 0; i < 16; i++)
        {
            if (!opaque[i]) continue;
            var t = (px[i * 4] - mr) * ax + (px[i * 4 + 1] - mg) * ay + (px[i * 4 + 2] - mb) * az;
            if (loIdx < 0 || t < lo) { lo = t; loIdx = i; }
            if (hiIdx < 0 || t > hi) { hi = t; hiIdx = i; }
        }
        var c0 = Pack565(px[loIdx * 4], px[loIdx * 4 + 1], px[loIdx * 4 + 2]);
        var c1 = Pack565(px[hiIdx * 4], px[hiIdx * 4 + 1], px[hiIdx * 4 + 2]);

        var indices = new int[16];
        var palette = new int[4 * 3];
        for (var round = 0; round < 3; round++)
        {
            Palette(c0, c1, threeColour, palette);
            Assign(px, opaque, palette, threeColour, indices);
            if (round == 2) break;
            if (!Refine(px, opaque, indices, threeColour, out var n0, out var n1)) break;
            if (n0 == c0 && n1 == c1) break;
            c0 = n0; c1 = n1;
        }
        // the mode is given by the endpoint order
        if (threeColour)
        {
            if (c0 > c1) (c0, c1) = (c1, c0);
        }
        else if (c0 < c1)
        {
            (c0, c1) = (c1, c0);
        }
        var three = threeColour || c0 == c1; // equal endpoints are the three-colour mode by definition
        Palette(c0, c1, three, palette);
        Assign(px, opaque, palette, three, indices);

        output[offset] = (byte)c0; output[offset + 1] = (byte)(c0 >> 8);
        output[offset + 2] = (byte)c1; output[offset + 3] = (byte)(c1 >> 8);
        uint bits = 0;
        for (var i = 0; i < 16; i++) bits |= (uint)indices[i] << (i * 2);
        output[offset + 4] = (byte)bits; output[offset + 5] = (byte)(bits >> 8);
        output[offset + 6] = (byte)(bits >> 16); output[offset + 7] = (byte)(bits >> 24);
    }

    static int Pack565(int r, int g, int b) => ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);

    static void Unpack565(int c, out int r, out int g, out int b)
    {
        r = (c >> 11) & 31; g = (c >> 5) & 63; b = c & 31;
        r = (r << 3) | (r >> 2); g = (g << 2) | (g >> 4); b = (b << 3) | (b >> 2);
    }

    static void Palette(int c0, int c1, bool three, int[] p)
    {
        Unpack565(c0, out p[0], out p[1], out p[2]);
        Unpack565(c1, out p[3], out p[4], out p[5]);
        if (three)
        {
            for (var k = 0; k < 3; k++) { p[6 + k] = (p[k] + p[3 + k]) / 2; p[9 + k] = 0; }
        }
        else
        {
            for (var k = 0; k < 3; k++)
            {
                p[6 + k] = (2 * p[k] + p[3 + k]) / 3;
                p[9 + k] = (p[k] + 2 * p[3 + k]) / 3;
            }
        }
    }

    static void Assign(int[] px, bool[] opaque, int[] p, bool three, int[] indices)
    {
        var n = three ? 3 : 4;
        for (var i = 0; i < 16; i++)
        {
            if (!opaque[i]) { indices[i] = 3; continue; }
            int best = 0, bestErr = int.MaxValue;
            for (var k = 0; k < n; k++)
            {
                int dr = px[i * 4] - p[k * 3], dg = px[i * 4 + 1] - p[k * 3 + 1], db = px[i * 4 + 2] - p[k * 3 + 2];
                var err = dr * dr + dg * dg + db * db;
                if (err < bestErr) { bestErr = err; best = k; }
            }
            indices[i] = best;
        }
    }

    /// <summary>Least-squares endpoints for the current indices (colour(i) = a*c0 + b*c1).</summary>
    static bool Refine(int[] px, bool[] opaque, int[] indices, bool three, out int c0, out int c1)
    {
        double saa = 0, sab = 0, sbb = 0;
        double[] sap = new double[3], sbp = new double[3];
        for (var i = 0; i < 16; i++)
        {
            if (!opaque[i]) continue;
            double a, b;
            switch (indices[i])
            {
                case 0: a = 1; b = 0; break;
                case 1: a = 0; b = 1; break;
                case 2: if (three) { a = 0.5; b = 0.5; } else { a = 2.0 / 3; b = 1.0 / 3; } break;
                default: a = 1.0 / 3; b = 2.0 / 3; break;
            }
            saa += a * a; sab += a * b; sbb += b * b;
            for (var k = 0; k < 3; k++) { sap[k] += a * px[i * 4 + k]; sbp[k] += b * px[i * 4 + k]; }
        }
        var det = saa * sbb - sab * sab;
        c0 = c1 = 0;
        if (Math.Abs(det) < 1e-9) return false;
        var e0 = new int[3]; var e1 = new int[3];
        for (var k = 0; k < 3; k++)
        {
            var v0 = (sbb * sap[k] - sab * sbp[k]) / det;
            var v1 = (saa * sbp[k] - sab * sap[k]) / det;
            e0[k] = (int)Math.Clamp(Math.Round(v0), 0, 255);
            e1[k] = (int)Math.Clamp(Math.Round(v1), 0, 255);
        }
        c0 = Pack565(e0[0], e0[1], e0[2]);
        c1 = Pack565(e1[0], e1[1], e1[2]);
        return true;
    }
}
