// Loads a DB2 table from the client with DBCD + WoWDBDefs and writes every row as JSON.
using System.Text.Json;
using DBCD;
using DBCD.Providers;

namespace ClientDump;

/// <summary>Serves DB2 bytes out of the client instead of a folder on disk.</summary>
sealed class ClientDbcProvider(Client client, string defsDir, string? fdidOverride) : IDBCProvider
{
    public Stream StreamForTableName(string tableName, string build)
    {
        var fdid = fdidOverride != null ? uint.Parse(fdidOverride) : ResolveFdid(tableName);
        return new MemoryStream(client.ReadFdid(fdid));
    }

    uint ResolveFdid(string table)
    {
        // 1. manifest.json of WoWDBDefs (table name -> db2FileDataID), 2. name hash in the root manifest.
        var manifest = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(defsDir).TrimEnd('/', '\\'))!, "manifest.json");
        if (File.Exists(manifest))
        {
            using var doc = JsonDocument.Parse(File.ReadAllBytes(manifest));
            foreach (var e in doc.RootElement.EnumerateArray())
                if (e.TryGetProperty("tableName", out var n) && n.GetString() == table
                    && e.TryGetProperty("db2FileDataID", out var id) && client.Build.Root!.FileExists(id.GetUInt32()))
                    return id.GetUInt32();
        }
        return client.FindFdidByName($"dbfilesclient/{table}.db2")
            ?? throw new FileNotFoundException($"no FileDataID for {table} in this client; pass --fdid");
    }
}

static class Db2
{
    public static IDBCDStorage Load(Client client, string defsDir, string table, string? fdid = null)
    {
        var dbcd = new DBCD.DBCD(new ClientDbcProvider(client, defsDir, fdid), new FilesystemDBDProvider(defsDir));
        return dbcd.Load(table, client.BuildString);
    }

    public static void Dump(Client client, string defsDir, string table, string outFile, string? fdid)
    {
        var storage = Load(client, defsDir, table, fdid);
        var columns = storage.AvailableColumns;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outFile))!);
        var tmp = outFile + ".tmp";
        using (var fs = File.Create(tmp))
        using (var w = new Utf8JsonWriter(fs))
        {
            w.WriteStartObject();
            w.WriteString("table", table);
            w.WriteString("build", client.BuildString);
            w.WriteNumber("rowCount", storage.Count);
            w.WriteStartArray("columns");
            foreach (var c in columns) w.WriteStringValue(c);
            w.WriteEndArray();
            w.WriteStartArray("rows");
            foreach (var key in storage.Keys.OrderBy(k => k))
            {
                var row = storage[key];
                w.WriteStartObject();
                foreach (var c in columns)
                {
                    w.WritePropertyName(c);
                    WriteValue(w, row[c]);
                }
                w.WriteEndObject();
            }
            w.WriteEndArray();
            w.WriteEndObject();
        }
        File.Move(tmp, outFile, true);
        Console.WriteLine($"{table}: {storage.Count} rows, {columns.Length} columns -> {outFile}");
    }

    static void WriteValue(Utf8JsonWriter w, object? v)
    {
        switch (v)
        {
            case null: w.WriteNullValue(); break;
            case string s: w.WriteStringValue(s); break;
            case bool b: w.WriteBooleanValue(b); break;
            case float f: if (float.IsFinite(f)) w.WriteNumberValue(f); else w.WriteNullValue(); break;
            case double d: if (double.IsFinite(d)) w.WriteNumberValue(d); else w.WriteNullValue(); break;
            case sbyte or byte or short or ushort or int or uint or long or ulong:
                w.WriteRawValue(Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture)!); break;
            case Array a:
                w.WriteStartArray();
                foreach (var item in a) WriteValue(w, item);
                w.WriteEndArray();
                break;
            default: w.WriteStringValue(v.ToString()); break;
        }
    }
}
