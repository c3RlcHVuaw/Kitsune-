using System.Text.Json.Nodes;
using Kitsune.Core;
using Xunit;

public class CoreTests
{
    const string Reality = "vless://11111111-2222-3333-4444-555555555555@example.com:443?type=grpc&security=reality&sni=www.microsoft.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=ab&serviceName=svc#%F0%9F%87%B3%F0%9F%87%B1%20Amsterdam";

    [Fact]
    public void ParsesVlessReality()
    {
        var s = ProxyLink.Parse(Reality);
        Assert.Equal("example.com", s.Host);
        Assert.Equal(443, s.Port);
        Assert.Equal("VLESS · gRPC · Reality", s.Summary);
        Assert.Equal("NL", s.CountryCode);
        Assert.Equal("Amsterdam", s.DisplayName);
        Assert.Contains("\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}", s.Outbound);
    }

    [Fact]
    public void IdIsStable() => Assert.Equal(ProxyLink.Parse(Reality).Id, ProxyLink.Parse(Reality).Id);

    [Fact]
    public void RejectsBadLinks()
    {
        Assert.Throws<LinkParseException>(() => ProxyLink.Parse("ftp://x"));
        Assert.Throws<LinkParseException>(() => ProxyLink.Parse("vless://u@h:443?security=reality"));
        Assert.Throws<LinkParseException>(() => ProxyLink.Parse("vless://u@h:99999"));
    }

    [Fact]
    public void ParsesIpv6AndHysteria2()
    {
        Assert.Equal("2001:db8::1", ProxyLink.Parse("vless://u@[2001:db8::1]:443").Host);
        var h = ProxyLink.Parse("hy2://pass@host.example:8443?sni=a.com&obfs=salamander&obfs-password=x#HY");
        Assert.Equal("Hysteria2 · QUIC", h.Summary);
        Assert.True(h.IsUdp);
        Assert.Equal("HY", h.Name);
    }

    [Fact]
    public void RouteEntries()
    {
        Assert.Equal(new RouteEntry(false, "example.com"), RouteEntry.Parse("https://*.Example.com:8080/path"));
        Assert.Equal(new RouteEntry(true, "10.0.0.0/8"), RouteEntry.Parse("10.0.0.0/8"));
        Assert.Equal(new RouteEntry(true, "1.2.3.4/32"), RouteEntry.Parse("1.2.3.4"));
        Assert.Equal(new RouteEntry(false, "xn--e1afmkfd.xn--p1ai"), RouteEntry.Parse("пример.рф"));
        Assert.Null(RouteEntry.Parse("1.2.3.4/99"));
        Assert.Null(RouteEntry.Parse("999.1.1.1"));
        Assert.Null(RouteEntry.Parse(""));
    }

    [Fact]
    public void RussiaDirectConfig()
    {
        var json = ConfigBuilder.Build(ProxyLink.Parse(Reality), controller: new ConfigBuilder.Controller(19090, "s"));
        var root = JsonNode.Parse(json)!;
        Assert.Equal("proxy", root["route"]!["final"]!.GetValue<string>());
        Assert.Equal("sniff", root["route"]!["rules"]![0]!["action"]!.GetValue<string>());
        Assert.Equal(4, root["route"]!["rule_set"]!.AsArray().Count);
        Assert.Equal("127.0.0.1:19090", root["experimental"]!["clash_api"]!["external_controller"]!.GetValue<string>());
        Assert.Contains("\"type\": \"selector\"", json);
    }

