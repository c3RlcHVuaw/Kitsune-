using Kitsune.Pages;
using Kitsune.Services;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Kitsune;

public sealed partial class MainWindow : Window
{
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
        Closed += (_, _) => Tunnel.Shared.Stop(); // never leave the core running with no window to stop it
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
            _ => typeof(HomePage),
        };
        Host.Navigate(page);
    }
}
