using System.Diagnostics;
using System.Net.Sockets;

namespace Kitsune.Services;

public static class Pinger
{
    public static async Task<int?> TcpAsync(string host, int port, CancellationToken token)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(TimeSpan.FromSeconds(3));
        var watch = Stopwatch.StartNew();
        try
        {
            using var client = new TcpClient();
            await client.ConnectAsync(host, port, timeout.Token);
            return (int)watch.ElapsedMilliseconds;
        }
        catch (Exception e) when (e is SocketException or OperationCanceledException) { return null; }
    }
}
