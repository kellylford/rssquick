using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace RSSQuick.Tests;

/// <summary>
/// A throwaway HTTP server on a loopback port, serving canned feeds.
/// </summary>
/// <remarks>
/// <para>Lets the real <c>FeedLoader</c> run against a server whose behaviour the test controls,
/// so timeouts, the concurrency cap and partial failure are covered on every build rather than
/// only when someone opts into hitting third-party servers.</para>
/// <para>A raw <see cref="TcpListener"/> rather than <c>HttpListener</c>, which needs a URL
/// reservation or administrator rights on Windows. A stub that only answers GET needs very little
/// of HTTP, and this way the tests need no setup on the machine running them.</para>
/// </remarks>
internal sealed class LocalFeedServer : IDisposable
{
    private readonly TcpListener _listener;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly ConcurrentDictionary<string, Response> _routes = new();
    private readonly ConcurrentDictionary<string, int> _requestCounts = new();

    private int _inFlight;
    private int _peakInFlight;

    /// <summary>How many requests were being served at the busiest moment.</summary>
    public int PeakConcurrentRequests => Volatile.Read(ref _peakInFlight);

    public LocalFeedServer()
    {
        // Port 0 asks the OS for a free one, so parallel test runs cannot collide.
        _listener = new TcpListener(IPAddress.Loopback, 0);
        _listener.Start();

        BaseAddress = new Uri($"http://127.0.0.1:{((IPEndPoint)_listener.LocalEndpoint).Port}/");

        _ = Task.Run(AcceptLoopAsync);
    }

    public Uri BaseAddress { get; }

    /// <summary>Serves <paramref name="body"/> at <paramref name="path"/>.</summary>
    public Uri Serve(
        string path,
        string body,
        HttpStatusCode status = HttpStatusCode.OK,
        string contentType = "application/rss+xml",
        TimeSpan? delay = null)
    {
        _routes[Normalize(path)] = new Response(status, contentType, Encoding.UTF8.GetBytes(body), delay, Hang: false);
        return new Uri(BaseAddress, path);
    }

    /// <summary>
    /// Accepts the connection and then never answers, the way a black-holed server behaves.
    /// </summary>
    public Uri ServeNothing(string path)
    {
        _routes[Normalize(path)] = new Response(HttpStatusCode.OK, "text/plain", [], null, Hang: true);
        return new Uri(BaseAddress, path);
    }

    /// <summary>A path nothing is registered for, which answers 404.</summary>
    public Uri Missing(string path) => new(BaseAddress, path);

    public int RequestsFor(string path) => _requestCounts.GetValueOrDefault(Normalize(path));

    private static string Normalize(string path) => "/" + path.TrimStart('/');

    private async Task AcceptLoopAsync()
    {
        while (!_shutdown.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await _listener.AcceptTcpClientAsync(_shutdown.Token);
            }
            catch (Exception) when (_shutdown.IsCancellationRequested)
            {
                return;
            }
            catch (Exception)
            {
                continue;
            }

            _ = Task.Run(() => ServeAsync(client));
        }
    }

    private async Task ServeAsync(TcpClient client)
    {
        var current = Interlocked.Increment(ref _inFlight);

        // Lock-free high-water mark: retry until our value is recorded or someone recorded higher.
        int peak;
        while (current > (peak = Volatile.Read(ref _peakInFlight)))
            Interlocked.CompareExchange(ref _peakInFlight, current, peak);

        try
        {
            using (client)
            {
                await using var stream = client.GetStream();

                var path = await ReadRequestPathAsync(stream);
                if (path is null) return;

                _requestCounts.AddOrUpdate(path, 1, (_, count) => count + 1);

                if (!_routes.TryGetValue(path, out var response))
                {
                    await WriteAsync(stream, HttpStatusCode.NotFound, "text/plain", "no such feed"u8.ToArray());
                    return;
                }

                if (response.Delay is { } delay)
                    await Task.Delay(delay, _shutdown.Token);

                if (response.Hang)
                {
                    // Hold the connection open, unanswered, until the test is done. The client's
                    // own timeout is what should end this.
                    await Task.Delay(Timeout.InfiniteTimeSpan, _shutdown.Token);
                    return;
                }

                await WriteAsync(stream, response.Status, response.ContentType, response.Body);
            }
        }
        catch (Exception)
        {
            // A client that gave up mid-exchange is exactly what several of these tests arrange.
        }
        finally
        {
            Interlocked.Decrement(ref _inFlight);
        }
    }

    /// <summary>Reads the request line and discards the headers. Returns the path.</summary>
    private static async Task<string?> ReadRequestPathAsync(Stream stream)
    {
        var reader = new StreamReader(stream, Encoding.ASCII, leaveOpen: true);

        var requestLine = await reader.ReadLineAsync();
        if (string.IsNullOrEmpty(requestLine)) return null;

        // "GET /path HTTP/1.1"
        var parts = requestLine.Split(' ');
        if (parts.Length < 2) return null;

        while (await reader.ReadLineAsync() is { Length: > 0 }) { /* headers */ }

        return parts[1];
    }

    private static async Task WriteAsync(Stream stream, HttpStatusCode status, string contentType, byte[] body)
    {
        var header = Encoding.ASCII.GetBytes(
            $"HTTP/1.1 {(int)status} {status}\r\n" +
            $"Content-Type: {contentType}\r\n" +
            $"Content-Length: {body.Length}\r\n" +
            "Connection: close\r\n" +
            "\r\n");

        await stream.WriteAsync(header);
        await stream.WriteAsync(body);
        await stream.FlushAsync();
    }

    public void Dispose()
    {
        _shutdown.Cancel();
        _listener.Stop();
        _shutdown.Dispose();
    }

    private sealed record Response(
        HttpStatusCode Status,
        string ContentType,
        byte[] Body,
        TimeSpan? Delay,
        bool Hang);
}

/// <summary>Feed XML the tests serve.</summary>
internal static class SampleFeed
{
    public static string WithItems(string channelTitle, params string[] headlines)
    {
        var items = new StringBuilder();
        foreach (var headline in headlines)
        {
            items.Append($"""
                  <item>
                    <title>{headline}</title>
                    <link>https://example.com/{Uri.EscapeDataString(headline)}</link>
                  </item>
                """);
        }

        return $"""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
              <channel>
                <title>{channelTitle}</title>
            {items}
              </channel>
            </rss>
            """;
    }
}
