// The client's hotfix cache (DBCache.bin) and its decryption keys, applied the way ADR 0039 decides.
using System.Security.Cryptography;
using DBCD;
using DBCD.IO;
using TACTSharp;

namespace ClientDump;

/// <summary>What a DBCache.bin holds, read without decoding rows: refuses a file that does not parse to its end
/// (the game may be writing it).</summary>
sealed record HotfixCacheInfo(string Path, int Version, int Build, int Entries, int HighestPush, string Sha256)
{
    const int HeaderSize = 44; // magic, version, build, 32-byte verification hash
    const int EntryHeaderSize = 32; // v9: magic, region, push, unique id, table hash, record id, data size, status + 3

    public static HotfixCacheInfo Read(string path)
    {
        var b = File.ReadAllBytes(path);
        if (b.Length < HeaderSize || !IsMagic(b, 0))
            throw new InvalidDataException($"{path} is not a hotfix cache (no XFTH header)");
        var version = BitConverter.ToInt32(b, 4);
        if (version != 9)
            throw new InvalidDataException($"{path}: hotfix cache version {version}, this reader knows 9");
        int pos = HeaderSize, entries = 0, highest = 0;
        while (pos < b.Length)
        {
            if (pos + EntryHeaderSize > b.Length || !IsMagic(b, pos))
                throw new InvalidDataException($"{path}: entry {entries} at byte {pos} does not parse (incomplete file?)");
            highest = Math.Max(highest, BitConverter.ToInt32(b, pos + 8));
            pos += EntryHeaderSize + BitConverter.ToInt32(b, pos + 24);
            entries++;
        }
        if (pos != b.Length)
            throw new InvalidDataException($"{path}: the last entry runs past the end of the file");
        return new HotfixCacheInfo(path, version, BitConverter.ToInt32(b, 8), entries, highest,
            Convert.ToHexStringLower(SHA256.HashData(b)));
    }

    static bool IsMagic(byte[] b, int at) => b[at] == 'X' && b[at + 1] == 'F' && b[at + 2] == 'T' && b[at + 3] == 'H';
}

/// <summary>Per table: what the hotfixes did. Deletes of rows the files hold are counted, not applied.</summary>
sealed record HotfixStats(int Added, int Replaced, int DeletesIgnored, int DeletesApplied);

static class Hotfix
{
    /// <summary>The build number of a "x.y.z.nnnnn" build string.</summary>
    public static int BuildNumber(string build) => int.Parse(build[(build.LastIndexOf('.') + 1)..]);

    /// <summary>Opens the cache for the files' build; any other build is refused (DBCD would apply it silently).</summary>
    public static (HotfixReader Reader, HotfixCacheInfo Info) Open(string path, string build)
    {
        var info = HotfixCacheInfo.Read(path);
        if (info.Build != BuildNumber(build))
            throw new InvalidOperationException(
                $"hotfix cache {path} is build {info.Build}, the files are {build}: refused (ADR 0039)");
        return (new HotfixReader(path), info);
    }

    /// <summary>Additions and changes apply. A delete of a row the files hold is ignored and counted (what it
    /// means is not verified, ADR 0039 option F); a delete of a row an earlier hotfix added applies. Counts: rows
    /// added (net, after such deletes), rows of the files replaced, deletes ignored, hotfix rows deleted again.</summary>
    public static HotfixStats Apply(IDBCDStorage storage, HotfixReader reader)
    {
        var fromFiles = new HashSet<int>(storage.Keys);
        var addedRows = new HashSet<int>();
        var replacedRows = new HashSet<int>();
        int ignored = 0, applied = 0;
        storage.ApplyingHotfixes(reader, (entry, flag) =>
        {
            var op = HotfixReader.DefaultProcessor(entry, flag);
            var id = entry.RecordId;
            if (op == RowOp.Delete)
            {
                if (fromFiles.Contains(id)) { ignored++; return RowOp.Ignore; }
                if (addedRows.Remove(id)) applied++;
            }
            else if (op == RowOp.Add)
            {
                if (fromFiles.Contains(id)) replacedRows.Add(id); else addedRows.Add(id);
            }
            return op;
        });
        return new HotfixStats(addedRows.Count, replacedRows.Count, ignored, applied);
    }

    /// <summary>The client's own decryption keys (TactKeyLookup + TactKey, with the cache's key hotfixes) into
    /// TACTSharp's key store, so encrypted sections of released content read. Never the community list (owner,
    /// 31.10.2026). Returns the number of keys set.</summary>
    public static int LoadClientKeys(Client client, string defsDir, HotfixReader? reader)
    {
        var lookup = Db2.Load(client, defsDir, "TactKeyLookup");
        var keys = Db2.Load(client, defsDir, "TactKey");
        if (reader != null)
        {
            lookup.ApplyingHotfixes(reader);
            keys.ApplyingHotfixes(reader);
        }
        var set = 0;
        foreach (var id in lookup.Keys)
        {
            if (!keys.ContainsKey(id)) continue;
            var name = (byte[])lookup[id]["TACTID"];
            var key = (byte[])keys[id]["Key"];
            if (key.Length != 16 || key.All(x => x == 0)) continue;
            KeyService.SetKey(BitConverter.ToUInt64(name, 0), key);
            set++;
        }
        return set;
    }
}
