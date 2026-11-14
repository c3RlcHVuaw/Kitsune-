using Kitsune.Core;
using Kitsune.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Kitsune.Pages;

public sealed partial class RoutesPage : Page
{
    static readonly (Profile Profile, string Title, string Hint)[] Profiles =
    [
        (Profile.RussiaDirect, "Россия напрямую", "Российские сайты и сервисы открываются без VPN, остальное идёт через туннель."),
        (Profile.AllVPN, "Всё через VPN", "Весь трафик идёт через сервер, кроме локальной сети."),
        (Profile.Custom, "Свои списки", "Решают только ваши списки ниже, остальное через VPN."),
    ];
    static readonly (RoutePreset Preset, string Title)[] Presets =
        [(RoutePreset.Streaming, "Стриминг"), (RoutePreset.Games, "Игры"), (RoutePreset.Messengers, "Мессенджеры")];

    DispatcherTimer? apply;

    public RoutesPage()
    {
        InitializeComponent();
        Build();
        Unloaded += (_, _) => { if (apply?.IsEnabled == true) Apply(); };
    }

    RoutingSettings Routing => AppState.Shared.Routing;

    /// Edits are saved at once; the running tunnel restarts once the user stops changing things.
    void Changed()
    {
        AppState.Shared.Save();
        apply ??= new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        apply.Tick -= OnApply; apply.Tick += OnApply;
        apply.Stop(); apply.Start();
    }

    void OnApply(object? sender, object e) => Apply();

    void Apply()
    {
        apply?.Stop();
        var s = AppState.Shared;
        _ = Tunnel.Shared.RestartAsync(s.Selected(), s.AllServers.ToList(), s.Routing);
    }

    static Border Group(string title, params UIElement[] rows)
    {
        var stack = new StackPanel { Spacing = 12 };
        stack.Children.Add(Ui.Text(title, 14, true));
        foreach (var row in rows) stack.Children.Add(row);
        return Ui.Card(stack);
    }

    void Build()
    {
        Root.Children.Add(Ui.Text("Маршруты", 28, true));

        var hint = Ui.Secondary(Profiles.First(p => p.Profile == Routing.Profile).Hint, 12);
        hint.TextWrapping = TextWrapping.Wrap;
        var selector = new RadioButtons { MaxColumns = 3 };
        foreach (var (profile, title, _) in Profiles) selector.Items.Add(new RadioButton { Content = title, Tag = profile });
        selector.SelectedIndex = Array.FindIndex(Profiles, p => p.Profile == Routing.Profile);
        selector.SelectionChanged += (_, _) =>
        {
            if (selector.SelectedIndex < 0) return;
            Routing.Profile = Profiles[selector.SelectedIndex].Profile;
            hint.Text = Profiles[selector.SelectedIndex].Hint;
            Changed();
        };
        Root.Children.Add(Group("Профиль", selector, hint));

        var ads = new ToggleSwitch { Header = "Блокировать рекламу и трекеры", IsOn = Routing.BlockAds, OnContent = "Вкл.", OffContent = "Откл." };
        ads.Toggled += (_, _) => { Routing.BlockAds = ads.IsOn; Changed(); };
        var v6 = new ToggleSwitch { Header = "Блокировать IPv6", IsOn = Routing.BlockIPv6, OnContent = "Вкл.", OffContent = "Откл." };
        v6.Toggled += (_, _) => { Routing.BlockIPv6 = v6.IsOn; Changed(); };
        var dns = new ComboBox { Header = "DNS через туннель", MinWidth = 200 };
        foreach (var provider in Enum.GetValues<DnsProvider>()) dns.Items.Add(provider.Title());
        dns.SelectedIndex = (int)Routing.Dns;
        dns.SelectionChanged += (_, _) => { if (dns.SelectedIndex >= 0) { Routing.Dns = (DnsProvider)dns.SelectedIndex; Changed(); } };
        Root.Children.Add(Group("Защита", ads, v6, dns));

        var presetRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
        foreach (var (preset, title) in Presets)
        {
            var box = new CheckBox { Content = title, IsChecked = Routing.Presets.Contains(preset) };
            box.Click += (_, _) => { if (box.IsChecked == true) Routing.Presets.Add(preset); else Routing.Presets.Remove(preset); Changed(); };
            presetRow.Children.Add(box);
        }
        Root.Children.Add(Group("Всегда через VPN: готовые наборы", presetRow));

        Root.Children.Add(ListGroup("Всегда напрямую", "Домены и IP, по одному в строке: bank.ru, 10.0.0.0/8", Routing.Direct));
        Root.Children.Add(ListGroup("Всегда через VPN", "Домены и IP, по одному в строке", Routing.Proxy));
        Root.Children.Add(ListGroup("Программы напрямую", "Имена процессов: telegram.exe", Routing.DirectApps));
        Root.Children.Add(ListGroup("Программы через VPN", "Имена процессов: chrome.exe", Routing.ProxyApps));
    }

    Border ListGroup(string title, string placeholder, List<string> target)
    {
        var box = new TextBox { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 72, PlaceholderText = placeholder, Text = string.Join("\r", target) };
        var note = Ui.Text("", 12, false, "SystemFillColorCautionBrush");
        box.LostFocus += (_, _) =>
        {
            var lines = box.Text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
            var invalid = lines.Count(l => !l.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && RouteEntry.Parse(l) == null && !placeholder.Contains(".exe"));
            note.Text = invalid > 0 ? $"Строк, которые не удалось разобрать: {invalid}. Они будут пропущены." : "";
            target.Clear(); target.AddRange(lines);
            Changed();
        };
        return Group(title, box, note);
    }
}
