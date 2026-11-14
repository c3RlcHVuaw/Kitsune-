using System.Diagnostics;
using System.IO.Compression;
using Kitsune.Core;

namespace Kitsune.Services;

public enum UpdateState { Idle, Available, Installing, Failed }

/// Looks for a newer Windows release on GitHub every few hours; one click downloads it, swaps the files and restarts.
public sealed class Updater
{
    public static Updater Shared { get; } = new();

    const string Feed = "https://api.github.com/repos/c3RlcHVuaw/Kitsune-/releases?per_page=20";
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(5) };

    public UpdateState State { get; private set; }
    public UpdateInfo? Info { get; private set; }
    public string? Error { get; private set; }
    public event Action? Changed;
    bool started;

    public void Start()
    {
        if (started) return;
        started = true;
        _ = Task.Run(async () =>
        {
            while (true)
            {
                if (State != UpdateState.Installing) await CheckAsync();
                await Task.Delay(TimeSpan.FromHours(4));
            }
        });
    }

    public async Task CheckAsync()
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, Feed);
            request.Headers.UserAgent.ParseAdd("Kitsune-Windows/" + AppInfo.Current);
            using var response = await Http.SendAsync(request);
            if (!response.IsSuccessStatusCode) return;
            Info = UpdateCheck.Newest(await response.Content.ReadAsStringAsync(), AppInfo.Current);
            State = Info == null ? UpdateState.Idle : UpdateState.Available;
            Changed?.Invoke();
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException) { }
    }

    /// Downloads the zip, then a detached PowerShell waits for this process to exit, copies the files over and starts the app again.
    public async Task InstallAsync()
    {
        if (Info == null || State == UpdateState.Installing) return;
        State = UpdateState.Installing; Error = null; Changed?.Invoke();
        try
        {
            var work = Path.Combine(Path.GetTempPath(), "kitsune-update-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(work);
            var zip = Path.Combine(work, "update.zip");
            await using (var file = File.Create(zip)) await (await Http.GetStreamAsync(Info.ZipUrl)).CopyToAsync(file);
            var fresh = Path.Combine(work, "new");
            ZipFile.ExtractToDirectory(zip, fresh);
            if (!File.Exists(Path.Combine(fresh, "Kitsune.exe"))) throw new InvalidDataException("В архиве нет Kitsune.exe.");

            var script = Path.Combine(work, "update.ps1");
            await File.WriteAllTextAsync(script, $"""
                Wait-Process -Id {Environment.ProcessId} -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                robocopy '{fresh}' '{AppInfo.InstallDir}' /E /NFL /NDL /NJH /NJS /R:10 /W:1 | Out-Null
                Start-Process '{Path.Combine(AppInfo.InstallDir, "Kitsune.exe")}'
                Remove-Item -Recurse -Force '{work}' -ErrorAction SilentlyContinue
                """);
            Process.Start(new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{script}\"") { UseShellExecute = false, CreateNoWindow = true });
            App.Quit();
        }
        catch (Exception e)
        {
            State = UpdateState.Failed; Error = e.Message; Changed?.Invoke();
        }
    }
}
