using System;
using System.Windows.Input;

namespace RSSReaderWPF
{
    /// <summary>
    /// An <see cref="ICommand"/> over a plain delegate, for the window's key bindings.
    /// </summary>
    public class RelayCommand : ICommand
    {
        private readonly Action _execute;
        private readonly Func<bool>? _canExecute;

        public RelayCommand(Action execute, Func<bool>? canExecute = null)
        {
            _execute = execute ?? throw new ArgumentNullException(nameof(execute));
            _canExecute = canExecute;
        }

        /// <remarks>
        /// Routed through <see cref="CommandManager.RequerySuggested"/> so WPF re-evaluates
        /// CanExecute on the events that usually change it, rather than this having to be told.
        /// </remarks>
        public event EventHandler? CanExecuteChanged
        {
            add { CommandManager.RequerySuggested += value; }
            remove { CommandManager.RequerySuggested -= value; }
        }

        public bool CanExecute(object? parameter) => _canExecute?.Invoke() ?? true;

        public void Execute(object? parameter) => _execute();
    }
}