    [Fact]
    public void WritesSampleConfig() // checked by hand with `sing-box check -c`
    {
        var routing = new RoutingSettings { Direct = ["bank.ru"], Proxy = ["x.com"], BlockAds = true, BlockIPv6 = true, DirectApps = ["telegram.exe"] };
        File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "config-sample.json"), ConfigBuilder.Build(ProxyLink.Parse(Reality), routing: routing, bundledRuleSets: "C:\\x\\RuleSets", controller: new ConfigBuilder.Controller(19090, "s")));
    }

    [Fact]
    public void AllVpnHasNoRuleSets()
    {
        var json = ConfigBuilder.Build(ProxyLink.Parse(Reality), routing: new RoutingSettings { Profile = Profile.AllVPN, Direct = ["a.com"] });
        Assert.DoesNotContain("rule_set", json);
        Assert.DoesNotContain("a.com", json);
    }

    [Fact]
    public void UserListsAndAdsOrder()
    {
        var routing = new RoutingSettings { Direct = ["bank.ru"], BlockAds = true, BlockIPv6 = true };
        var rules = JsonNode.Parse(ConfigBuilder.Build(ProxyLink.Parse(Reality), routing: routing))!["route"]!["rules"]!.AsArray();
        Assert.Equal(6, (int)rules[2]!["ip_version"]!.GetValue<int>());
        Assert.Equal("reject", rules[3]!["action"]!.GetValue<string>());
    }

    [Fact]
    public void ParsesSubscriptions()
    {
        var plain = ProxyLink.Parse(Reality).Link + "\nhy2://p@h.example:443#x\nvmess://skip";
        var (servers, skipped) = SubscriptionParser.Servers(plain);
        Assert.Equal(2, servers.Count);
        Assert.Equal(1, skipped);
        var b64 = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(plain));
        Assert.Equal(2, SubscriptionParser.Servers(b64).Servers.Count);
        var sb = """{"outbounds":[{"type":"selector","tag":"a"},{"type":"vless","tag":"n","server":"h","server_port":1,"uuid":"u","transport":{"type":"grpc"},"tls":{"enabled":true}}]}""";
        Assert.Equal("VLESS · gRPC · TLS", SubscriptionParser.Servers(sb).Servers.Single().Summary);
    }

    [Fact]
    public void ParsesInfoHeaders()
    {
        var info = SubscriptionInfo.Parse(new Dictionary<string, string>
        {
            ["Subscription-Userinfo"] = "upload=1; download=2; total=10; expire=1767225600",
            ["Profile-Title"] = "base64:0J/RgNC40LLQtdGC",
            ["Profile-Update-Interval"] = "12",
        });
        Assert.Equal(3, info.Used);
        Assert.Equal(10, info.Total);
        Assert.Equal("Привет", info.Title);
        Assert.Equal(12, info.UpdateIntervalHours);
        Assert.NotNull(info.Expire);
    }

    [Fact]
    public void OldSettingsLoad()
    {
        var s = System.Text.Json.JsonSerializer.Deserialize<RoutingSettings>("""{"profile":"allVPN","direct":["a.com"]}""", RoutingSettings.JsonOptions)!;
        Assert.Equal(Profile.AllVPN, s.Profile);
        Assert.Equal(DnsProvider.Cloudflare, s.Dns);
        Assert.Empty(s.Presets);
    }

    [Fact]
    public void UpdateCheckPicksNewestWindowsBuild()
    {
        const string json = """
        [{"tag_name":"v1.9","draft":false,"html_url":"p9","assets":[{"name":"Kitsune-mac.zip","browser_download_url":"mac"}]},
         {"tag_name":"v1.8.1-win2","draft":false,"html_url":"p2","assets":[{"name":"Kitsune-win-x64.zip","browser_download_url":"z2"}]},
         {"tag_name":"v1.8.1-win1","draft":false,"html_url":"p1","assets":[{"name":"Kitsune-win-x64.zip","browser_download_url":"z1"}]}]
        """;
        Assert.Equal("z2", UpdateCheck.Newest(json, BuildVersion.Parse("1.8.1-win1")!.Value)!.ZipUrl);
        Assert.Null(UpdateCheck.Newest(json, BuildVersion.Parse("1.8.1-win2")!.Value));
        Assert.Equal("1.8.1-win2", UpdateCheck.Newest(json, BuildVersion.Parse("1.8.0")!.Value)!.Version);
        Assert.True(BuildVersion.Parse("v1.10")!.Value.CompareTo(BuildVersion.Parse("1.9.9-win5")!.Value) > 0);
        Assert.Null(BuildVersion.Parse("nightly"));
    }
}
