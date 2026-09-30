using System;
using System.Runtime.InteropServices;

namespace RSSReaderWPF.Services
{
    /// <summary>
    /// Whether this copy was installed from the Microsoft Store.
    /// </summary>
    /// <remarks>
    /// <para>A Store copy is an MSIX package, and Windows gives a packaged process an identity that
    /// nothing else has. Asking for its name is the documented test: an unpackaged process gets
    /// <c>APPMODEL_ERROR_NO_PACKAGE</c> instead.</para>
    /// <para>What changes in a Store copy is only who updates it. Windows does, so RSS Quick must
    /// not look for a newer version itself or offer a download from GitHub. docs/STORE-PLAN.md has
    /// the rest.</para>
    /// </remarks>
    public static class PackageIdentity
    {
        private const int AppModelErrorNoPackage = 15700;
        private const int ErrorInsufficientBuffer = 122;

        private static readonly Lazy<bool> Packaged = new(Ask);

        /// <summary>True when running from a package, which for RSS Quick means the Store.</summary>
        public static bool IsPackaged => Packaged.Value;

        private static bool Ask()
        {
            try
            {
                // Length zero asks only how long the name is, which is enough to learn there is one.
                var length = 0u;
                return GetCurrentPackageFullName(ref length, IntPtr.Zero) switch
                {
                    AppModelErrorNoPackage => false,
                    ErrorInsufficientBuffer => true,
                    _ => false,
                };
            }
            catch (EntryPointNotFoundException)
            {
                // Windows older than 8 has no packages at all.
                return false;
            }
        }

        [DllImport("kernel32.dll", ExactSpelling = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        private static extern int GetCurrentPackageFullName(ref uint packageFullNameLength, IntPtr packageFullName);
    }
}
