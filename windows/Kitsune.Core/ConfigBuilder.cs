namespace Kitsune.Core;

using Obj = Dictionary<string, object?>;

/// Builds the sing-box JSON config.
/// Route order: sniff → DNS → private nets direct → user "always direct" → user "always VPN"
/// → Russian domain lists → Russian IP list → everything else through the proxy.
public static class ConfigBuilder
{
    public sealed record Controller(int Port, string Secret);

    public static string Tag(ServerConfig server) => $"s-{server.Id}";

    /// <param name="bundledRuleSets">folder with `tag.srs` snapshots, used until the first successful download.</param>
    public static string Build(ServerConfig server, IReadOnlyList<ServerConfig>? servers = null, RoutingSettings? routing = null,
                               string? bundledRuleSets = null, Controller? controller = null, bool findProcess = false)
    {
        servers ??= [];
        routing ??= new RoutingSettings();
        var routeRules = new List<Obj>
        {
            new() { ["action"] = "sniff" },
            new() { ["protocol"] = "dns", ["action"] = "hijack-dns" },
            new() { ["ip_is_private"] = true, ["outbound"] = "direct" },
        };
        var dnsRules = new List<Obj>();

        if (routing.UsesUserLists)
        {
            var known = new[] { server }.Concat(servers).Select(s => s.Id).ToHashSet();
            foreach (var (app, id) in routing.AppServers.OrderBy(p => p.Key, StringComparer.Ordinal).Where(p => known.Contains(p.Value)))
                routeRules.Add(new() { ["process_name"] = new[] { app }, ["outbound"] = $"s-{id}" });
            if (routing.DirectApps.Count > 0) routeRules.Add(new() { ["process_name"] = routing.DirectApps, ["outbound"] = "direct" });
            if (routing.ProxyApps.Count > 0) routeRules.Add(new() { ["process_name"] = routing.ProxyApps, ["outbound"] = "proxy" });
            if (Match(routing.Direct) is { } direct)
            {
                routeRules.Add(new Obj(direct) { ["outbound"] = "direct" });
                if (direct.TryGetValue("domain_suffix", out var d)) dnsRules.Add(new() { ["domain_suffix"] = d, ["server"] = "russia" });
            }
            if (Match(routing.EffectiveProxy.ToList()) is { } proxy)
            {
                routeRules.Add(new Obj(proxy) { ["outbound"] = "proxy" });
                if (proxy.TryGetValue("domain_suffix", out var d)) dnsRules.Add(new() { ["domain_suffix"] = d, ["server"] = "remote" });
            }
        }

        var ruleSets = new List<Obj>();
        if (routing.Profile == Profile.RussiaDirect)
        {
            var domainTags = RuleSources.DomainSets.Select(s => s.Tag).ToList();
            var ipTags = RuleSources.IpSets.Select(s => s.Tag).ToList();
            routeRules.Add(new() { ["domain_suffix"] = RuleSources.RussianTlds, ["rule_set"] = domainTags, ["outbound"] = "direct" });
            routeRules.Add(new() { ["rule_set"] = ipTags, ["outbound"] = "direct" });
            dnsRules.Add(new() { ["domain_suffix"] = RuleSources.RussianTlds, ["rule_set"] = domainTags, ["server"] = "russia" });
            foreach (var (tag, path) in RuleSources.DomainSets.Concat(RuleSources.IpSets)) ruleSets.Add(RemoteSet(tag, path, bundledRuleSets));
        }

        if (routing.BlockAds)
        {
            ruleSets.Add(RemoteSet(RuleSources.AdsSet.Tag, RuleSources.AdsSet.Path, bundledRuleSets));
            routeRules.Insert(2, new() { ["rule_set"] = new[] { RuleSources.AdsSet.Tag }, ["action"] = "reject" }); // before every direct/proxy rule
        }
        if (routing.BlockIPv6) routeRules.Insert(2, new() { ["ip_version"] = 6, ["action"] = "reject" });

        var route = new Obj
        {
            ["rules"] = routeRules,
            ["final"] = "proxy",
            ["auto_detect_interface"] = true,
            ["default_domain_resolver"] = "russia", // resolves the proxy server's own hostname outside the tunnel
        };
        if (ruleSets.Count > 0) route["rule_set"] = ruleSets;
        if (findProcess || routing.UsesUserLists && (routing.DirectApps.Count + routing.ProxyApps.Count > 0 || routing.AppServers.Count > 0))
            route["find_process"] = true;

        var dns = new Obj
        {
            ["servers"] = new List<Obj>
            {
                new() { ["type"] = "https", ["tag"] = "remote", ["server"] = routing.Dns.Address(), ["detour"] = "proxy" },
                new() { ["type"] = "udp", ["tag"] = "russia", ["server"] = RuleSources.RussianDns },
            },
            ["final"] = "remote",
        };
        if (dnsRules.Count > 0) dns["rules"] = dnsRules;
        if (routing.BlockIPv6) dns["strategy"] = "ipv4_only";

        var outbounds = ProxyOutbounds(server, servers);
        outbounds.Add(new() { ["type"] = "direct", ["tag"] = "direct" });
        var config = new Obj
        {
            ["log"] = new Obj { ["level"] = "info" },
            ["dns"] = dns,
            ["inbounds"] = new List<Obj>
            {
                new()
                {
                    ["type"] = "tun", ["tag"] = "tun-in",
                    ["address"] = new[] { "172.19.0.1/30", "fdfe:dcba:9876::1/126" },
                    ["auto_route"] = true, ["strict_route"] = true,
                },
            },
            ["outbounds"] = outbounds,
            ["route"] = route,
        };
        var experimental = new Obj();
        // Keeps downloaded rule-sets between launches, so a failed update falls back to the last good copy.
        if (ruleSets.Count > 0) experimental["cache_file"] = new Obj { ["enabled"] = true };
        if (controller != null) experimental["clash_api"] = new Obj { ["external_controller"] = $"127.0.0.1:{controller.Port}", ["secret"] = controller.Secret };
        if (experimental.Count > 0) config["experimental"] = experimental;
        return Json.Write(config, indented: true);
    }

