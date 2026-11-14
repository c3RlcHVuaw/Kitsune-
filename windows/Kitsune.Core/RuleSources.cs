namespace Kitsune.Core;

/// Remote sing-box rule-sets for the "Russia direct" profile (runetfreedom/russia-v2ray-rules-dat, rebuilt daily).
public static class RuleSources
{
    public const string Base = "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box";

    public static readonly (string Tag, string Path)[] DomainSets =
    [
        ("geosite-category-ru", "rule-set-geosite/geosite-category-ru.srs"),
        ("geosite-category-gov-ru", "rule-set-geosite/geosite-category-gov-ru.srs"),
        ("geosite-ru-available-only-inside", "rule-set-geosite/geosite-ru-available-only-inside.srs"),
    ];

    /// Ads and trackers, used only when "block ads" is on.
    public static readonly (string Tag, string Path) AdsSet = ("geosite-category-ads-all", "rule-set-geosite/geosite-category-ads-all.srs");
    public static readonly (string Tag, string Path)[] IpSets = [("geoip-ru", "rule-set-geoip/geoip-ru.srs")];

    /// Whole Russian TLDs: .ru, .рф (punycode), .su.
    public static readonly string[] RussianTlds = ["ru", "xn--p1ai", "su"];

    /// Russian resolver used for direct domains, reached outside the tunnel.
    public const string RussianDns = "77.88.8.8";
}
