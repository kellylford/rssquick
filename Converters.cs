using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace RSSReaderWPF
{
    /// <summary>
    /// Converts boolean to FontWeight for category styling
    /// </summary>
    public class BoolToFontWeightConverter : IValueConverter
    {
        public static readonly BoolToFontWeightConverter Instance = new();

        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value is bool isCategory && isCategory)
                return FontWeights.Bold;
            return FontWeights.Normal;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }

    /// <summary>
    /// Converts boolean to Thickness for category margin styling
    /// </summary>
    public class BoolToMarginConverter : IValueConverter
    {
        public static readonly BoolToMarginConverter Instance = new();

        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value is bool isCategory && isCategory)
                return new Thickness(0, 5, 0, 0); // Top margin for categories
            return new Thickness(20, 1, 0, 1); // Left indent for feeds
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }

    /// <summary>
    /// Converts boolean to Foreground brush for category styling
    /// </summary>
    public class BoolToForegroundConverter : IValueConverter
    {
        public static readonly BoolToForegroundConverter Instance = new();

        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value is bool isCategory && isCategory)
                return System.Windows.Media.Brushes.DarkBlue;
            return System.Windows.Media.Brushes.Black;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }
}
