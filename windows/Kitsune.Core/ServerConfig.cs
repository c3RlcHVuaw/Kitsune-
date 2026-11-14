using System.Security.Cryptography;
using System.Text;

namespace Kitsune.Core;

/// One connectable server, whatever it came from (a share link or a subscription).
public sealed class ServerConfig
{
    /// Stable across subscription refreshes: derived from the outbound itself.
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    /// "VLESS · gRPC · Reality"
    public string Summary { get; set; } = "";
    public string Host { get; set; } = "";
    public int Port { get; set; }
    /// sing-box outbound JSON, without a tag.
    public string Outbound { get; set; } = "{}";
    /// The share link it was parsed from, kept so manual servers can be edited.
    public string? Link { get; set; }

    public ServerConfig() { }

    public ServerConfig(string name, string summary, Dictionary<string, object?> outbound)
    {
        Outbound = Json.Write(outbound, indented: false);
        Id = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Outbound))).ToLowerInvariant()[..24];
        Name = name;
        Summary = summary;
        Host = outbound.GetValueOrDefault("server") as string ?? "";
        Port = outbound.GetValueOrDefault("server_port") is int p ? p : 0;
    }

    /// Country flag emoji found in the name ("🇳🇱 Amsterdam" → "🇳🇱").
    public string? Flag
    {
        get
        {
            var runes = Name.EnumerateRunes().ToArray();
            for (var i = 0; i < runes.Length - 1; i++)
                if (IsRegional(runes[i]) && IsRegional(runes[i + 1])) return runes[i].ToString() + runes[i + 1];
            return null;
        }
    }

    static bool IsRegional(Rune r) => r.Value is >= 0x1F1E6 and <= 0x1F1FF;

    /// Two-letter country code from the flag ("🇳🇱" → "NL").
    public string? CountryCode
    {
        get
        {
            var flag = Flag;
            if (flag == null) return null;
            return new string(flag.EnumerateRunes().Select(r => (char)(r.Value - 0x1F1A5)).ToArray());
        }
    }

    /// QUIC-based protocols cannot be pinged with a TCP connect.
    public bool IsUdp => Outbound.Contains("\"type\":\"hysteria2\"") || Outbound.Contains("\"type\":\"tuic\"");

    /// Name without the flag and surrounding spaces.
    public string DisplayName
    {
        get
        {
            var flag = Flag;
            if (flag == null) return Name;
            var trimmed = Name.Replace(flag, "").Trim();
            return trimmed.Length == 0 ? Name : trimmed;
        }
    }
}
