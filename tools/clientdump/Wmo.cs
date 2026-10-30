// Collision geometry of WMOs (buildings, cities, caves, bridges) and M2 doodads for the navmesh (ADR 0026). Model
// space as stored: z up, yards. Formats (wowdev.wiki, cross-checked with TrinityCore's vmap4extractor):
//   WMO root: MOHD (group count at 4, bounding box at 36, flags at 60), GFID (group FileDataIDs, lod 0 first),
//     MODS (doodad sets, 32 bytes: name[20], first, count), MODI (doodad FileDataIDs) or MODN (names),
//     MODD (40 bytes: name index 24 bits, position, quaternion x y z w, scale).
//   WMO group: MOGP header (0x44 bytes: flags at 8, liquid type at 0x34), then MOPY (flags, material per
//     triangle; MPY2 since 10.x: u16 flags, u16 material), MOVI (u16 indices) or MOVX (u32), MOVT
//     (vertices), MLIQ (liquid grid).
//     Collision per triangle as TrinityCore: F_COLLISION (0x08), or a render face (F_RENDER 0x20 without
//     F_DETAIL 0x04). Groups flagged unreachable (0x80) or antiportal (0x4000000) are skipped. Indoor = 0x2000.
//   M2: MD21 chunk holding the MD20 header (or a bare MD20 file); collision indices (u16) at 0xD8 and
//     collision vertices at 0xE0 (M2Array count, offset from the MD20 start).
using System.Numerics;

namespace ClientDump;

sealed class ModelMesh
{
    public float[] Verts = [];   // x, y, z per vertex, model space
    public int[] Tris = [];      // 3 indices per triangle
    public byte[] TriFlags = []; // bit 0: indoor
    public Vector3 Min, Max;     // bounds of Verts
    public void Bounds()
    {
        Min = new Vector3(float.MaxValue); Max = new Vector3(float.MinValue);
        for (var i = 0; i + 2 < Verts.Length; i += 3)
        {
            var v = new Vector3(Verts[i], Verts[i + 1], Verts[i + 2]);
            Min = Vector3.Min(Min, v); Max = Vector3.Max(Max, v);
        }
    }
}

readonly record struct WmoDoodad(uint Fdid, Vector3 Pos, Quaternion Rot, float Scale);

sealed class WmoModel
{
    public ModelMesh Mesh = new();
    public List<(Vector3 a, Vector3 b, Vector3 c, int type)> Liquids = []; // model space
    public List<WmoDoodad> Doodads = [];
    public List<(int first, int count)> Sets = [];
    public Vector3 BoxMin, BoxMax; // MOHD
    public int Groups, GroupsRead, GroupsSkipped, IndoorGroups, UnnamedDoodads;
    public string? Error;
}

static class Wmo
{
    public static WmoModel Read(Func<uint, byte[]?> read, uint fdid, Func<uint, int> liquidType)
    {
        var m = new WmoModel();
        var b = read(fdid);
        if (b == null) { m.Error = "root missing"; return m; }
        var gfid = new List<uint>();
        var modi = new List<uint>();
        byte[]? modn = null;
        uint rootFlags = 0;
        var modd = new List<(int name, Vector3 pos, Quaternion q, float scale)>();
        foreach (var (magic, s, n) in Terrain.Chunks(b, 0, b.Length))
        {
            switch (magic)
            {
                case "MOHD":
                    m.Groups = BitConverter.ToInt32(b, s + 4);
                    m.BoxMin = Adt.V3(b, s + 36); m.BoxMax = Adt.V3(b, s + 48);
                    rootFlags = BitConverter.ToUInt16(b, s + 60);
                    break;
                case "GFID": for (var i = 0; i + 4 <= n; i += 4) gfid.Add(BitConverter.ToUInt32(b, s + i)); break;
                case "MODI": for (var i = 0; i + 4 <= n; i += 4) modi.Add(BitConverter.ToUInt32(b, s + i)); break;
                case "MODN": modn = b[s..(s + n)]; break;
                case "MODS":
                    for (var o = s; o + 32 <= s + n; o += 32)
                        m.Sets.Add((BitConverter.ToInt32(b, o + 20), BitConverter.ToInt32(b, o + 24)));
                    break;
                case "MODD":
                    for (var o = s; o + 40 <= s + n; o += 40)
                        modd.Add(((int)(BitConverter.ToUInt32(b, o) & 0xFFFFFF), Adt.V3(b, o + 4),
                            new Quaternion(BitConverter.ToSingle(b, o + 16), BitConverter.ToSingle(b, o + 20),
                                BitConverter.ToSingle(b, o + 24), BitConverter.ToSingle(b, o + 28)),
                            BitConverter.ToSingle(b, o + 32)));
                    break;
            }
        }
        foreach (var d in modd)
        {
            // MODI replaces MODN since 8.1: the name index is then an index into MODI
            uint dfdid = modi.Count > 0 ? (d.name < modi.Count ? modi[d.name] : 0) : 0;
            if (dfdid == 0) m.UnnamedDoodads++;
            m.Doodads.Add(new WmoDoodad(dfdid, d.pos, d.q, d.scale));
        }
        if (gfid.Count == 0 && m.Groups > 0) { m.Error = "no GFID (groups by name are not read)"; return m; }

        var verts = new List<float>();
        var tris = new List<int>();
        var tflags = new List<byte>();
        for (var g = 0; g < Math.Min(m.Groups, gfid.Count); g++)
        {
            var gb = gfid[g] == 0 ? null : read(gfid[g]);
            if (gb == null) { m.GroupsSkipped++; continue; }
            ReadGroup(gb, m, verts, tris, tflags, rootFlags, liquidType);
        }
        m.Mesh.Verts = verts.ToArray();
        m.Mesh.Tris = tris.ToArray();
        m.Mesh.TriFlags = tflags.ToArray();
        m.Mesh.Bounds();
        return m;
    }

