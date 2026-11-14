using System.Security.Principal;

namespace Kitsune.Services;

public sealed record Check(string Title, bool Ok, string Detail);

public static class Diagnostics
{
    public static async Task<List<Check>> RunAsync()
    {
        var core = Path.Combine(AppContext.BaseDirectory, "core");
        var checks = new List<Check>();
        using var identity = WindowsIdentity.GetCurrent();
        var admin = new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
        checks.Add(new("Права администратора", admin, admin ? "Есть" : "Нет: туннель не создать. Запустите Kitsune от имени администратора."));
        checks.Add(new("Ядро sing-box", File.Exists(Path.Combine(core, "sing-box.exe")), File.Exists(Path.Combine(core, "sing-box.exe")) ? "core\\sing-box.exe на месте" : "Нет core\\sing-box.exe: переустановите приложение."));
        checks.Add(new("Сетевой адаптер Wintun", File.Exists(Path.Combine(core, "wintun.dll")), File.Exists(Path.Combine(core, "wintun.dll")) ? "wintun.dll на месте" : "Нет core\\wintun.dll: антивирус мог удалить файл."));
        var servers = AppState.Shared.AllServers.Count();
        checks.Add(new("Серверы", servers > 0, servers > 0 ? $"Добавлено: {servers}" : "Добавьте сервер или подписку на вкладке «Серверы»."));

        var ip = await IpLookup.GetAsync();
        checks.Add(new("Интернет", ip != null, ip != null ? $"Сайты видят {ip.Ip} ({ip.Country})" : "Не удалось узнать внешний адрес: проверьте подключение."));
        var tunnel = Tunnel.Shared;
        if (tunnel.State == TunnelState.Connected && tunnel.DirectIp != null && ip != null)
        {
            var changed = tunnel.DirectIp.Ip != ip.Ip;
            checks.Add(new("Утечка IP", changed, changed ? "Адрес отличается от домашнего: трафик идёт через сервер." : "Адрес совпадает с домашним: трафик идёт мимо VPN."));
        }
        else checks.Add(new("Туннель", tunnel.State == TunnelState.Connected, tunnel.State == TunnelState.Error ? tunnel.Error ?? "Ошибка" : "Не подключён"));
        return checks;
    }
}
