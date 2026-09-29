using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using RSSReaderWPF.Services;

namespace RSSReaderWPF
{
    /// <summary>
    /// A small modal window asking for one line of text, and optionally a folder: Search All Feeds
    /// and Subscribe to Feed.
    /// </summary>
    /// <remarks>
    /// <para>Built in code rather than XAML because it is a handful of standard controls, and a
    /// standard control is already what a screen reader handles best: each field is labelled by
    /// its <see cref="Label"/> (which also gives it an Alt key), Enter is the default button and
    /// Escape cancels. Focus starts in the text box with its text selected, so typing replaces
    /// the last search.</para>
    /// <para>No colours are set: everything takes the Windows theme, as the main window does. The
    /// font size is the main window's, so Ctrl+Plus and the Windows text size carry over.</para>
    /// <para>The window only asks. What happens with the answer is done by the main window, where
    /// the tests can reach it without a modal dialog in the way.</para>
    /// </remarks>
    internal sealed class InputDialog : Window
    {
        private readonly TextBox _text;
        private readonly ComboBox? _folders;

        /// <param name="owner">Centred on, and takes its font size from.</param>
        /// <param name="title">The window title, which is what a screen reader says first.</param>
        /// <param name="prompt">The text box's label, with an underscore before its Alt key.</param>
        /// <param name="accept">The default button's text, with an underscore before its Alt key.</param>
        /// <param name="text">What the text box starts with.</param>
        /// <param name="folders">When given, a Folder list under the text box.</param>
        /// <param name="folder">The folder chosen to start with.</param>
        public InputDialog(Window owner, string title, string prompt, string accept, string text = "",
                           IReadOnlyList<FolderChoice>? folders = null, FolderChoice? folder = null)
        {
            Owner = owner;
            Title = title;
            FontSize = owner.FontSize;
            SizeToContent = SizeToContent.WidthAndHeight;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            SetResourceReference(BackgroundProperty, SystemColors.WindowBrushKey);
            SetResourceReference(ForegroundProperty, SystemColors.WindowTextBrushKey);

            var panel = new StackPanel { Margin = new Thickness(12), MinWidth = 420 };

            _text = new TextBox { Text = text, Margin = new Thickness(0, 0, 0, 12) };
            panel.Children.Add(Labelled(prompt, _text));
            panel.Children.Add(_text);

            if (folders is not null)
            {
                _folders = new ComboBox
                {
                    ItemsSource = folders,
                    DisplayMemberPath = nameof(FolderChoice.Name),
                    SelectedItem = folder ?? (folders.Count > 0 ? folders[0] : null),
                    Margin = new Thickness(0, 0, 0, 12),
                };
                panel.Children.Add(Labelled("_Folder:", _folders));
                panel.Children.Add(_folders);
            }

            var ok = new Button { Content = accept, IsDefault = true, MinWidth = 90, Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(0, 0, 8, 0) };
            ok.Click += (_, _) =>
            {
                // An empty box has nothing to do, and closing on it would read as having done it.
                if (string.IsNullOrWhiteSpace(_text.Text)) { _text.Focus(); return; }
                DialogResult = true;
            };
            var cancel = new Button { Content = "Cancel", IsCancel = true, MinWidth = 90, Padding = new Thickness(10, 4, 10, 4) };

            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            buttons.Children.Add(ok);
            buttons.Children.Add(cancel);
            panel.Children.Add(buttons);

            Content = panel;

            Loaded += (_, _) =>
            {
                _text.Focus();
                _text.SelectAll();
            };
        }

        /// <summary>What was typed, trimmed.</summary>
        public string Text => _text.Text.Trim();

        /// <summary>The folder chosen, when there was a list to choose from.</summary>
        public FolderChoice? Folder => _folders?.SelectedItem as FolderChoice;

        /// <summary>A label that names the field for a screen reader and gives it an Alt key.</summary>
        private static Label Labelled(string text, Control target)
        {
            var label = new Label { Content = text, Target = target, Padding = new Thickness(0, 0, 0, 4) };
            AutomationProperties.SetLabeledBy(target, label);
            return label;
        }
    }
}