    static void ReadGroup(byte[] b, WmoModel m, List<float> verts, List<int> tris, List<byte> tflags, uint rootFlags,
        Func<uint, int> liquidType)
    {
        foreach (var (magic, s, n) in Terrain.Chunks(b, 0, b.Length))
        {
            if (magic != "MOGP") continue;
            var flags = BitConverter.ToUInt32(b, s + 8);
            if ((flags & 0x80) != 0 || (flags & 0x4000000) != 0) { m.GroupsSkipped++; return; }
            var groupLiquid = BitConverter.ToUInt32(b, s + 0x34);
            var indoor = (flags & 0x2000) != 0;
            if (indoor) m.IndoorGroups++;
            byte[]? mopy = null;
            int[]? idx = null;
            float[]? v = null;
            (int s, int n)? mliq = null;
            foreach (var (sm, ss, sn) in Terrain.Chunks(b, s + 0x44, s + n))
            {
                switch (sm)
                {
                    case "MOPY": mopy = b[ss..(ss + sn)]; break;
                    case "MPY2": // since 10.x: u16 flags, u16 material per triangle; the flag bits are MOPY's
                        mopy = new byte[sn / 2];
                        for (var i = 0; i + 1 < mopy.Length; i += 2) { mopy[i] = b[ss + i * 2]; mopy[i + 1] = b[ss + i * 2 + 2]; }
                        break;
                    case "MOVI":
                        idx = new int[sn / 2];
                        for (var i = 0; i < idx.Length; i++) idx[i] = BitConverter.ToUInt16(b, ss + i * 2);
                        break;
                    case "MOVX":
                        idx = new int[sn / 4];
                        for (var i = 0; i < idx.Length; i++) idx[i] = BitConverter.ToInt32(b, ss + i * 4);
                        break;
                    case "MOVT":
                        v = new float[sn / 4];
                        for (var i = 0; i < v.Length; i++) v[i] = BitConverter.ToSingle(b, ss + i * 4);
                        break;
                    case "MLIQ": mliq = (ss, sn); break;
                }
            }
            m.GroupsRead++;
            if (mliq is { } lq) ReadLiquid(b, lq.s, lq.n, m, flags, groupLiquid, rootFlags, liquidType);
            if (idx == null || v == null || mopy == null) return;
            var nv = v.Length / 3;
            var baseIndex = verts.Count / 3;
            verts.AddRange(v);
            for (var t = 0; t < idx.Length / 3 && t * 2 + 1 < mopy.Length; t++)
            {
                var f = mopy[t * 2];
                var render = (f & 0x20) != 0 && (f & 0x04) == 0;
                if ((f & 0x08) == 0 && !render) continue;
                int a = idx[t * 3], c = idx[t * 3 + 1], d = idx[t * 3 + 2];
                if (a >= nv || c >= nv || d >= nv) continue;
                tris.Add(baseIndex + a); tris.Add(baseIndex + c); tris.Add(baseIndex + d);
                tflags.Add((byte)(indoor ? 1 : 0));
            }
            return;
        }
    }

