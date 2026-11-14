using Kitsune.Core;
using Kitsune.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace Kitsune.Pages;

public sealed partial class ServersPage : Page
{
    string query = "";

    public ServersPage()
    {
        InitializeComponent();
        Loaded += (_, _) => { AppState.Shared.Changed += OnChanged; Refresh(); };
        Unloaded += (_, _) => AppState.Shared.Changed -= OnChanged;
    }

    void OnChanged() => Ui.OnUi(this, Refresh);

    void OnSearchChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        query = sender.Text.Trim();
        Refresh();
    }

    async void OnPing(object sender, RoutedEventArgs e)
    {
        PingButton.IsEnabled = false;
        await AppState.Shared.PingAllAsync();
        PingButton.IsEnabled = true;
    }

    async void OnAdd(object sender, RoutedEventArgs e)
    {
        var box = new TextBox { PlaceholderText = "vless://…  hysteria2://…  или https://… (подписка)", AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 96 };
        var message = Ui.Text("", 12, false, "SystemFillColorCriticalBrush");
        var content = new StackPanel { Spacing = 12, MinWidth = 420 };
        content.Children.Add(Ui.Secondary("Ссылка на сервер (по одной в строке) или адрес подписки."));
        content.Children.Add(box);
        content.Children.Add(message);
        var dialog = new ContentDialog { XamlRoot = XamlRoot, Title = "Добавить", Content = content, PrimaryButtonText = "Добавить", CloseButtonText = "Отмена", DefaultButton = ContentDialogButton.Primary };
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            var error = await AppState.Shared.AddAsync(box.Text);
            if (error != null) { message.Text = error; args.Cancel = true; }
            deferral.Complete();
        };
        await dialog.ShowAsync();
    }

    void Refresh()
    {
        var state = AppState.Shared;
        Subs.Children.Clear();
        foreach (var sub in state.Subscriptions) Subs.Children.Add(SubscriptionCard(sub));

        List.Children.Clear();
        var servers = state.AllServers.Where(s => query.Length == 0 || s.Name.Contains(query, StringComparison.CurrentCultureIgnoreCase)).ToList();
        Empty.Visibility = state.AllServers.Any() ? Visibility.Collapsed : Visibility.Visible;
        if (servers.Count == 0) return;

        var auto = Row(null, "Авто | Самый быстрый", "Выбирается по пингу", null, state.IsAuto);
        auto.Tapped += (_, _) => state.Select(null);
        var rows = new StackPanel { Spacing = 2 };
        if (query.Length == 0) rows.Children.Add(auto);
        foreach (var server in servers)
        {
            var row = Row(server.CountryCode, server.DisplayName, server.Summary, state.Pings.TryGetValue(server.Id, out var ms) ? ms : null, !state.IsAuto && state.SelectedId == server.Id);
            row.Tapped += (_, _) => state.Select(server.Id);
            row.RightTapped += (_, _) => { if (state.Manual.Any(m => m.Id == server.Id)) state.RemoveServer(server.Id); };
            rows.Children.Add(row);
        }
        List.Children.Add(Ui.Card(rows, 4));
    }

    static Grid Row(string? code, string name, string summary, int? ping, bool selected)
    {
        var grid = new Grid { Height = 52, Padding = new Thickness(12, 0, 12, 0), ColumnSpacing = 12, CornerRadius = new CornerRadius(4) };
        grid.Background = selected ? Ui.Res("SubtleFillColorSecondaryBrush") : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var flag = Ui.Flag(code); flag.VerticalAlignment = VerticalAlignment.Center; grid.Children.Add(flag);
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(Ui.Text(name, 14)); texts.Children.Add(Ui.Secondary(summary, 11));
        Grid.SetColumn(texts, 1); grid.Children.Add(texts);
        if (ping is { } value)
        {
            var label = Ui.Text($"{value} мс", 12, false, value < 150 ? "SystemFillColorSuccessBrush" : value < 400 ? "SystemFillColorCautionBrush" : "SystemFillColorCriticalBrush");
            label.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(label, 2); grid.Children.Add(label);
        }
        if (selected)
            grid.Children.Add(new Microsoft.UI.Xaml.Shapes.Rectangle { Width = 3, Height = 16, RadiusX = 1.5, RadiusY = 1.5, Fill = Ui.Accent, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(-12, 0, 0, 0) });
        return grid;
    }

    Border SubscriptionCard(SubscriptionEntry sub)
    {
        var info = sub.Info;
        var stack = new StackPanel { Spacing = 10 };
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        title.Children.Add(Ui.Text(sub.Name, 14, true));
        var ago = DateTimeOffset.Now - sub.Updated;
        title.Children.Add(Ui.Secondary($"{sub.Servers.Count} серверов · обновлено {(ago.TotalMinutes < 1 ? "только что" : ago.TotalHours < 1 ? $"{(int)ago.TotalMinutes} мин назад" : ago.TotalDays < 1 ? $"{(int)ago.TotalHours} ч назад" : $"{(int)ago.TotalDays} дн назад")}"));
        header.Children.Add(title);
        if (info.Expire is { } expire) { var until = Ui.Secondary($"до {expire:d MMM}"); Grid.SetColumn(until, 1); header.Children.Add(until); }
        stack.Children.Add(header);

        if (info.Total is > 0 && info.Used is { } used)
            stack.Children.Add(new ProgressBar { Minimum = 0, Maximum = info.Total.Value, Value = Math.Min(used, info.Total.Value) });
        var footer = new Grid();
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.Children.Add(Ui.Secondary(info.Used is { } u ? (info.Total is > 0 ? $"{Ui.Bytes(u)} из {Ui.Bytes(info.Total.Value)}" : $"{Ui.Bytes(u)} · без лимита") : "Подписка", 12));
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        void AddLink(string title, string? url)
        {
            if (url == null) return;
            var button = new Button { Content = title };
            button.Click += async (_, _) => await Launcher.LaunchUriAsync(new Uri(url));
            buttons.Children.Add(button);
        }
        AddLink("Поддержка", info.SupportUrl); AddLink("Сайт", info.WebPageUrl);
        var refresh = new Button { Content = "Обновить" };
        refresh.Click += async (_, _) => { refresh.IsEnabled = false; await AppState.Shared.RefreshAsync(sub); AppState.Shared.Save(); };
        buttons.Children.Add(refresh);
        var remove = new Button { Content = "Удалить" };
        remove.Click += (_, _) => AppState.Shared.RemoveSubscription(sub);
        buttons.Children.Add(remove);
        Grid.SetColumn(buttons, 1); footer.Children.Add(buttons);
        stack.Children.Add(footer);
        return Ui.Card(stack);
    }
}
