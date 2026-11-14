using System.Text.Json;

namespace Kitsune.Services;

public sealed record IpInfo(string Ip, string Country, string Code);

/// Public address and country as websites see it (through the tunnel when it is up).
public static class IpLookup
{
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(8) };

    public static async Task<IpInfo?> GetAsync()
    {
        try
        {
            using var doc = JsonDocument.Parse(await Http.GetStringAsync("https://ipwho.is/"));
            var root = doc.RootElement;
            if (root.TryGetProperty("success", out var ok) && !ok.GetBoolean()) return null;
            return new IpInfo(root.GetProperty("ip").GetString() ?? "", root.GetProperty("country").GetString() ?? "", (root.GetProperty("country_code").GetString() ?? "").ToLowerInvariant());
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or JsonException or KeyNotFoundException) { return null; }
    }
}
