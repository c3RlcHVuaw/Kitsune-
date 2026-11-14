using Kitsune.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Kitsune.Pages;

public sealed partial class HistoryPage : Page
{
    public HistoryPage()
    {
        InitializeComponent();
        Root.Children.Add(Ui.Text("История", 28, true));
        var sessions = AppState.Shared.Sessions;
        if (sessions.Count == 0)
        {
            Root.Children.Add(Ui.Secondary("Здесь появятся ваши подключения: когда, куда и сколько трафика.", 14));
            return;
        }
        var hours = sessions.Sum(s => s.Seconds) / 3600.0;
        var summary = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 32 };
        summary.Children.Add(Stat($"{hours:0.#}".Replace('.', ','), "часов под защитой"));
        summary.Children.Add(Stat(sessions.Count.ToString(), "подключений"));
        summary.Children.Add(Stat(Ui.Bytes(sessions.Sum(s => s.Down + s.Up)), "трафика"));
        Root.Children.Add(Ui.Card(summary, 20));

        var rows = new StackPanel { Spacing = 2 };
        foreach (var s in sessions.Take(100))
        {
            var row = new Grid { Height = 52, Padding = new Thickness(12, 0, 12, 0), ColumnSpacing = 12 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var flag = Ui.Flag(s.Country); flag.VerticalAlignment = VerticalAlignment.Center; row.Children.Add(flag);
            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            texts.Children.Add(Ui.Text(s.Server.Length > 0 ? s.Server : "Сервер", 14));
            texts.Children.Add(Ui.Secondary($"{s.Start.LocalDateTime:d MMM, HH:mm} · {Duration(s.Seconds)}", 11));
            Grid.SetColumn(texts, 1); row.Children.Add(texts);
            var traffic = Ui.Secondary($"↓ {Ui.Bytes(s.Down)}   ↑ {Ui.Bytes(s.Up)}", 12); traffic.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(traffic, 2); row.Children.Add(traffic);
            rows.Children.Add(row);
        }
        Root.Children.Add(Ui.Card(rows, 4));
    }

    static StackPanel Stat(string value, string caption)
    {
        var stack = new StackPanel { Spacing = 2 };
        stack.Children.Add(new TextBlock { Text = value, FontFamily = Ui.Display, FontSize = 24, Foreground = Ui.Accent });
        stack.Children.Add(Ui.Secondary(caption));
        return stack;
    }

    static string Duration(int seconds) => seconds >= 3600 ? $"{seconds / 3600} ч {seconds % 3600 / 60} мин" : seconds >= 60 ? $"{seconds / 60} мин" : $"{seconds} с";
}
