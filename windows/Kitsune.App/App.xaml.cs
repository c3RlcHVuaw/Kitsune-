using Kitsune.Services;
using Microsoft.UI.Xaml;

namespace Kitsune;

public partial class App : Application
{
    public static MainWindow? Window { get; private set; }

    /// `Kitsune.exe --page=servers` opens that tab (used by CI to take screenshots).
    public static string? StartPage { get; } = Environment.GetCommandLineArgs().FirstOrDefault(a => a.StartsWith("--page="))?[7..];

    public App() => InitializeComponent();

    /// Really exits (the window's close button only hides to the tray): stops the core first.
    public static void Quit()
    {
        Tunnel.Shared.Stop();
        Window?.DisposeTray();
        Current.Exit();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        AppState.Shared.Load();
        Window = new MainWindow();
        Window.Activate();
        Updater.Shared.Start();
        if (AppState.Shared.AutoConnect && AppState.Shared.Selected() != null) _ = AppState.Shared.ConnectAsync();
    }
}
