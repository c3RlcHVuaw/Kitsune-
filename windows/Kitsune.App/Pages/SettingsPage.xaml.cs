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
        Root.Children.Add(Ui.Card(data));

        var about = new StackPanel { Spacing = 8 };
        about.Children.Add(Ui.Text("О программе", 14, true));
        about.Children.Add(Ui.Secondary($"Kitsune для Windows {typeof(SettingsPage).Assembly.GetName().Version?.ToString(3)} · ядро sing-box"));
        var repo = new HyperlinkButton { Content = "Исходный код и релизы", NavigateUri = new Uri("https://github.com/c3RlcHVuaw/Kitsune-") };
        about.Children.Add(repo);
        Root.Children.Add(Ui.Card(about));
    }
}
