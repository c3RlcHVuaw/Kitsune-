using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using Kitsune.Core;

namespace Kitsune.Services;

public enum TunnelState { Idle, Connecting, Connected, Error }

public sealed record AppRate(string Name, long BytesPerSecond);

public sealed class SessionRecord
{
    public DateTimeOffset Start { get; set; }
    public int Seconds { get; set; }
    public string Server { get; set; } = "";
    public string Country { get; set; } = "";
    public long Up { get; set; }
    public long Down { get; set; }
}

/// Runs the bundled sing-box (core\sing-box.exe + wintun.dll) as a child process and watches it through the local Clash API.
public sealed class Tunnel
{
    public static Tunnel Shared { get; } = new();

    const int ApiPort = 19090;
    static readonly string WorkDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Kitsune");
    static string CoreDir => Path.Combine(AppContext.BaseDirectory, "core");

    public TunnelState State { get; private set; }
    public string? Error { get; private set; }
    public ServerConfig? Server { get; private set; }
    public DateTime? ConnectedAt { get; private set; }
    public IpInfo? Ip { get; private set; }
    public IpInfo? DirectIp { get; private set; }
    public long UpTotal { get; private set; }
    public long DownTotal { get; private set; }
    public long UpRate { get; private set; }
    public long DownRate { get; private set; }
    public List<AppRate> Apps { get; private set; } = [];
    public Queue<long> History { get; } = new();

    public event Action? Changed;
    public event Action<SessionRecord>? SessionEnded;

    Process? process;
    CancellationTokenSource? cts;
    HttpClient? api;
    readonly Queue<string> log = new();

    void Set(TunnelState state, string? error = null)
    {
        State = state;
        Error = error;
        Changed?.Invoke();
    }

    public async Task StartAsync(ServerConfig? server, IReadOnlyList<ServerConfig> all, RoutingSettings routing)
    {
        if (State is TunnelState.Connecting or TunnelState.Connected) return;
        if (server == null) { Set(TunnelState.Error, "Сначала добавьте сервер."); return; }
        Server = server;
        Set(TunnelState.Connecting);
        try
        {
            var exe = Path.Combine(CoreDir, "sing-box.exe");
            if (!File.Exists(exe)) throw new FileNotFoundException("Не найден core\\sing-box.exe рядом с приложением.");
            DirectIp = await IpLookup.GetAsync();

            Directory.CreateDirectory(WorkDir);
            var secret = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
            var config = ConfigBuilder.Build(server, all, routing, Path.Combine(CoreDir, "RuleSets"), new ConfigBuilder.Controller(ApiPort, secret), findProcess: true);
            var configPath = Path.Combine(WorkDir, "config.json");
            await File.WriteAllTextAsync(configPath, config);

            var info = new ProcessStartInfo(exe, $"run -c \"{configPath}\" -D \"{WorkDir}\"")
            {
                WorkingDirectory = CoreDir, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
            };
            log.Clear();
            process = Process.Start(info) ?? throw new InvalidOperationException("sing-box не запустился.");
            process.OutputDataReceived += (_, e) => Remember(e.Data);
            process.ErrorDataReceived += (_, e) => Remember(e.Data);
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            cts = new CancellationTokenSource();
            api = new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{ApiPort}"), Timeout = Timeout.InfiniteTimeSpan };
            api.DefaultRequestHeaders.Add("Authorization", $"Bearer {secret}");
            await WaitForApiAsync(cts.Token);

            ConnectedAt = DateTime.Now;
            UpTotal = DownTotal = 0;
            History.Clear();
            Set(TunnelState.Connected);
            _ = WatchTrafficAsync(cts.Token);
            _ = WatchAppsAsync(cts.Token);
            _ = process.WaitForExitAsync().ContinueWith(_ => { if (State == TunnelState.Connected) Fail("Соединение оборвалось: sing-box завершился."); });
            Ip = await IpLookup.GetAsync();
            Changed?.Invoke();
        }
        catch (Exception e)
        {
            Kill();
            Set(TunnelState.Error, e.Message);
        }
    }

    void Remember(string? line)
    {
        if (string.IsNullOrWhiteSpace(line)) return;
        lock (log) { log.Enqueue(line); while (log.Count > 12) log.Dequeue(); }
    }

