using System.Reflection;
using Kitsune.Core;

namespace Kitsune.Services;

public static class AppInfo
{
    /// "1.8.1-win2" from the assembly's informational version (the SDK may append "+commit").
    public static BuildVersion Current { get; } = BuildVersion.Parse(
        (Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0").Split('+')[0])
        ?? new BuildVersion(new Version(0, 0), 0);

    public static string InstallDir => AppContext.BaseDirectory.TrimEnd('\\', '/');
}
