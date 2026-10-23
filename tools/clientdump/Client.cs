// Opens a local WoW install (CASC/TACT storage) with TACTSharp. Never touches the network, never writes to the install.
using TACTSharp;

namespace ClientDump;

sealed class Client
{
    public required BuildInstance Build { get; init; }
    public required string Product { get; init; }
    public required string Version { get; init; }
    public required string BuildKey { get; init; }
    public required string RootDir { get; init; }

    /// <summary>The "x.y.z.nnnnn" build string DBCD wants.</summary>
    public string BuildString => Version;

    /// <param name="install">A flavor folder (_retail_, _classic_beta_) or the folder holding .build.info.</param>
    public static Client Open(string install, string? product, string cacheDir, string? cdnConfig = null)
    {
        var root = new DirectoryInfo(Path.GetFullPath(install));
        while (root != null && !File.Exists(Path.Combine(root.FullName, ".build.info")))
            root = root.Parent;
        if (root == null)
            throw new FileNotFoundException(".build.info not found in or above " + install);

        if (product == null)
        {
            // Flavor folders carry a .flavor.info: line 1 is the header, line 2 the product name.
            var flavor = Path.Combine(Path.GetFullPath(install), ".flavor.info");
            product = File.Exists(flavor) ? File.ReadAllLines(flavor)[1].Trim() : "wow";
        }

        var build = new BuildInstance();
        build.Settings.BaseDir = root.FullName;
        build.Settings.Product = product;
        build.Settings.TryCDN = false;           // fail instead of downloading
        build.Settings.ListfileFallback = false; // no listfile download
        build.Settings.CacheDir = cacheDir;
        Settings.LogLevel = TSLogLevel.Warn;

        var info = new BuildInfo(Path.Combine(root.FullName, ".build.info"), build.Settings, build.cdn);
        var entry = info.Entries.FirstOrDefault(e => e.Product == product);
        if (entry.BuildConfig == null)
            throw new InvalidOperationException("Product " + product + " not in .build.info (have: "
                + string.Join(", ", info.Entries.Select(e => e.Product)) + ")");

        build.cdn.ProductDirectory = entry.CDNPath ?? "";
        build.LoadConfigs(entry.BuildConfig, cdnConfig ?? LocalCdnConfig(root.FullName, entry.CDNConfig));
        build.Load();

        return new Client
        {
            Build = build, Product = product, Version = entry.Version,
            BuildKey = entry.BuildConfig, RootDir = root.FullName,
        };
    }

    /// <summary>The CDN config to load: the one .build.info names when Data/config holds it, else the newest
    /// local CDN config. The launcher rewrites the key before it downloads the new config (seen 20.10.2026 on
    /// both products); the archive list only matters for CDN fetches, which this tool never does.</summary>
    static string LocalCdnConfig(string root, string wanted)
    {
        var configDir = Path.Combine(root, "Data", "config");
        if (File.Exists(Path.Combine(configDir, wanted[..2], wanted[2..4], wanted)))
            return wanted;
        var local = Directory.EnumerateFiles(configDir, "*", SearchOption.AllDirectories)
            .Where(f => File.ReadLines(f).Take(3).Any(l => l.StartsWith("# CDN Configuration")))
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .FirstOrDefault();
        if (local == null)
            throw new FileNotFoundException($"CDN config {wanted} from .build.info is not in {configDir} and no other local CDN config exists (run the launcher once, or pass --cdn-config)");
        var key = Path.GetFileName(local);
        Console.Error.WriteLine($"warning: CDN config {wanted} from .build.info is not in Data/config; using local {key} (local reads only)");
        return key;
    }

    public byte[] ReadFdid(uint fdid) => Build.OpenFileByFDID(fdid);

    /// <summary>Looks a path up by its Jenkins96 name hash in the root manifest; null if the root has no such name.</summary>
    public uint? FindFdidByName(string path)
    {
        var lookup = new Jenkins96().ComputeHash(path.Replace('/', '\\').ToUpperInvariant(), true);
        var entries = Build.Root!.GetEntriesByLookup(lookup);
        return entries.Count == 0 ? null : entries[0].fileDataID;
    }
}
