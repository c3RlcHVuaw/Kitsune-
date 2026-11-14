using System.Diagnostics;

namespace Kitsune.Services;

/// Start with Windows through a scheduled task: it can run elevated at logon without a UAC prompt, which a Run-key entry cannot.
public static class Autostart
{
    const string Task = "Kitsune";

    static int Run(string args)
    {
        using var p = Process.Start(new ProcessStartInfo("schtasks.exe", args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
        if (p == null) return -1;
        p.WaitForExit(10_000);
        return p.ExitCode;
    }

    public static bool IsOn => Run($"/query /tn {Task}") == 0;

    public static bool Set(bool on) => on
        ? Run($"/create /tn {Task} /tr \"\\\"{System.IO.Path.Combine(AppInfo.InstallDir, "Kitsune.exe")}\\\"\" /sc onlogon /rl highest /f") == 0
        : Run($"/delete /tn {Task} /f") == 0;
}