    /// <summary>MLIQ: xverts, yverts, xtiles, ytiles (i32), corner (C3Vector), material (u16) = 30 bytes; then
    /// xverts * yverts vertices of 8 bytes (4 bytes flow or uv, float height); then a byte per tile (low nibble
    /// 0x0F = no liquid). A liquid tile is 4.1667 yards. The type follows TrinityCore's WMOGroup: the root flag
    /// 0x4 means the group's liquid field is a LiquidType id, else it is the legacy kind + 1 (15 = none).</summary>
    static void ReadLiquid(byte[] b, int s, int n, WmoModel m, uint groupFlags, uint groupLiquid, uint rootFlags,
        Func<uint, int> liquidType)
    {
        if (n < 30) return;
        int xv = BitConverter.ToInt32(b, s), yv = BitConverter.ToInt32(b, s + 4);
        int xt = BitConverter.ToInt32(b, s + 8), yt = BitConverter.ToInt32(b, s + 12);
        var corner = Adt.V3(b, s + 16);
        if (xv <= 1 || yv <= 1 || 30 + xv * yv * 8 + xt * yt > n) return;
        var heights = new float[xv * yv];
        for (var i = 0; i < heights.Length; i++) heights[i] = BitConverter.ToSingle(b, s + 30 + i * 8 + 4);
        var tiles = s + 30 + xv * yv * 8;
        uint type;
        if ((rootFlags & 0x4) != 0) type = Legacy(groupLiquid, groupFlags);
        else if (groupLiquid == 15) type = 0;
        else type = Legacy(groupLiquid + 1, groupFlags);
        var u = (float)Frame.Unit;
        for (var j = 0; j < yt; j++)
        for (var i = 0; i < xt; i++)
        {
            var tf = b[tiles + j * xt + i];
            if ((tf & 0x0F) == 0x0F) continue;
            var t = type != 0 ? type : Legacy((uint)(tf & 0x0F) + 1, groupFlags);
            Vector3 P(int x, int y) => new(corner.X + x * u, corner.Y + y * u, heights[y * xv + x]);
            var lt = liquidType(t);
            m.Liquids.Add((P(i, j), P(i + 1, j), P(i + 1, j + 1), lt));
            m.Liquids.Add((P(i, j), P(i + 1, j + 1), P(i, j + 1), lt));
        }
    }

    /// <summary>TrinityCore WMOGroup::GetLiquidTypeId: the legacy kinds 1..20 map to the WMO liquid types 13
    /// (water; 14 when the group flag 0x80000 says ocean), 14 (ocean), 19 (magma), 20 (slime).</summary>
    static uint Legacy(uint id, uint groupFlags)
    {
        if (id is 0 or >= 21) return id;
        return ((id - 1) & 3) switch
        {
            0 => (groupFlags & 0x80000) != 0 ? 14u : 13u,
            1 => 14,
            2 => 19,
            _ => 20,
        };
    }
}

static class M2
{
    /// <summary>The collision mesh of an M2; empty when it has none (grass, most small props). Null when the file
    /// is missing or not an M2.</summary>
    public static ModelMesh? Read(byte[]? b)
    {
        if (b == null || b.Length < 0x100) return null;
        var md20 = -1;
        var end = b.Length;
        if (b[0] == 'M' && b[1] == 'D' && b[2] == '2' && b[3] == '0') md20 = 0;
        else // M2 chunk ids are stored in reading order ("MD21"), unlike ADT and WMO ids
            for (var p = 0; p + 8 <= b.Length;)
            {
                var size = BitConverter.ToInt32(b, p + 4);
                if (size < 0 || p + 8 + size > b.Length) break;
                if (b[p] == 'M' && b[p + 1] == 'D' && b[p + 2] == '2' && b[p + 3] == '1') { md20 = p + 8; end = p + 8 + size; break; }
                p += 8 + size;
            }
        if (md20 < 0 || end - md20 < 0xE8) return null;
        int nIdx = BitConverter.ToInt32(b, md20 + 0xD8), oIdx = BitConverter.ToInt32(b, md20 + 0xDC);
        int nV = BitConverter.ToInt32(b, md20 + 0xE0), oV = BitConverter.ToInt32(b, md20 + 0xE4);
        var mesh = new ModelMesh();
        if (nIdx <= 0 || nV <= 0 || md20 + oIdx + nIdx * 2 > end || md20 + oV + nV * 12 > end || nIdx % 3 != 0)
            return mesh;
        mesh.Verts = new float[nV * 3];
        for (var i = 0; i < mesh.Verts.Length; i++) mesh.Verts[i] = BitConverter.ToSingle(b, md20 + oV + i * 4);
        var tris = new List<int>(nIdx);
        for (var i = 0; i < nIdx; i += 3)
        {
            int a = BitConverter.ToUInt16(b, md20 + oIdx + i * 2), c = BitConverter.ToUInt16(b, md20 + oIdx + i * 2 + 2),
                d = BitConverter.ToUInt16(b, md20 + oIdx + i * 2 + 4);
            if (a >= nV || c >= nV || d >= nV) continue;
            tris.Add(a); tris.Add(c); tris.Add(d);
        }
        mesh.Tris = tris.ToArray();
        mesh.TriFlags = new byte[mesh.Tris.Length / 3];
        mesh.Bounds();
        return mesh;
    }
}
