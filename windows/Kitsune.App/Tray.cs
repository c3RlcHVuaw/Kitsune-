using System.Windows.Input;
using H.NotifyIcon;
using Kitsune.Services;
using Microsoft.UI.Xaml.Controls;

namespace Kitsune;

/// Notification-area icon: left click opens the window, the menu connects, disconnects or quits.
public sealed class Tray : IDisposable
{
    sealed class Command(Action run) : ICommand
    {
        public event EventHandler? CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => run();
    }

    readonly TaskbarIcon icon;
    readonly MenuFlyoutItem status = new() { IsEnabled = false };
    readonly MenuFlyoutItem toggle = new();

    public Tray(MainWindow window)
    {
        var open = new MenuFlyoutItem { Text = "Открыть Kitsune" };
        open.Click += (_, _) => window.Reveal();
        toggle.Click += async (_, _) =>
        {
            if (Tunnel.Shared.State == TunnelState.Connected) Tunnel.Shared.Stop(); else await AppState.Shared.ConnectAsync();
        };
        var quit = new MenuFlyoutItem { Text = "Выйти" };
        quit.Click += (_, _) => App.Quit();

        var menu = new MenuFlyout();
        menu.Items.Add(status);
        menu.Items.Add(toggle);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(open);
        menu.Items.Add(quit);

        icon = new TaskbarIcon
        {
            ToolTipText = "Kitsune",
            ContextMenuMode = ContextMenuMode.PopupMenu,
            ContextFlyout = menu,
            NoLeftClickDelay = true,
            LeftClickCommand = new Command(window.Reveal),
            Icon = new System.Drawing.Icon(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Kitsune.ico")),
        };
        icon.ForceCreate();
        Tunnel.Shared.Changed += () => window.DispatcherQueue.TryEnqueue(Refresh);
        Refresh();
    }

    void Refresh()
    {
        var state = Tunnel.Shared.State;
        status.Text = state switch { TunnelState.Connected => "Защищено", TunnelState.Connecting => "Подключаемся…", TunnelState.Error => "Ошибка подключения", _ => "Не защищено" };
        toggle.Text = state == TunnelState.Connected ? "Отключить" : "Подключить";
        toggle.IsEnabled = state != TunnelState.Connecting;
        icon.ToolTipText = "Kitsune · " + status.Text;
    }

    public void Dispose() => icon.Dispose();
}
