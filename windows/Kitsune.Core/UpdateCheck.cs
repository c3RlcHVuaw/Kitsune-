using System.Text.RegularExpressions;
using System.Text.Json;

namespace Kitsune.Core;

/// Windows builds are GitHub releases tagged `v1.8.1-win1`: app version plus a Windows build counter.
public readonly record struct BuildVersion(Version App, int Build) : IComparable<BuildVersion>
{
    static readonly Regex Pattern = new(@"^v?(\d+(?:\.\d+){1,2})(?:-win(\d+))?$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public static BuildVersion? Parse(string tag)
    {
        var m = Pattern.Match(tag.Trim());
        return m.Success ? new BuildVersion(Version.Parse(m.Groups[1].Value), m.Groups[2].Success ? int.Parse(m.Groups[2].Value) : 0) : null;
    }

    public int CompareTo(BuildVersion other) => App != other.App ? App.CompareTo(other.App) : Build.CompareTo(other.Build);
    public override string ToString() => Build > 0 ? $"{App}-win{Build}" : App.ToString();
}

public sealed record UpdateInfo(string Version, string ZipUrl, string PageUrl);

public static class UpdateCheck
{
    /// Picks the newest release that ships `Kitsune-win-x64.zip` and is newer than `current`; null when up to date.
    public static UpdateInfo? Newest(string releasesJson, BuildVersion current)
    {
        using var doc = JsonDocument.Parse(releasesJson);
        UpdateInfo? best = null;
        BuildVersion? bestVersion = null;
        foreach (var release in doc.RootElement.EnumerateArray())
        {
            if (release.TryGetProperty("draft", out var draft) && draft.GetBoolean()) continue;
            if (BuildVersion.Parse(release.GetProperty("tag_name").GetString() ?? "") is not { } version) continue;
            string? zip = null;
            foreach (var asset in release.GetProperty("assets").EnumerateArray())
                if (asset.GetProperty("name").GetString() == "Kitsune-win-x64.zip") zip = asset.GetProperty("browser_download_url").GetString();
            if (zip == null || version.CompareTo(current) <= 0) continue;
            if (bestVersion == null || version.CompareTo(bestVersion.Value) > 0)
            {
                bestVersion = version;
                best = new UpdateInfo(version.ToString(), zip, release.GetProperty("html_url").GetString() ?? "");
            }
        }
        return best;
    }
}
