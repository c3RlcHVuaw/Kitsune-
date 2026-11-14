namespace Kitsune.Core;

public sealed class LinkParseException(string message) : Exception(message);

/// Share-link parser: vless:// (TCP / gRPC / WebSocket over Reality, TLS or plain) and hysteria2://.
public static class ProxyLink
{
    public static ServerConfig Parse(string link)
    {
        var trimmed = link.Trim();
        var colon = trimmed.IndexOf(':');
        var scheme = (colon < 0 ? trimmed : trimmed[..colon]).ToLowerInvariant();
        var server = scheme switch
        {
            "vless" => Vless(trimmed),
            "hysteria2" or "hy2" => Hysteria2(trimmed),
            _ => throw new LinkParseException($"unsupported scheme {scheme}"),
        };
        server.Link = trimmed;
        return server;
    }

    sealed record Parts(string User, string Host, int Port, Dictionary<string, string> Query, string? Fragment);

    /// scheme://user@host:port?query#fragment, with bracketed IPv6 hosts.
    static Parts Split(string link, string what)
    {
        var rest = link[(link.IndexOf("://", StringComparison.Ordinal) + 3)..];
        string? fragment = null;
        var hash = rest.IndexOf('#');
        if (hash >= 0) { fragment = Uri.UnescapeDataString(rest[(hash + 1)..]); rest = rest[..hash]; }
        var query = new Dictionary<string, string>();
        var q = rest.IndexOf('?');
        if (q >= 0)
        {
            foreach (var pair in rest[(q + 1)..].Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var eq = pair.IndexOf('=');
                if (eq <= 0) continue;
                var value = Uri.UnescapeDataString(pair[(eq + 1)..].Replace("+", "%20"));
                if (value.Length > 0) query[Uri.UnescapeDataString(pair[..eq])] = value;
            }
            rest = rest[..q];
        }
        rest = rest.TrimEnd('/');
        var at = rest.LastIndexOf('@');
        var user = at < 0 ? "" : Uri.UnescapeDataString(rest[..at]);
        var hostPort = at < 0 ? rest : rest[(at + 1)..];
        string host; var port = 0;
        if (hostPort.StartsWith('['))
        {
            var close = hostPort.IndexOf(']');
            if (close < 0) throw new LinkParseException($"{what}: host");
            host = hostPort[1..close];
            if (hostPort.Length > close + 2 && hostPort[close + 1] == ':') int.TryParse(hostPort[(close + 2)..], out port);
        }
        else
        {
            var c = hostPort.LastIndexOf(':');
            host = c < 0 ? hostPort : hostPort[..c];
            if (c >= 0) int.TryParse(hostPort[(c + 1)..], out port);
        }
        return new Parts(user, host, port, query, string.IsNullOrEmpty(fragment) ? null : fragment);
    }

    static ServerConfig Vless(string link)
    {
        var p = Split(link, "vless");
        if (p.User.Length == 0) throw new LinkParseException("vless: missing uuid");
        if (p.Host.Length == 0) throw new LinkParseException("vless: missing host");
        if (p.Port is < 1 or > 65535) throw new LinkParseException("vless: missing port");
        var q = p.Query;
        var security = q.GetValueOrDefault("security", "none");
        if (security is not ("reality" or "tls" or "none")) throw new LinkParseException($"vless: security={security}");
        var transport = q.GetValueOrDefault("type", "tcp");
        if (transport is not ("tcp" or "grpc" or "ws")) throw new LinkParseException($"vless: type={transport}");

        var outbound = new Dictionary<string, object?> { ["type"] = "vless", ["server"] = p.Host, ["server_port"] = p.Port, ["uuid"] = p.User };
        if (q.TryGetValue("flow", out var flow)) outbound["flow"] = flow;
        if (security != "none")
        {
            var tls = new Dictionary<string, object?> { ["enabled"] = true };
            var sni = q.GetValueOrDefault("sni");
            var fp = q.GetValueOrDefault("fp");
            if (security == "reality")
            {
                if (sni == null) throw new LinkParseException("vless: missing sni");
                if (!q.TryGetValue("pbk", out var pbk)) throw new LinkParseException("vless: missing pbk");
                fp ??= "chrome"; // Reality requires uTLS
                tls["reality"] = new Dictionary<string, object?> { ["enabled"] = true, ["public_key"] = pbk, ["short_id"] = q.GetValueOrDefault("sid", "") };
            }
            if (sni != null) tls["server_name"] = sni;
            if (fp != null) tls["utls"] = new Dictionary<string, object?> { ["enabled"] = true, ["fingerprint"] = fp };
            outbound["tls"] = tls;
        }
        switch (transport)
        {
            case "grpc":
                outbound["transport"] = new Dictionary<string, object?> { ["type"] = "grpc", ["service_name"] = q.GetValueOrDefault("serviceName", "") };
                break;
            case "ws":
                var ws = new Dictionary<string, object?> { ["type"] = "ws", ["path"] = q.GetValueOrDefault("path", "/") };
                if (q.TryGetValue("host", out var hostHeader)) ws["headers"] = new Dictionary<string, object?> { ["Host"] = hostHeader };
                outbound["transport"] = ws;
                break;
        }
        var summary = string.Join(" · ", new[] { "VLESS", transport.ToUpperInvariant().Replace("GRPC", "gRPC"), security == "none" ? null : security == "tls" ? "TLS" : "Reality" }.Where(s => s != null));
        return new ServerConfig(p.Fragment ?? p.Host, summary, outbound);
    }

    // shortcut: single port only; port ranges (mport) need sing-box server_ports, add when a provider uses them.
    static ServerConfig Hysteria2(string link)
    {
        var p = Split(link, "hysteria2");
        if (p.Host.Length == 0 || p.Port is < 1 or > 65535 || p.User.Length == 0) throw new LinkParseException("hysteria2");
        var q = p.Query;
        var tls = new Dictionary<string, object?> { ["enabled"] = true, ["server_name"] = q.GetValueOrDefault("sni", p.Host) };
        if (q.GetValueOrDefault("insecure") == "1") tls["insecure"] = true;
        var outbound = new Dictionary<string, object?> { ["type"] = "hysteria2", ["server"] = p.Host, ["server_port"] = p.Port, ["password"] = p.User, ["tls"] = tls };
        if (q.GetValueOrDefault("obfs") == "salamander" && q.TryGetValue("obfs-password", out var obfs))
            outbound["obfs"] = new Dictionary<string, object?> { ["type"] = "salamander", ["password"] = obfs };
        return new ServerConfig(p.Fragment ?? p.Host, "Hysteria2 · QUIC", outbound);
    }
}