    static Obj RemoteSet(string tag, string path, string? bundled)
    {
        var set = new Obj
        {
            ["type"] = "remote", ["tag"] = tag, ["format"] = "binary", ["url"] = $"{RuleSources.Base}/{path}",
            ["http_client"] = new Obj { ["detour"] = "proxy" }, // GitHub may be unreachable directly from Russia
            ["update_interval"] = "24h",
        };
        if (bundled != null) set["initial_path"] = $"{bundled}/{tag}.srs".Replace('\\', '/');
        return set;
    }

    /// Every server as its own outbound, plus a `proxy` selector defaulting to the chosen one.
    static List<Obj> ProxyOutbounds(ServerConfig selected, IReadOnlyList<ServerConfig> others)
    {
        var seen = new HashSet<string>();
        var all = new[] { selected }.Concat(others).Where(s => seen.Add(s.Id)).ToList();
        var outbounds = all.Select(s =>
        {
            var outbound = Json.ParseObject(s.Outbound) ?? throw new InvalidDataException($"corrupt outbound for {s.Name}");
            outbound["tag"] = Tag(s);
            return outbound;
        }).ToList();
        outbounds.Add(new() { ["type"] = "selector", ["tag"] = "proxy", ["outbounds"] = all.Select(Tag).ToList(), ["default"] = Tag(selected) });
        return outbounds;
    }

    /// One sing-box rule matching any of the entries; invalid entries are skipped.
    static Obj? Match(IReadOnlyList<string> entries)
    {
        var parsed = entries.Select(RouteEntry.Parse).OfType<RouteEntry>().ToList();
        var rule = new Obj();
        var domains = parsed.Where(e => !e.IsCidr).Select(e => e.Value).ToList();
        var cidrs = parsed.Where(e => e.IsCidr).Select(e => e.Value).ToList();
        if (domains.Count > 0) rule["domain_suffix"] = domains;
        if (cidrs.Count > 0) rule["ip_cidr"] = cidrs;
        return rule.Count == 0 ? null : rule;
    }
}
