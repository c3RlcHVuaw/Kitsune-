using System.Text;
using System.Text.Json.Nodes;

namespace Kitsune.Core;

/// Metadata a subscription server sends in response headers (Marzban / Remnawave / 3x-ui conventions).
public sealed class SubscriptionInfo
{
    public string? Title { get; set; }
    public long? Upload { get; set; }
    public long? Download { get; set; }
    /// null or 0 means unlimited.
    public long? Total { get; set; }
    public DateTimeOffset? Expire { get; set; }
    public int? UpdateIntervalHours { get; set; }
    public string? Announce { get; set; }
    public string? SupportUrl { get; set; }
    public string? WebPageUrl { get; set; }

    public long? Used => Upload == null && Download == null ? null : (Upload ?? 0) + (Download ?? 0);

    public static SubscriptionInfo Parse(IReadOnlyDictionary<string, string> headers)
    {
        var h = headers.GroupBy(p => p.Key.ToLowerInvariant()).ToDictionary(g => g.Key, g => g.Last().Value);
        var info = new SubscriptionInfo
        {
            Title = h.GetValueOrDefault("profile-title") is { } t ? DecodeText(t) : null,
            Announce = h.GetValueOrDefault("announce") is { } a ? DecodeText(a) : null,
            UpdateIntervalHours = int.TryParse(h.GetValueOrDefault("profile-update-interval")?.Trim(), out var hours) ? hours : null,
            SupportUrl = Link(h.GetValueOrDefault("support-url")),
            WebPageUrl = Link(h.GetValueOrDefault("profile-web-page-url")),
        };
        if (h.TryGetValue("subscription-userinfo", out var userinfo))
        {
            // "upload=123; download=456; total=789; expire=1767225600"
            foreach (var pair in userinfo.Split(';'))
            {
                var kv = pair.Split('=', 2).Select(s => s.Trim()).ToArray();
                if (kv.Length != 2 || !long.TryParse(kv[1], out var value)) continue;
                switch (kv[0])
                {
                    case "upload": info.Upload = value; break;
                    case "download": info.Download = value; break;
                    case "total": info.Total = value; break;
                    case "expire": info.Expire = value > 0 ? DateTimeOffset.FromUnixTimeSeconds(value) : null; break;
                }
            }
        }
        return info;
    }

    static string? Link(string? value)
    {
        if (value == null) return null;
        var text = DecodeText(value).Trim();
        return Uri.TryCreate(text, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" or "tg" ? text : null;
    }

    /// Some panels send `base64:<data>` to carry non-ASCII text in headers.
    static string DecodeText(string value) =>
        value.StartsWith("base64:") && SubscriptionParser.TryBase64(value[7..], out var decoded) ? decoded : value;
}

/// Turns a subscription response body into servers.
public static class SubscriptionParser
{
    /// Outbound types passed through from sing-box JSON subscriptions.
    static readonly HashSet<string> ProxyTypes = ["vless", "vmess", "trojan", "shadowsocks", "hysteria2", "tuic", "wireguard"];

    /// Returns parsed servers and how many entries were skipped as unsupported.
    public static (List<ServerConfig> Servers, int Skipped) Servers(string body)
    {
        var text = body.Trim();
        if (text.StartsWith('{') && Json.ParseObject(text) is { } json && json.GetValueOrDefault("outbounds") is List<object?> outbounds)
            return FromSingBox(outbounds.OfType<Dictionary<string, object?>>());
        if (!text.Contains("://") && TryBase64(text, out var decoded)) text = decoded;
        var servers = new List<ServerConfig>();
        var skipped = 0;
        foreach (var line in text.Split(['\n', '\r'], StringSplitOptions.RemoveEmptyEntries).Select(l => l.Trim()).Where(l => l.Length > 0))
        {
            try { servers.Add(ProxyLink.Parse(line)); } catch (LinkParseException) { skipped++; }
        }
        return (Dedup(servers), skipped);
    }

    static (List<ServerConfig>, int) FromSingBox(IEnumerable<Dictionary<string, object?>> outbounds)
    {
        var servers = new List<ServerConfig>();
        var skipped = 0;
        foreach (var outbound in outbounds)
        {
            if (outbound.GetValueOrDefault("type") is not string type || !ProxyTypes.Contains(type)) continue; // selectors, direct, dns…
            var name = outbound.GetValueOrDefault("tag") as string ?? type;
            outbound.Remove("tag");
            outbound.Remove("detour"); // points at tags from the provider's config, not ours
            servers.Add(new ServerConfig(name, Summary(outbound), outbound));
        }
        return (Dedup(servers), skipped);
    }

    static string Summary(Dictionary<string, object?> outbound)
    {
        var type = ((outbound.GetValueOrDefault("type") as string) ?? "").ToUpperInvariant()
            .Replace("HYSTERIA2", "Hysteria2").Replace("SHADOWSOCKS", "Shadowsocks").Replace("WIREGUARD", "WireGuard");
        var transport = (outbound.GetValueOrDefault("transport") as Dictionary<string, object?>)?.GetValueOrDefault("type") as string;
        var tls = outbound.GetValueOrDefault("tls") as Dictionary<string, object?>;
        var security = tls?.ContainsKey("reality") == true ? "Reality" : tls?.GetValueOrDefault("enabled") is true ? "TLS" : null;
        return string.Join(" · ", new[] { type, transport == null ? null : transport == "grpc" ? "gRPC" : transport.ToUpperInvariant(), security }.Where(s => s != null));
    }

    static List<ServerConfig> Dedup(List<ServerConfig> servers)
    {
        var seen = new HashSet<string>();
        return servers.Where(s => seen.Add(s.Id)).ToList();
    }

    internal static bool TryBase64(string text, out string decoded)
    {
        var n = new string(text.Where(c => !char.IsWhiteSpace(c)).ToArray()).Replace('-', '+').Replace('_', '/');
        n += new string('=', (4 - n.Length % 4) % 4);
        try { decoded = Encoding.UTF8.GetString(Convert.FromBase64String(n)); return true; }
        catch (FormatException) { decoded = ""; return false; }
    }
}
