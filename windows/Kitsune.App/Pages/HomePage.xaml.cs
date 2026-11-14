using Kitsune.Core;
using Kitsune.Services;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace Kitsune.Pages;

public sealed partial class HomePage : Page
{
    readonly Tunnel tunnel = Tunnel.Shared;
    readonly DispatcherTimer clock = new() { Interval = TimeSpan.FromSeconds(1) };

    Ellipse ring = new();
    Microsoft.UI.Xaml.Shapes.Path fox = new();
    TextBlock title = new(), subtitle = new(), error = new();
    Button action = new();
    ToggleSwitch russia = new();
    readonly StackPanel info = new(), speed = new(), apps = new();
    readonly StackPanel bars = new() { Orientation = Orientation.Horizontal, Spacing = 4, Height = 40 };
    bool syncing;

    public HomePage()
    {
        InitializeComponent();
        BuildHero();
        Side.Children.Add(Section("Подключение", info));
        Side.Children.Add(Section("Скорость", speed));
        Side.Children.Add(Section("Кто потребляет", apps));
        Loaded += (_, _) => { tunnel.Changed += OnChanged; AppState.Shared.Changed += OnChanged; clock.Tick += (_, _) => Refresh(); clock.Start(); Refresh(); };
        Unloaded += (_, _) => { tunnel.Changed -= OnChanged; AppState.Shared.Changed -= OnChanged; clock.Stop(); };
    }

    void OnChanged() => Ui.OnUi(this, Refresh);

    static Border Section(string heading, UIElement body)
    {
        var stack = new StackPanel { Spacing = 12 };
        stack.Children.Add(Ui.Text(heading, 14, true));
        stack.Children.Add(body);
        return Ui.Card(stack);
    }

