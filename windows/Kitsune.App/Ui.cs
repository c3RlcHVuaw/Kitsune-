using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;

namespace Kitsune;

/// Small builders shared by the pages: cards, labels and the fox, all on Fluent theme resources.
public static class Ui
{
    public static Brush Res(string key) => (Brush)Application.Current.Resources[key];
    public static FontFamily Display => (FontFamily)Application.Current.Resources["DisplayFont"];

    public static Border Card(UIElement child, double padding = 16) => new()
    {
        Background = Res("CardBackgroundFillColorDefaultBrush"),
        BorderBrush = Res("CardStrokeColorDefaultBrush"),
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(8),
        Padding = new Thickness(padding),
        Child = child,
    };

    public static TextBlock Text(string text, double size = 14, bool bold = false, string brush = "TextFillColorPrimaryBrush") => new()
    {
        Text = text, FontSize = size, Foreground = Res(brush),
        FontWeight = bold ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    public static TextBlock Secondary(string text, double size = 12) => Text(text, size, false, "TextFillColorSecondaryBrush");

    public static Brush Accent => Res("AccentFillColorDefaultBrush");

    /// The fox mark (same polygon as FoxHead in the macOS app, 100×100 grid).
    public static Microsoft.UI.Xaml.Shapes.Path Fox(double size, Brush fill) => new()
    {
        Width = size, Height = size, Fill = fill, Stretch = Stretch.Uniform,
        Data = (Geometry)Microsoft.UI.Xaml.Markup.XamlBindingHelper.ConvertValue(typeof(Geometry), "M10,10 L38,36 L62,36 L90,10 L90,52 L50,92 L10,52 Z"),
    };

    public static Image Flag(string? code, double width = 24)
    {
        var image = new Image { Width = width, Height = width * 0.7, Stretch = Stretch.UniformToFill };
        if (!string.IsNullOrEmpty(code)) image.Source = FlagSource(code);
        return image;
    }

    static ImageSource? FlagSource(string code)
    {
        var path = System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "flags", code.ToLowerInvariant() + ".png");
        return System.IO.File.Exists(path) ? new BitmapImage(new Uri(path)) : null;
    }

    public static string Bytes(long value)
    {
        string[] units = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
        double v = value; var i = 0;
        while (v >= 1000 && i < units.Length - 1) { v /= 1000; i++; }
        return (i == 0 ? $"{v:0}" : v < 10 ? $"{v:0.0}" : $"{v:0}") .Replace('.', ',') + " " + units[i];
    }

    public static string Rate(long value) => Bytes(value) + "/с";

    public static void OnUi(UIElement element, Action action)
    {
        if (element.DispatcherQueue.HasThreadAccess) action(); else element.DispatcherQueue.TryEnqueue(() => action());
    }
}
