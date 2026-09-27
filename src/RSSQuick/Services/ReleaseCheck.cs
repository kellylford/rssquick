using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace RSSReaderWPF.Services
{
    /// <summary>A published release newer than the one running.</summary>
    /// <param name="Version">Three parts, as the tag has it: 1.3.0.</param>
    /// <param name="Page">The release's page on GitHub, which carries its notes and downloads.</param>
    public sealed record AvailableRelease(Version Version, Uri Page);

    /// <summary>
    /// Asks GitHub whether there is a newer release than the one running.
    /// </summary>
    /// <remarks>
    /// <para>This is how a copy that cannot update itself finds out there is something to update
    /// to: the portable ZIP, and every macOS copy. An installed Windows copy asks Velopack
    /// instead, which reads the same releases but can also download and apply them — see
    /// <c>AppUpdater</c>.</para>
    /// <para>A release only counts if it carries a download for this platform. Windows and
    /// macOS are released from the same tag, but a fix for one can go out alone, and telling a
    /// Mac user about a release with nothing in it for them sends them to a page they cannot
    /// use.</para>
    /// <para>The macOS version is <c>macos/Sources/RSSQuickCore/ReleaseCheck.swift</c>. The two
    /// answer the same questions, and their tests should change together.</para>
    /// </remarks>
    public static class ReleaseCheck
    {
        public static readonly Uri LatestReleaseApi =
            new("https://api.github.com/repos/kellylford/rssquick/releases/latest");

        private static readonly HttpClient Http = CreateClient();

        private static HttpClient CreateClient()
        {
            var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            // GitHub's API refuses requests with no User-Agent.
            client.DefaultRequestHeaders.UserAgent.ParseAdd("RSSQuick (+https://github.com/kellylford/rssquick)");
            client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
            return client;
        }

        /// <summary>
        /// The release at <paramref name="api"/>, if it is newer than <paramref name="current"/>
        /// and carries an asset whose name ends with <paramref name="assetSuffix"/>.
        /// </summary>
        /// <returns>
        /// Null when there is nothing newer — and also when the question could not be answered.
        /// No network, a GitHub outage or a rate limit are not worth interrupting anyone for; the
        /// next launch asks again.
        /// </returns>
        public static async Task<AvailableRelease?> CheckAsync(
            Uri api, Version current, string assetSuffix, CancellationToken cancellationToken = default)
        {
            try
            {
                using var response = await Http.GetAsync(api, cancellationToken).ConfigureAwait(false);
                if (!response.IsSuccessStatusCode) return null;

                var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
                return Parse(json, current, assetSuffix);
            }
            catch (Exception ex) when (ex is HttpRequestException or OperationCanceledException)
            {
                return null;
            }
        }

        /// <summary>
        /// Reads a GitHub release document. Everything <see cref="CheckAsync"/> decides, without
        /// the network.
        /// </summary>
        public static AvailableRelease? Parse(string json, Version current, string assetSuffix)
        {
            try
            {
                using var document = JsonDocument.Parse(json);
                var root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object) return null;

                // /releases/latest never returns either, but a document from anywhere else might.
                if (IsTrue(root, "draft") || IsTrue(root, "prerelease")) return null;

                if (!root.TryGetProperty("tag_name", out var tag) || tag.ValueKind != JsonValueKind.String) return null;
                if (!root.TryGetProperty("html_url", out var page) || page.ValueKind != JsonValueKind.String) return null;

                if (TryParseTag(tag.GetString()!) is not { } version) return null;
                if (version <= Normalize(current)) return null;
                if (!Uri.TryCreate(page.GetString(), UriKind.Absolute, out var pageUri)
                    || pageUri.Scheme != Uri.UriSchemeHttps) return null;
                if (!HasAsset(root, assetSuffix)) return null;

                return new AvailableRelease(version, pageUri);
            }
            catch (JsonException)
            {
                return null;
            }
        }

        /// <summary>"v1.3.0" or "1.3.0" to a three-part version; anything else to null.</summary>
        internal static Version? TryParseTag(string tag)
        {
            var text = tag.StartsWith('v') || tag.StartsWith('V') ? tag[1..] : tag;
            return Version.TryParse(text, out var version) ? Normalize(version) : null;
        }

        /// <summary>
        /// Three parts, always.
        /// </summary>
        /// <remarks>
        /// The assembly reports 1.2.0.0 and the tag says 1.2.0, and <see cref="Version"/> treats
        /// a missing part as less than zero — so compared as they stand, 1.2.0 is older than the
        /// 1.2.0.0 that is running, and 1.2.0.0 is newer than the 1.2.0 on GitHub.
        /// </remarks>
        internal static Version Normalize(Version version) =>
            new(version.Major, version.Minor, Math.Max(version.Build, 0));

        private static bool IsTrue(JsonElement root, string name) =>
            root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;

        private static bool HasAsset(JsonElement root, string suffix)
        {
            if (!root.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array) return false;

            foreach (var asset in assets.EnumerateArray())
            {
                if (asset.ValueKind == JsonValueKind.Object
                    && asset.TryGetProperty("name", out var name)
                    && name.ValueKind == JsonValueKind.String
                    && name.GetString()!.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }
    }
}
