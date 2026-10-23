// clientdump: reads DB2 tables and minimap tiles straight out of a local WoW client for the Bastians pipeline.
// Usage: see docs/data/client-extraction.md
using ClientDump;

static string? Opt(string[] a, string name)
{
    var i = Array.IndexOf(a, "--" + name);
    return i >= 0 && i + 1 < a.Length ? a[i + 1] : null;
}

if (args.Length == 0 || args[0] is "-h" or "--help")
{
    Console.WriteLine("""
        clientdump info    --install <client folder> [--product <name>]
        clientdump db2     --install <client folder> --table <Name> --out <file.json> [--defs <dir>] [--fdid <id>]
        clientdump minimap --install <client folder> --map <name or id> --out <folder> [--defs <dir>] [--wdt-fdid <id>] [--listfile <csv>] [--tile x,y]
        clientdump overview --install <client folder> --map <name or id> --out <folder> [--wdt-fdid <id>] [--pixels 64] [--span 8] [--format blp|tga] [--no-mips] [--alpha dxt1|dxt5] [--sea rrggbb] [--art <Dir>_art.json]
        common: --product <name> (default: from .flavor.info)  --cache <dir> (default: .local/clientdump-cache)  --cdn-config <hash> (when .build.info names one that is not local)  --trace (stack trace on error)
        """);
    return 0;
}

try
{
    var install = Opt(args, "install") ?? throw new ArgumentException("--install is required");
    var client = Client.Open(install, Opt(args, "product"), Opt(args, "cache") ?? Path.Combine(".local", "clientdump-cache"), Opt(args, "cdn-config"));
    Console.WriteLine($"product={client.Product} version={client.Version} buildKey={client.BuildKey} root={client.RootDir}");
    var defs = Opt(args, "defs") ?? Path.Combine(".local", "WoWDBDefs", "definitions");

    switch (args[0])
    {
        case "info":
            Console.WriteLine($"root fdids={client.Build.Root!.GetAvailableFDIDs().Length} named={client.Build.Root.GetAvailableLookups().Length}");
            foreach (var name in new[] { "world/maps/azeroth/azeroth.wdt", "dbfilesclient/map.db2", "interface/framexml/globalstrings.lua" })
                Console.WriteLine($"  {name}: {client.FindFdidByName(name)?.ToString() ?? "no name hash"}");
            foreach (var a in args.Skip(1).Where(x => uint.TryParse(x, out _)))
                Console.WriteLine($"  fdid {a}: " + (client.Build.Root.FileExists(uint.Parse(a)) ? "present" : "absent"));
            break;
        case "db2":
            Db2.Dump(client, defs,
                Opt(args, "table") ?? throw new ArgumentException("--table is required"),
                Opt(args, "out") ?? throw new ArgumentException("--out is required"),
                Opt(args, "fdid"));
            break;
        case "minimap":
            Minimap.Run(client, defs,
                Opt(args, "map") ?? throw new ArgumentException("--map is required"),
                Opt(args, "out") ?? throw new ArgumentException("--out is required"),
                Opt(args, "wdt-fdid"), Opt(args, "listfile"), Opt(args, "tile"));
            break;
        case "overview":
            Overview.Run(client, defs,
                Opt(args, "map") ?? throw new ArgumentException("--map is required"),
                Opt(args, "out") ?? throw new ArgumentException("--out is required"),
                Opt(args, "wdt-fdid"), Opt(args, "listfile"),
                int.Parse(Opt(args, "pixels") ?? "64"), int.Parse(Opt(args, "span") ?? "8"),
                Opt(args, "format") ?? "blp", !args.Contains("--no-mips"), Opt(args, "alpha") ?? "dxt1", Opt(args, "sea"),
                Opt(args, "art"));
            break;
        default:
            throw new ArgumentException("unknown command " + args[0]);
    }
    return 0;
}
catch (Exception e)
{
    Console.Error.WriteLine("error: " + e.Message);
    if (args.Contains("--trace")) Console.Error.WriteLine(e.ToString());
    return 1;
}
