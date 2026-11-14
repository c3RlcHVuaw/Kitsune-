using Kitsune.Pages;
using Kitsune.Services;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Kitsune;

public sealed partial class MainWindow : Window
{
    readonly Tray? tray;

    public void DisposeTray() => tray?.Dispose();

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
        // Screenshot runs (--page=…) pin the window to the top-left corner of a small screen.
        if (App.StartPage != null) AppWindow.MoveAndResize(new Windows.Graphics.RectInt32(0, 0, 1000, 690));
        else AppWindow.Resize(new Windows.Graphics.SizeInt32(1000, 680));
        TitleFox.Children.Add(Ui.Fox(16, Ui.Accent));
        if (Content is FrameworkElement root) root.RequestedTheme = ElementTheme.Dark;
        AppWindow.SetIcon(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Kitsune.ico"));
        // The close button hides the window to the tray; the VPN keeps running. "Выход" in the tray menu quits for real.
        AppWindow.Closing += (_, args) => { args.Cancel = true; AppWindow.Hide(); };
        try { tray = new Tray(this); } catch (Exception) { tray = null; } // no notification area (e.g. a bare session): run without the icon
        if (!AppState.Shared.OnboardingDone) ShowOnboarding();
    }

    void OnNavLoaded(object sender, RoutedEventArgs e)
    {
        if (Nav.SettingsItem is NavigationViewItem settings) settings.Content = "Настройки";
        Nav.SelectedItem = App.StartPage == "settings" ? Nav.SettingsItem
            : Nav.MenuItems.OfType<NavigationViewItem>().FirstOrDefault(i => (string)i.Tag == App.StartPage) ?? Nav.MenuItems[0];
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
