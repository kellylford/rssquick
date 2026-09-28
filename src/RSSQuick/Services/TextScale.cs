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
        /// The sizes Ctrl+Plus and Ctrl+Minus step through, on top of the Windows setting.
        /// </summary>
        /// <remarks>
        /// The same steps as the Mac's View menu (<c>macos/Sources/RSSQuickUI/TextScale.swift</c>).
        /// Unlike the Mac, the choice lasts only until RSS Quick closes: Windows already has a
        /// remembered text size in Settings, which is <see cref="Current"/>, and this build keeps
        /// no settings file of its own.
        /// </remarks>
        private static readonly double[] Steps = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0];

        /// <summary>The next step up, or the largest.</summary>
        public static double Larger(double current) =>
            Array.Find(Steps, step => step > current + 0.001) is var next && next > 0 ? next : Steps[^1];

        /// <summary>The next step down, or the smallest.</summary>
        public static double Smaller(double current) =>
            Array.FindLast(Steps, step => step < current - 0.001) is var next && next > 0 ? next : Steps[0];

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
