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
        clientdump navgraph --terrain <file.bin.gz> --nodes <nodes.json> --config <config.json> --out <graph.json> [--png <file>]
        clientdump terrain --install <client folder> --map <name or id> --wdt-fdid <id> --out <folder> [--roads <fdid list>] [--tile x,y]
        clientdump navmesh --install <client folder> --map <name or id> --wdt-fdid <id> --out <folder> [--roads <fdid list>] [--tiles x0,y0,x1,y1] [--blocked <words>] [--threads n] [--listfile <csv>] [--read-only]
        clientdump mapdata --install <client folder> --map <name or id> --wdt-fdid <id> --out <folder> [--tiles x0,y0,x1,y1] [--pixels 256] [--threads n]
        clientdump blp --in <folder of .rgba cells> [--threads n]
        clientdump navmesh-png --mesh <file.navmesh> --out <file.png> (--tiles x0,y0,x1,y1 | --at wx,wy,radius) [--z zmin,zmax] [--ppy n]
        clientdump navmesh-check --mesh <file.navmesh> --taxi <TaxiNodes.json>
        clientdump navnet --navmesh <file.navmesh> --nodes <nav-nodes.json> --out <file.json> [--places <json>] [--config <json>] [--client forever|retail] [--png <file> --png-tiles x0,y0,x1,y1]
        clientdump navmesh-path --mesh <file.navmesh> --from wx,wy,wz --to wx,wy,wz [--corners]
        common: --product <name> (default: from .flavor.info)  --cache <dir> (default: .local/clientdump-cache)  --cdn-config <hash> (when .build.info names one that is not local)  --locale <enUS|deDE|zhCN|...> (the text language to read, default enUS)  --trace (stack trace on error)
        """);
    return 0;
}

if (args[0] is "navgraph" or "navmesh-png" or "navmesh-check" or "navmesh-path" or "navnet" or "blp") // work on files, open no client
{
    try
    {
        if (args[0] == "blp")
        {
            BlpCells.Run(Opt(args, "in") ?? throw new ArgumentException("--in is required"),
                int.Parse(Opt(args, "threads") ?? Environment.ProcessorCount.ToString()));
            return 0;
        }
        if (args[0] == "navmesh-png")
        {
            NavmeshView.Png(Opt(args, "mesh") ?? throw new ArgumentException("--mesh is required"),
                Opt(args, "out") ?? throw new ArgumentException("--out is required"),
                Opt(args, "tiles"), Opt(args, "at"), Opt(args, "z"), Opt(args, "ppy"));
            return 0;
        }
        if (args[0] == "navnet")
        {
            Navnet.Run(Opt(args, "navmesh") ?? throw new ArgumentException("--navmesh is required"),
                Opt(args, "nodes") ?? throw new ArgumentException("--nodes is required"),
                Opt(args, "places"), Opt(args, "config"),
                Opt(args, "out") ?? throw new ArgumentException("--out is required"),
                Opt(args, "client"), Opt(args, "png"), Opt(args, "png-tiles"));
            return 0;
        }
        if (args[0] == "navmesh-path")
        {
            NavmeshView.Path(Opt(args, "mesh") ?? throw new ArgumentException("--mesh is required"),
                Opt(args, "from") ?? throw new ArgumentException("--from is required"),
                Opt(args, "to") ?? throw new ArgumentException("--to is required"), args.Contains("--corners"));
            return 0;
        }
        if (args[0] == "navmesh-check")
        {
            NavmeshView.Check(Opt(args, "mesh") ?? throw new ArgumentException("--mesh is required"),
                Opt(args, "taxi") ?? throw new ArgumentException("--taxi is required"));
            return 0;
        }
        Navgraph.Run(Opt(args, "terrain") ?? throw new ArgumentException("--terrain is required"),
            Opt(args, "nodes") ?? throw new ArgumentException("--nodes is required"),
            Opt(args, "config") ?? throw new ArgumentException("--config is required"),
            Opt(args, "out") ?? throw new ArgumentException("--out is required"), Opt(args, "png"));
        return 0;
    }
    catch (Exception e)
    {
        Console.Error.WriteLine("error: " + e.Message);
        if (args.Contains("--trace")) Console.Error.WriteLine(e.ToString());
        return 1;
    }
}

try
{
    var install = Opt(args, "install") ?? throw new ArgumentException("--install is required");
    var client = Client.Open(install, Opt(args, "product"), Opt(args, "cache") ?? Path.Combine(".local", "clientdump-cache"), Opt(args, "cdn-config"),
        Opt(args, "locale"));
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
        case "terrain":
            Terrain.Run(client, defs,
                Opt(args, "map") ?? throw new ArgumentException("--map is required"),
                Opt(args, "out") ?? throw new ArgumentException("--out is required"),
                Opt(args, "wdt-fdid"), Opt(args, "listfile"), Opt(args, "roads"), Opt(args, "tile"));
            break;
        case "navmesh":
            Navmesh.Run(client, defs,
                Opt(args, "map") ?? throw new ArgumentException("--map is required"),
                Opt(args, "out") ?? throw new ArgumentException("--out is required"),
                Opt(args, "wdt-fdid"), Opt(args, "listfile"), Opt(args, "roads"), Opt(args, "tiles"), Opt(args, "blocked"),
                int.Parse(Opt(args, "threads") ?? Environment.ProcessorCount.ToString()), args.Contains("--read-only"));
            break;
        case "mapdata":
            MapData.Run(client, defs,
                Opt(args, "map") ?? throw new ArgumentException("--map is required"),
                Opt(args, "out") ?? throw new ArgumentException("--out is required"),
                Opt(args, "wdt-fdid"), Opt(args, "listfile"), Opt(args, "tiles"),
                int.Parse(Opt(args, "pixels") ?? "256"),
                int.Parse(Opt(args, "threads") ?? Environment.ProcessorCount.ToString()));
            break;
        case "textures":
            // BLP textures by FileDataID as PNG, one per line of --list (ADR 0036: the zone paintings)
            var texOut = Opt(args, "out") ?? throw new ArgumentException("--out is required");
            Directory.CreateDirectory(texOut);
            var texCount = 0;
            foreach (var line in File.ReadAllLines(Opt(args, "list") ?? throw new ArgumentException("--list is required")))
            {
                if (!uint.TryParse(line.Trim(), out var fdid)) continue;
                var png = Path.Combine(texOut, fdid + ".png");
                if (File.Exists(png)) continue;
                using var blpStream = new MemoryStream(client.ReadFdid(fdid));
                var bgra = new BLPSharp.BLPFile(blpStream).GetPixels(0, out var tw, out var th);
                Png.Write(png, bgra, tw, th);
                texCount++;
            }
            Console.WriteLine($"textures: {texCount} written -> {texOut}");
            break;
        case "raw":
            // one client file by FileDataID, as stored (a font for a build-time preview)
            File.WriteAllBytes(Opt(args, "out") ?? throw new ArgumentException("--out is required"),
                client.ReadFdid(uint.Parse(Opt(args, "fdid") ?? throw new ArgumentException("--fdid is required"))));
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
