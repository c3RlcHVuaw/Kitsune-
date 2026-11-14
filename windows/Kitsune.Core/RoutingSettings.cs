using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Kitsune.Core;

public enum Profile { RussiaDirect, AllVPN, Custom }
public enum DnsProvider { Cloudflare, Google, Quad9, AdGuard }
public enum RoutePreset { Streaming, Games, Messengers }

public static class RoutingNames
{
    public static string Address(this DnsProvider p) => p switch
    {
        DnsProvider.Google => "8.8.8.8", DnsProvider.Quad9 => "9.9.9.9", DnsProvider.AdGuard => "94.140.14.14", _ => "1.1.1.1",
    };

    public static string Title(this DnsProvider p) => p switch
    {
        DnsProvider.Google => "Google", DnsProvider.Quad9 => "Quad9", DnsProvider.AdGuard => "AdGuard", _ => "Cloudflare",
    };

    public static string[] Domains(this RoutePreset p) => p switch
    {
        RoutePreset.Streaming => ["netflix.com", "nflxvideo.net", "youtube.com", "googlevideo.com", "ytimg.com", "spotify.com", "scdn.co",
            "twitch.tv", "ttvnw.net", "disneyplus.com", "hulu.com", "primevideo.com"],
        RoutePreset.Games => ["steampowered.com", "steamcommunity.com", "steamstatic.com", "epicgames.com", "riotgames.com",
            "leagueoflegends.com", "ea.com", "battle.net", "blizzard.com", "ubisoft.com", "roblox.com"],
        _ => ["telegram.org", "t.me", "telegra.ph", "whatsapp.com", "whatsapp.net", "signal.org", "discord.com", "discord.gg", "discordapp.com", "viber.com"],
    };
}

/// What goes direct and what goes through the tunnel. Missing JSON fields keep their defaults, so old saved settings still load.
public sealed class RoutingSettings
{
    public Profile Profile { get; set; } = Profile.RussiaDirect;
    public DnsProvider Dns { get; set; } = DnsProvider.Cloudflare;
    public bool BlockAds { get; set; }
    public bool BlockIPv6 { get; set; }
    /// "Always direct" entries: domains or IPs/CIDRs.
    public List<string> Direct { get; set; } = [];
    /// "Always through VPN" entries, same format.
    public List<string> Proxy { get; set; } = [];
    public HashSet<RoutePreset> Presets { get; set; } = [];
    /// Process names (e.g. `telegram.exe`) that always go direct / always through VPN.
    public List<string> DirectApps { get; set; } = [];
    public List<string> ProxyApps { get; set; } = [];
    public Dictionary<string, string> AppServers { get; set; } = [];

    [JsonIgnore]
    public IEnumerable<string> EffectiveProxy => Proxy.Concat(Enum.GetValues<RoutePreset>().Where(Presets.Contains).SelectMany(p => p.Domains()));

    /// User lists apply in every profile except "everything through VPN".
    [JsonIgnore]
    public bool UsesUserLists => Profile != Profile.AllVPN;

    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
        WriteIndented = true,
    };
}

/// One user routing entry, normalised: a domain suffix or an IP range.
public readonly record struct RouteEntry(bool IsCidr, string Value)
{
    /// Accepts `example.com`, `*.example.com`, `https://example.com/path`, `1.2.3.4`, `10.0.0.0/8`, `2001:db8::/32`; null if invalid.
    public static RouteEntry? Parse(string raw)
    {
        var text = raw.Trim().ToLowerInvariant();
        if (text.Length == 0) return null;
        var scheme = text.IndexOf("://", StringComparison.Ordinal);
        if (scheme >= 0) text = text[(scheme + 3)..];

        var cidr = ParseCidr(text, out var isIp);
        if (isIp) return cidr == null ? null : new RouteEntry(true, cidr);

        var slash = text.IndexOf('/');
        if (slash >= 0) text = text[..slash];
        var colon = text.LastIndexOf(':');
        if (colon >= 0) text = text[..colon]; // drop :port
        while (text.StartsWith("*.") || text.StartsWith('.')) text = text[(text.StartsWith("*.") ? 2 : 1)..];
        try { text = new IdnMapping().GetAscii(text); } catch (ArgumentException) { return null; } // пример.рф → xn--e1afmkfd.xn--p1ai
        var labels = text.Split('.');
        static bool Valid(string l) => l.Length is > 0 and <= 63 && !l.StartsWith('-') && !l.EndsWith('-') && l.All(c => char.IsLetterOrDigit(c) || c == '-');
        if (text.Length > 253 || !labels.All(Valid) || labels[^1].All(char.IsDigit)) return null; // numeric last label = malformed IP
        return new RouteEntry(false, text);
    }

    static string? ParseCidr(string text, out bool isIp)
    {
        var parts = text.Split('/', 2);
        var address = parts[0];
        var isV4 = address.Split('.').Length == 4 && IPAddress.TryParse(address, out var a4) && a4.AddressFamily == AddressFamily.InterNetwork;
        var isV6 = !isV4 && address.Contains(':') && IPAddress.TryParse(address, out var a6) && a6.AddressFamily == AddressFamily.InterNetworkV6;
        isIp = isV4 || isV6;
        if (!isIp) return null;
        var max = isV4 ? 32 : 128;
        if (parts.Length == 1) return $"{address}/{max}";
        return int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var prefix) && prefix <= max ? $"{address}/{prefix}" : null;
    }
}