    async Task WaitForApiAsync(CancellationToken token)
    {
        for (var i = 0; i < 60; i++)
        {
            if (process is { HasExited: true }) throw new InvalidOperationException(Hint());
            try { using var r = await api!.GetAsync("/version", token); if (r.IsSuccessStatusCode) return; }
            catch (HttpRequestException) { }
            await Task.Delay(500, token);
        }
        throw new TimeoutException("sing-box не ответил за 30 секунд. " + Hint());
    }

    string Hint()
    {
        string[] lines; lock (log) lines = log.ToArray();
        var last = lines.LastOrDefault(l => l.Contains("FATAL", StringComparison.OrdinalIgnoreCase) || l.Contains("ERROR", StringComparison.OrdinalIgnoreCase)) ?? lines.LastOrDefault() ?? "";
        return last.Length > 300 ? last[..300] : last;
    }

    void Fail(string message)
    {
        Kill();
        Set(TunnelState.Error, message);
    }

    async Task WatchTrafficAsync(CancellationToken token)
    {
        try
        {
            using var stream = await api!.GetStreamAsync("/traffic", token);
            using var reader = new StreamReader(stream);
            while (!token.IsCancellationRequested && await reader.ReadLineAsync(token) is { } line)
            {
                using var doc = JsonDocument.Parse(line);
                UpRate = doc.RootElement.GetProperty("up").GetInt64();
                DownRate = doc.RootElement.GetProperty("down").GetInt64();
                UpTotal += UpRate; DownTotal += DownRate;
                History.Enqueue(DownRate + UpRate);
                while (History.Count > 30) History.Dequeue();
                Changed?.Invoke();
            }
        }
        catch (Exception e) when (e is OperationCanceledException or HttpRequestException or IOException or JsonException) { }
    }

    /// Per-program speed: sum of byte growth of each connection, grouped by the process that owns it.
    async Task WatchAppsAsync(CancellationToken token)
    {
        var previous = new Dictionary<string, long>();
        try
        {
            while (!token.IsCancellationRequested)
            {
                await Task.Delay(2000, token);
                using var response = await api!.GetAsync("/connections", token);
                using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
                var current = new Dictionary<string, long>();
                var perApp = new Dictionary<string, long>();
                foreach (var c in doc.RootElement.GetProperty("connections").EnumerateArray())
                {
                    var id = c.GetProperty("id").GetString() ?? "";
                    var bytes = c.GetProperty("upload").GetInt64() + c.GetProperty("download").GetInt64();
                    current[id] = bytes;
                    var path = c.GetProperty("metadata").TryGetProperty("processPath", out var p) ? p.GetString() : null;
                    if (string.IsNullOrEmpty(path)) continue;
                    var delta = bytes - previous.GetValueOrDefault(id, bytes);
                    var name = Path.GetFileNameWithoutExtension(path);
                    perApp[name] = perApp.GetValueOrDefault(name) + Math.Max(delta, 0) / 2;
                }
                previous = current;
                Apps = perApp.Where(p => p.Value > 0).OrderByDescending(p => p.Value).Take(3).Select(p => new AppRate(p.Key, p.Value)).ToList();
                Changed?.Invoke();
            }
        }
        catch (Exception e) when (e is OperationCanceledException or HttpRequestException or JsonException or KeyNotFoundException) { }
    }

    public string LogTail() { lock (log) return string.Join(Environment.NewLine, log); }

    void Kill()
    {
        if (ConnectedAt is { } started)
            SessionEnded?.Invoke(new SessionRecord { Start = started, Seconds = (int)(DateTime.Now - started).TotalSeconds, Server = Server?.DisplayName ?? "", Country = Ip?.Code ?? "", Up = UpTotal, Down = DownTotal });
        cts?.Cancel();
        try { if (process is { HasExited: false }) { process.Kill(entireProcessTree: true); process.WaitForExit(3000); } }
        catch (InvalidOperationException) { }
        process = null;
        api?.Dispose(); api = null;
        ConnectedAt = null; Ip = null; Apps = []; UpRate = DownRate = 0; History.Clear();
    }

    public void Stop()
    {
        Kill();
        Set(TunnelState.Idle);
    }

    /// Applies a changed server or routing while connected: restart the core with the new config.
    public async Task RestartAsync(ServerConfig? server, IReadOnlyList<ServerConfig> all, RoutingSettings routing)
    {
        if (State != TunnelState.Connected) return;
        Stop();
        await StartAsync(server, all, routing);
    }
}
