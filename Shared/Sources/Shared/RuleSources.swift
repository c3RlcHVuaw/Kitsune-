/// Remote sing-box rule-sets for the "Russia direct" profile.
/// Source: runetfreedom/russia-v2ray-rules-dat (release branch, rebuilt daily). Swap URLs here to change provider.
public enum RuleSources {
    static let base = "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box"

    /// (tag, path) — domain lists first, then IP list.
    static let domainSets = [
        ("geosite-category-ru", "rule-set-geosite/geosite-category-ru.srs"),
        ("geosite-category-gov-ru", "rule-set-geosite/geosite-category-gov-ru.srs"),
        ("geosite-ru-available-only-inside", "rule-set-geosite/geosite-ru-available-only-inside.srs"),
    ]
    /// Ads and trackers, used only when "block ads" is on.
    static let adsSet = ("geosite-category-ads-all", "rule-set-geosite/geosite-category-ads-all.srs")
    static let ipSets = [("geoip-ru", "rule-set-geoip/geoip-ru.srs")]

    /// Whole Russian TLDs: .ru, .рф (punycode), .su.
    static let russianTLDs = ["ru", "xn--p1ai", "su"]

    /// Russian resolver used for direct domains, reached outside the tunnel.
    static let russianDNS = "77.88.8.8"
}
