using Kitsune.Services;
using Microsoft.UI.Xaml;

namespace Kitsune;

public partial class App : Application
{
    public static MainWindow? Window { get; private set; }

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        AppState.Shared.Load();
        Window = new MainWindow();
        Window.Activate();
        if (AppState.Shared.AutoConnect && AppState.Shared.Selected() != null) _ = AppState.Shared.ConnectAsync();
    }
}
