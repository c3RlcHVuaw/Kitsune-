using System.Net.Http.Headers;
using System.Text.Json;
using Kitsune.Core;

namespace Kitsune.Services;

public sealed class SubscriptionEntry
{
    public string Url { get; set; } = "";
    public string Name { get; set; } = "";
    public SubscriptionInfo Info { get; set; } = new();
    public List<ServerConfig> Servers { get; set; } = [];
    public DateTimeOffset Updated { get; set; }
}

sealed class SavedState
{
    public List<ServerConfig> Manual { get; set; } = [];
    public List<SubscriptionEntry> Subscriptions { get; set; } = [];
    public string? SelectedId { get; set; }
    public RoutingSettings Routing { get; set; } = new();
    public bool AutoConnect { get; set; }
}

/// Everything the user has set up: servers, subscriptions, routing. Persisted as JSON in %AppData%\Kitsune.
public sealed class AppState
{
    public static AppState Shared { get; } = new();

    static readonly string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Kitsune");
    static string FilePath => Path.Combine(Dir, "state.json");
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };

    SavedState data = new();
    public event Action? Changed;

    public List<ServerConfig> Manual => data.Manual;
    public List<SubscriptionEntry> Subscriptions => data.Subscriptions;
    public IEnumerable<ServerConfig> AllServers => data.Manual.Concat(data.Subscriptions.SelectMany(s => s.Servers)).DistinctBy(s => s.Id);
    public RoutingSettings Routing => data.Routing;
    public string? SelectedId => data.SelectedId;
    public Dictionary<string, int> Pings { get; } = [];

    public bool AutoConnect
    {
        get => data.AutoConnect;
        set { data.AutoConnect = value; Save(); }
    }

    public void Load()
    {
        try { if (File.Exists(FilePath)) data = JsonSerializer.Deserialize<SavedState>(File.ReadAllText(FilePath), RoutingSettings.JsonOptions) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException) { data = new(); }
    }

    public void Save()
    {
        Directory.CreateDirectory(Dir);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(data, RoutingSettings.JsonOptions));
        Changed?.Invoke();
    }

    public void Select(string? id) { data.SelectedId = id; Save(); }

    /// The chosen server; with none chosen ("Авто"), the one with the lowest known ping, else the first.
    public ServerConfig? Selected()
    {
        var all = AllServers.ToList();
        if (data.SelectedId != null && all.FirstOrDefault(s => s.Id == data.SelectedId) is { } chosen) return chosen;
        return all.OrderBy(s => Pings.GetValueOrDefault(s.Id, int.MaxValue)).FirstOrDefault();
    }

    public bool IsAuto => data.SelectedId == null || AllServers.All(s => s.Id != data.SelectedId);

    public void RemoveServer(string id)
    {
        data.Manual.RemoveAll(s => s.Id == id);
        foreach (var sub in data.Subscriptions) sub.Servers.RemoveAll(s => s.Id == id);
        if (data.SelectedId == id) data.SelectedId = null;
        Save();
    }

    public void RemoveSubscription(SubscriptionEntry sub)
    {
        data.Subscriptions.Remove(sub);
        Save();
    }

    /// Adds share links (one per line) or downloads a subscription. Returns a user-facing error, or null on success.
    public async Task<string?> AddAsync(string input)
    {
        var text = input.Trim();
        if (text.Length == 0) return "Вставьте ссылку на сервер или подписку.";
        try
        {
            if (text.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || text.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                var sub = data.Subscriptions.FirstOrDefault(s => s.Url == text) ?? new SubscriptionEntry { Url = text };
                var error = await RefreshAsync(sub);
                if (error != null) return error;
                if (!data.Subscriptions.Contains(sub)) data.Subscriptions.Add(sub);
                Save();
                return null;
            }
            var (servers, skipped) = SubscriptionParser.Servers(text);
            if (servers.Count == 0) return skipped > 0 ? "Эта ссылка не поддерживается." : "Не удалось разобрать ссылку.";
            foreach (var s in servers.Where(s => data.Manual.All(m => m.Id != s.Id))) data.Manual.Add(s);
            Save();
            return null;
        }
        catch (Exception e) { return e.Message; }
    }

    public async Task<string?> RefreshAsync(SubscriptionEntry sub)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, sub.Url);
            request.Headers.UserAgent.Add(new ProductInfoHeaderValue("Kitsune", "1.8"));
            using var response = await Http.SendAsync(request);
            if (!response.IsSuccessStatusCode) return $"Подписка ответила кодом {(int)response.StatusCode}.";
            var headers = response.Headers.Concat(response.Content.Headers).ToDictionary(h => h.Key, h => string.Join(",", h.Value));
            var (servers, _) = SubscriptionParser.Servers(await response.Content.ReadAsStringAsync());
            if (servers.Count == 0) return "В подписке нет поддерживаемых серверов.";
            sub.Info = SubscriptionInfo.Parse(headers);
            sub.Servers = servers;
            sub.Updated = DateTimeOffset.Now;
            sub.Name = sub.Info.Title ?? new Uri(sub.Url).Host;
            return null;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or UriFormatException) { return "Не удалось скачать подписку: " + e.Message; }
    }

    public async Task RefreshAllAsync()
    {
        foreach (var sub in data.Subscriptions.ToList()) await RefreshAsync(sub);
        Save();
    }

    /// TCP connect time to every TCP-based server, in parallel. QUIC servers (Hysteria2, TUIC) are skipped.
    public async Task PingAllAsync()
    {
        Pings.Clear();
        await Parallel.ForEachAsync(AllServers.Where(s => !s.IsUdp).ToList(), new ParallelOptions { MaxDegreeOfParallelism = 24 }, async (s, ct) =>
        {
            var ms = await Pinger.TcpAsync(s.Host, s.Port, ct);
            if (ms != null) lock (Pings) Pings[s.Id] = ms.Value;
        });
        Changed?.Invoke();
    }

    public Task ConnectAsync() => Tunnel.Shared.StartAsync(Selected(), AllServers.ToList(), data.Routing);
}
