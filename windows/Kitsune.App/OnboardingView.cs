using Kitsune.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Kitsune;

/// First launch: what Kitsune is, what stays direct, and where to paste the first server. Three steps with dots.
public sealed class OnboardingView : Grid
{
    readonly Action done;
    readonly StackPanel body = new() { Spacing = 14, MaxWidth = 460, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    readonly StackPanel dots = new() { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
    readonly Button back = new() { Content = "Назад" };
    readonly Button next = new() { Style = (Style)Application.Current.Resources["AccentButtonStyle"], MinWidth = 120 };
    readonly TextBox link = new() { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 90, PlaceholderText = "vless://…  hysteria2://…  или https://… (подписка)" };
    readonly TextBlock error = Ui.Text("", 12, false, "SystemFillColorCriticalBrush");
    int step;

    public OnboardingView(Action done)
    {
        this.done = done;
        RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Children.Add(body);
        var footer = new StackPanel { Spacing = 16, Margin = new Thickness(0, 0, 0, 32), HorizontalAlignment = HorizontalAlignment.Center };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
        buttons.Children.Add(back); buttons.Children.Add(next);
        footer.Children.Add(dots); footer.Children.Add(buttons);
        SetRow(footer, 1); Children.Add(footer);
        back.Click += (_, _) => { step--; Render(); };
        next.Click += async (_, _) => await NextAsync();
        Render();
    }

    async Task NextAsync()
    {
        if (step < 2) { step++; Render(); return; }
        if (!string.IsNullOrWhiteSpace(link.Text))
        {
            next.IsEnabled = false;
            var problem = await AppState.Shared.AddAsync(link.Text);
            next.IsEnabled = true;
            if (problem != null) { error.Text = problem; return; }
        }
        done();
    }

    void Render()
    {
        body.Children.Clear();
        back.Visibility = step == 0 ? Visibility.Collapsed : Visibility.Visible;
        next.Content = step == 2 ? "Готово" : "Далее";
        switch (step)
        {
            case 0:
                body.Children.Add(Ui.Fox(56, Ui.Accent));
                body.Children.Add(new TextBlock { Text = "Kitsune", FontFamily = Ui.Display, FontSize = 34, Foreground = Ui.Res("TextFillColorPrimaryBrush") });
                body.Children.Add(Wrap(Ui.Secondary("VPN, который не мешает. Российские сайты открываются как обычно, всё остальное идёт через защищённый туннель.", 14)));
                break;
            case 1:
                body.Children.Add(new TextBlock { Text = "Что работает без VPN", FontFamily = Ui.Display, FontSize = 24, Foreground = Ui.Res("TextFillColorPrimaryBrush") });
                body.Children.Add(Wrap(Ui.Secondary("Банки, маркетплейсы, Госуслуги и другие российские сервисы. Настраивать ничего не нужно, список можно изменить позже на вкладке «Маршруты».", 14)));
                var chips = new ItemsControl { ItemsPanel = (ItemsPanelTemplate)Microsoft.UI.Xaml.Markup.XamlReader.Load("<ItemsPanelTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'><VariableSizedWrapGrid Orientation='Horizontal'/></ItemsPanelTemplate>") };
                foreach (var name in new[] { "Банки", "Ozon", "Wildberries", "Госуслуги", "Яндекс", "VK", "Такси", "Доставка" })
                    chips.Items.Add(new Border { Margin = new Thickness(0, 0, 8, 8), Padding = new Thickness(14, 6, 14, 6), CornerRadius = new CornerRadius(14), Background = Ui.Res("ControlFillColorDefaultBrush"), BorderBrush = Ui.Res("ControlStrokeColorDefaultBrush"), BorderThickness = new Thickness(1), Child = Ui.Text(name, 13) });
                body.Children.Add(chips);
                break;
            default:
                body.Children.Add(new TextBlock { Text = "Добавьте сервер", FontFamily = Ui.Display, FontSize = 24, Foreground = Ui.Res("TextFillColorPrimaryBrush") });
                body.Children.Add(Wrap(Ui.Secondary("Вставьте ссылку на сервер или подписку. Kitsune запускается от имени администратора: это нужно для сетевого адаптера. Пароли и адреса остаются на этом компьютере.", 14)));
                body.Children.Add(link);
                body.Children.Add(error);
                body.Children.Add(Ui.Secondary("Можно пропустить и добавить позже на вкладке «Серверы».", 12));
                break;
        }
        dots.Children.Clear();
        for (var i = 0; i < 3; i++)
            dots.Children.Add(new Border { Width = i == step ? 20 : 8, Height = 8, CornerRadius = new CornerRadius(4), Background = i == step ? Ui.Accent : Ui.Res("TextFillColorDisabledBrush") });
    }

    static TextBlock Wrap(TextBlock text) { text.TextWrapping = TextWrapping.Wrap; return text; }
}
