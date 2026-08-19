using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace RSSReaderWPF
{
    /// <summary>
    /// Bold for a folder, normal for a feed.
    /// </summary>
    /// <remarks>
    /// Weight rather than colour, deliberately. The tree used to colour folders dark blue as well,
    /// which sits unreadably against the background of a Windows high contrast theme, and says
    /// nothing at all to a colour-blind user or to a screen reader. Anything that distinguishes
    /// one kind of row from another here has to survive both.
    /// </remarks>
    public class BoolToFontWeightConverter : IValueConverter
    {
        public static readonly BoolToFontWeightConverter Instance = new();

        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
            value is true ? FontWeights.Bold : FontWeights.Normal;

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
            throw new NotSupportedException("One-way only.");
    }
}
