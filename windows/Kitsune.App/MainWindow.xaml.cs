using Kitsune.Pages;
using Kitsune.Services;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Kitsune;

public sealed partial class MainWindow : Window
{
    readonly Tray tray;

    public void DisposeTray() => tray.Dispose();

    public void Reveal() { AppWindow.Show(); Activate(); }

    void ShowOnboarding()
    {
        Overlay.Visibility = Visibility.Visible;
        Overlay.Children.Add(new OnboardingView(() => { AppState.Shared.OnboardingDone = true; Overlay.Children.Clear(); Overlay.Visibility = Visibility.Collapsed; }));
    }

    public MainWindow()
    {
        InitializeComponent();
        Title = "Kitsune";
        SystemBackdrop = new MicaBackdrop();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(TitleBar);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1000, 680));
        TitleFox.Children.Add(Ui.Fox(16, Ui.Accent));
        if (Content is FrameworkElement root) root.RequestedTheme = ElementTheme.Dark;
        AppWindow.SetIcon(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Kitsune.ico"));
        // The close button hides the window to the tray; the VPN keeps running. "Выход" in the tray menu quits for real.
        AppWindow.Closing += (_, args) => { args.Cancel = true; AppWindow.Hide(); };
        tray = new Tray(this);
        if (!AppState.Shared.OnboardingDone) ShowOnboarding();
    }

    void OnNavLoaded(object sender, RoutedEventArgs e)
    {
        if (Nav.SettingsItem is NavigationViewItem settings) settings.Content = "Настройки";
        Nav.SelectedItem = Nav.MenuItems[0];
    }

    void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var page = args.IsSettingsSelected ? typeof(SettingsPage) : (args.SelectedItemContainer?.Tag as string) switch
        {
            "servers" => typeof(ServersPage),
            "routes" => typeof(RoutesPage),
            "history" => typeof(HistoryPage),
            _ => typeof(HomePage),
        };
        Host.Navigate(page);
    }
}