    void BuildHero()
    {
        var disc = new Grid { Width = 260, Height = 260, HorizontalAlignment = HorizontalAlignment.Center };
        disc.Children.Add(new Ellipse { Width = 250, Height = 250, Stroke = Ui.Res("CardStrokeColorDefaultBrush"), StrokeThickness = 1 });
        ring = new Ellipse { Width = 230, Height = 230, StrokeThickness = 3 };
        disc.Children.Add(ring);
        disc.Children.Add(new Ellipse { Width = 200, Height = 200, Fill = Ui.Res("ControlFillColorDefaultBrush") });
        fox = Ui.Fox(72, Ui.Res("TextFillColorPrimaryBrush"));
        disc.Children.Add(fox);

        title = new TextBlock { FontFamily = Ui.Display, FontSize = 26, HorizontalAlignment = HorizontalAlignment.Center, Foreground = Ui.Res("TextFillColorPrimaryBrush") };
        subtitle = new TextBlock { FontSize = 13, HorizontalAlignment = HorizontalAlignment.Center, Foreground = Ui.Res("TextFillColorSecondaryBrush") };
        error = new TextBlock { FontSize = 12, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, Foreground = Ui.Res("SystemFillColorCriticalBrush"), MaxWidth = 340 };
        action = new Button { HorizontalAlignment = HorizontalAlignment.Center, MinWidth = 104 };
        action.Click += async (_, _) => await OnActionAsync();
        russia = new ToggleSwitch { OnContent = "Россия напрямую", OffContent = "Россия напрямую", HorizontalAlignment = HorizontalAlignment.Center };
        russia.Toggled += async (_, _) => await OnRussiaToggledAsync();

        var stack = new StackPanel { Spacing = 14, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        foreach (var child in new UIElement[] { disc, title, subtitle, error, action, russia }) stack.Children.Add(child);
        HeroCard.Child = null;
        HeroCard.Background = Ui.Res("CardBackgroundFillColorDefaultBrush");
        HeroCard.BorderBrush = Ui.Res("CardStrokeColorDefaultBrush");
        HeroCard.BorderThickness = new Thickness(1);
        HeroCard.CornerRadius = new CornerRadius(8);
        HeroCard.Child = stack;
    }

    async Task OnActionAsync()
    {
        if (tunnel.State == TunnelState.Connected) { tunnel.Stop(); return; }
        if (tunnel.State == TunnelState.Connecting) return;
        await AppState.Shared.ConnectAsync();
    }

    async Task OnRussiaToggledAsync()
    {
        if (syncing) return;
        AppState.Shared.Routing.Profile = russia.IsOn ? Profile.RussiaDirect : Profile.AllVPN;
        AppState.Shared.Save();
        var state = AppState.Shared;
        await tunnel.RestartAsync(state.Selected(), state.AllServers.ToList(), state.Routing);
    }

    void Refresh()
    {
        var state = tunnel.State;
        var connected = state == TunnelState.Connected;
        ring.Stroke = connected ? Ui.Accent : state == TunnelState.Error ? Ui.Res("SystemFillColorCriticalBrush") : Ui.Res("ControlStrokeColorDefaultBrush");
        fox.Fill = connected ? Ui.Accent : Ui.Res("TextFillColorPrimaryBrush");
        title.Text = state switch { TunnelState.Connected => "Защищено", TunnelState.Connecting => "Подключаемся…", TunnelState.Error => "Ошибка", _ => "Не защищено" };
        var server = tunnel.Server ?? AppState.Shared.Selected();
        var name = AppState.Shared.IsAuto ? "Авто | Самый быстрый" : server?.DisplayName ?? "Сервер не выбран";
        subtitle.Text = connected && tunnel.ConnectedAt is { } at ? $"{name}  ·  {Elapsed(DateTime.Now - at)}" : name;
        error.Text = tunnel.Error ?? "";
        error.Visibility = string.IsNullOrEmpty(tunnel.Error) ? Visibility.Collapsed : Visibility.Visible;
        action.Content = connected ? "Отключить" : state == TunnelState.Connecting ? "Подождите…" : "Подключить";
        action.IsEnabled = state != TunnelState.Connecting;
        if (connected) action.Style = null; else action.Style = (Style)Application.Current.Resources["AccentButtonStyle"];

        syncing = true;
        russia.IsOn = AppState.Shared.Routing.Profile == Profile.RussiaDirect;
        syncing = false;

        info.Children.Clear();
        var ip = tunnel.Ip;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        row.Children.Add(Ui.Flag(ip?.Code));
        var texts = new StackPanel();
        texts.Children.Add(Ui.Text(connected ? ip?.Ip ?? "…" : "—", 14, true));
        texts.Children.Add(Ui.Secondary(connected && ip != null ? $"{ip.Country} · сайты видят этот IP" : "Подключитесь, чтобы увидеть"));
        row.Children.Add(texts);
        info.Children.Add(row);
        if (connected && ip != null)
        {
            var changed = tunnel.DirectIp == null || tunnel.DirectIp.Ip != ip.Ip;
            var status = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            status.Children.Add(new Ellipse { Width = 8, Height = 8, VerticalAlignment = VerticalAlignment.Center, Fill = Ui.Res(changed ? "SystemFillColorSuccessBrush" : "SystemFillColorCautionBrush") });
            status.Children.Add(Ui.Secondary(changed ? "IP сменился" : "IP не изменился, проверьте сервер"));
            info.Children.Add(status);
        }

        speed.Children.Clear();
        var columns = new Grid { ColumnSpacing = 12 };
        columns.ColumnDefinitions.Add(new ColumnDefinition()); columns.ColumnDefinitions.Add(new ColumnDefinition());
        columns.Children.Add(SpeedColumn("↓ Загрузка", tunnel.DownRate, tunnel.DownTotal, true, 0));
        columns.Children.Add(SpeedColumn("↑ Отдача", tunnel.UpRate, tunnel.UpTotal, false, 1));
        speed.Children.Add(columns);
        bars.Children.Clear();
        var max = Math.Max(tunnel.History.DefaultIfEmpty(0).Max(), 1);
        foreach (var value in tunnel.History.TakeLast(30))
            bars.Children.Add(new Border { Width = 4, Height = Math.Max(3, 38.0 * value / max), VerticalAlignment = VerticalAlignment.Bottom, CornerRadius = new CornerRadius(2), Background = Ui.Accent });
        speed.Children.Add(bars);

        apps.Children.Clear();
        if (tunnel.Apps.Count == 0) apps.Children.Add(Ui.Secondary(connected ? "Пока тихо" : "Данные появятся после подключения"));
        var top = tunnel.Apps.FirstOrDefault()?.BytesPerSecond ?? 1;
        foreach (var app in tunnel.Apps)
        {
            var line = new Grid { ColumnSpacing = 10, Height = 28 };
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(64) });
            line.Children.Add(Ui.Text(app.Name, 13));
            var bar = new ProgressBar { Width = 60, Minimum = 0, Maximum = 1, Value = (double)app.BytesPerSecond / top, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(bar, 1); line.Children.Add(bar);
            var rate = Ui.Secondary(Ui.Rate(app.BytesPerSecond)); rate.TextAlignment = TextAlignment.Right;
            Grid.SetColumn(rate, 2); line.Children.Add(rate);
            apps.Children.Add(line);
        }
    }

    static string Elapsed(TimeSpan t) => t.TotalHours >= 1 ? $"{(int)t.TotalHours}:{t.Minutes:00}:{t.Seconds:00}" : $"{t.Minutes:00}:{t.Seconds:00}";

    static StackPanel SpeedColumn(string caption, long rate, long total, bool accent, int column)
    {
        var stack = new StackPanel { Spacing = 2 };
        stack.Children.Add(Ui.Secondary(caption));
        var number = new TextBlock { Text = Ui.Rate(rate), FontFamily = Ui.Display, FontSize = 17, Foreground = accent ? Ui.Accent : Ui.Res("TextFillColorPrimaryBrush") };
        stack.Children.Add(number);
        stack.Children.Add(Ui.Secondary(Ui.Bytes(total), 11));
        Grid.SetColumn(stack, column);
        return stack;
    }
}
