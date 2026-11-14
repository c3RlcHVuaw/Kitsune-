using Kitsune.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.System;

namespace Kitsune.Pages;

public sealed partial class SettingsPage : Page
{
    public SettingsPage()
    {
        InitializeComponent();
        Root.Children.Add(Ui.Text("Настройки", 28, true));

        var auto = new ToggleSwitch { Header = "Подключаться при запуске", IsOn = AppState.Shared.AutoConnect, OnContent = "Вкл.", OffContent = "Откл." };
        auto.Toggled += (_, _) => AppState.Shared.AutoConnect = auto.IsOn;
        var stack = new StackPanel { Spacing = 12 };
        stack.Children.Add(Ui.Text("Подключение", 14, true));
        stack.Children.Add(auto);
        var login = new ToggleSwitch { Header = "Запускать вместе с Windows", IsOn = Autostart.IsOn, OnContent = "Вкл.", OffContent = "Откл." };
        login.Toggled += (_, _) => { if (!Autostart.Set(login.IsOn)) login.IsOn = Autostart.IsOn; };
        stack.Children.Add(login);
        stack.Children.Add(Ui.Secondary("Kitsune запускается от имени администратора: это нужно для сетевого адаптера и маршрутов."));
        Root.Children.Add(Ui.Card(stack));

        var refresh = new Button { Content = "Обновить подписки" };
        refresh.Click += async (_, _) => { refresh.IsEnabled = false; await AppState.Shared.RefreshAllAsync(); refresh.IsEnabled = true; };
        var data = new StackPanel { Spacing = 12 };
        data.Children.Add(Ui.Text("Данные", 14, true));
        data.Children.Add(refresh);
        var folder = new Button { Content = "Открыть папку с данными" };
        folder.Click += async (_, _) => await Launcher.LaunchFolderPathAsync(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Kitsune"));
        data.Children.Add(folder);
        var diagnose = new Button { Content = "Диагностика" };
        diagnose.Click += async (_, _) => await ShowDiagnosticsAsync();
        data.Children.Add(diagnose);
        Root.Children.Add(Ui.Card(data));

        var about = new StackPanel { Spacing = 8 };
        about.Children.Add(Ui.Text("О программе", 14, true));
        about.Children.Add(Ui.Secondary($"Kitsune для Windows {AppInfo.Current} · ядро sing-box"));
        var update = new Button { Content = "Проверить обновления" };
        var updateNote = Ui.Secondary("");
        update.Click += async (_, _) =>
        {
            update.IsEnabled = false;
            await Updater.Shared.CheckAsync();
            updateNote.Text = Updater.Shared.Info is { } info ? $"Доступна версия {info.Version}, кнопка обновления на главной." : "Установлена последняя версия.";
            update.IsEnabled = true;
        };
        about.Children.Add(update);
        about.Children.Add(updateNote);
        var repo = new HyperlinkButton { Content = "Исходный код и релизы", NavigateUri = new Uri("https://github.com/c3RlcHVuaw/Kitsune-") };
        about.Children.Add(repo);
        Root.Children.Add(Ui.Card(about));
    }

    async Task ShowDiagnosticsAsync()
    {
        var list = new StackPanel { Spacing = 10, MinWidth = 440 };
        var progress = new ProgressRing { IsActive = true, Width = 24, Height = 24, HorizontalAlignment = HorizontalAlignment.Left };
        list.Children.Add(progress);
        var dialog = new ContentDialog { XamlRoot = XamlRoot, Title = "Диагностика", Content = new ScrollViewer { Content = list, MaxHeight = 420 }, CloseButtonText = "Готово" };
        var show = dialog.ShowAsync().AsTask();
        foreach (var check in await Diagnostics.RunAsync())
        {
            var row = new Grid { ColumnSpacing = 10 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(new FontIcon { Glyph = check.Ok ? "\uE73E" : "\uE711", FontSize = 14, Foreground = Ui.Res(check.Ok ? "SystemFillColorSuccessBrush" : "SystemFillColorCriticalBrush"), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 3, 0, 0) });
            var texts = new StackPanel();
            texts.Children.Add(Ui.Text(check.Title, 14, true));
            var detail = Ui.Secondary(check.Detail); detail.TextWrapping = TextWrapping.Wrap; texts.Children.Add(detail);
            Grid.SetColumn(texts, 1); row.Children.Add(texts);
            list.Children.Add(row);
        }
        var tail = Tunnel.Shared.LogTail();
        if (tail.Length > 0)
        {
            list.Children.Add(Ui.Text("Журнал sing-box", 14, true));
            list.Children.Add(new TextBox { Text = tail, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"), FontSize = 11, MaxHeight = 160 });
        }
        list.Children.Remove(progress);
        await show;
    }
}
