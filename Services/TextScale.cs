using System;
using Microsoft.Win32;

namespace RSSReaderWPF.Services
{
    /// <summary>
    /// The Windows "Make text bigger" setting, as a multiplier.
    /// </summary>
    /// <remarks>
    /// <para>Settings, Accessibility, Text size. It is a separate control from display scaling: a
    /// user who wants larger text without everything else growing reaches for this one, and it is
    /// the setting low-vision users are most often told to use.</para>
    /// <para>WPF does not honour it. Unlike display scaling, which the per-monitor DPI awareness in
    /// app.manifest handles, nothing in WPF reads this value, so a WPF window ignores it entirely
    /// and stays at the message font size however large the user asked for. Reading it here and
    /// applying it to the window's font size is the whole of the support.</para>
    /// <para>Read once at startup. Changing the setting takes effect the next time RSS Quick
    /// starts, rather than live.</para>
    /// </remarks>
    public static class TextScale
    {
        /// <summary>Below this, Windows is not scaling text at all.</summary>
        private const int MinimumPercent = 100;

        /// <summary>Windows' own slider stops at 225%; allow headroom without accepting nonsense.</summary>
        private const int MaximumPercent = 400;

        /// <summary>The current multiplier, or 1.0 when text scaling is off or unreadable.</summary>
        public static double Current => FromRegistryValue(ReadRawValue());

        private static object? ReadRawValue()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Accessibility");
                return key?.GetValue("TextScaleFactor");
            }
            catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException)
            {
                // A locked-down profile should mean ordinary text, not a crash on startup.
                return null;
            }
        }

        /// <summary>
        /// Turns the raw registry value into a multiplier. Separated from reading the registry so
        /// the clamping can be tested without touching the machine's actual settings.
        /// </summary>
        internal static double FromRegistryValue(object? raw)
        {
            if (raw is not int percent) return 1.0;
            if (percent < MinimumPercent || percent > MaximumPercent) return 1.0;

            return percent / 100.0;
        }
    }
}
