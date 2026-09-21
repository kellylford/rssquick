import AppKit

/// The reader's chosen text size, as a multiplier.
///
/// macOS is in the same position Windows is: there is a system-wide accessibility text size
/// setting, and AppKit does not apply it to an ordinary application's views any more than WPF
/// applies the Windows one. On Windows this class reads that setting out of the registry. There
/// is no equivalent value to read here, so the multiplier is the reader's own, set from the View
/// menu with the usual Command-plus and Command-minus.
///
/// This is the one thing RSS Quick remembers between runs. The Windows build stores nothing at
/// all, and that is the right default for feeds and window state - but a low-vision reader
/// having to enlarge the text again on every launch is a poor trade for that tidiness.
@MainActor
public enum TextScale {
    private static let defaultsKey = "TextScaleFactor"

    /// Matches the range the Windows build accepts, which is Windows' own slider plus headroom.
    static let minimum = 1.0
    static let maximum = 4.0

    private static let steps: [Double] = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0]

    public static var current: Double {
        get { clamp(UserDefaults.standard.object(forKey: defaultsKey) as? Double ?? 1.0) }
        set { UserDefaults.standard.set(clamp(newValue), forKey: defaultsKey) }
    }

    /// The base size everything in the window is derived from.
    public static var baseFontSize: Double { NSFont.systemFontSize * current }

    static func larger() { current = steps.first { $0 > current + 0.001 } ?? maximum }

    static func smaller() { current = steps.last { $0 < current - 0.001 } ?? minimum }

    static func reset() { current = 1.0 }

    /// Clamps to the supported range. Separated from reading the stored value so it can be
    /// tested without touching the machine's actual settings.
    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        return Swift.min(Swift.max(value, minimum), maximum)
    }
}
