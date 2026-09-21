import AppKit
import RSSQuickCore

/// The feed tree.
///
/// `NSOutlineView` already does most of what the Windows `TreeView` had to be taught: Left and
/// Right collapse and expand, type-ahead finds a feed by name, and VoiceOver announces the level
/// and the disclosure state without being asked. What is left is Return, which the control does
/// not handle at all, and making sure focus arriving here lands on a row rather than on nothing.
final class FeedOutlineView: NSOutlineView {
    /// Called when Return is pressed on a row - never on selection. Selecting a feed does not
    /// load it; Enter does. That is deliberate, so arrow-key browsing never touches the network.
    var onActivate: (() -> Void)?

    /// Called when focus arrives, so the controller can say where it went.
    var onFocusArrived: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.isReturn, selectedRow >= 0 {
            onActivate?()
            return
        }

        super.keyDown(with: event)
    }

    /// Sends focus that landed on an empty selection on to a row.
    ///
    /// The Windows build needs a `GotFocus` handler for this and has to guard it on the original
    /// source, because there the container and its rows are separate focus targets and the
    /// handler ran for both - so every arrow key re-focused the row it had just left. Here the
    /// view is the only responder and rows are not, so there is nothing to guard against: this
    /// runs once, when focus enters the panel.
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }

        if selectedRow < 0, numberOfRows > 0 {
            selectRowIndexes([0], byExtendingSelection: false)
            scrollRowToVisible(0)
        }

        onFocusArrived?()
        return true
    }
}

/// The headlines list.
final class HeadlinesTableView: NSTableView {
    /// Called when Return is pressed on a row: open the article in the browser.
    var onActivate: (() -> Void)?

    var onFocusArrived: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.isReturn, selectedRow >= 0 {
            onActivate?()
            return
        }

        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }

        if selectedRow < 0, numberOfRows > 0 {
            selectRowIndexes([0], byExtendingSelection: false)
            scrollRowToVisible(0)
        }

        onFocusArrived?()
        return true
    }
}

/// One headline: the title, and a quieter line under it.
///
/// The row is a single accessibility element rather than a group of two text fields. A braille
/// display shows one line per element, and a row that reports as "title" then "12/03/2026, 09:14"
/// costs the reader a second line to scrub past for every headline. The date is in the help text
/// instead, where it can be asked for.
final class HeadlineCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HeadlineCell")

    private let titleField = HeadlineCellView.makeField()
    private let detailField = HeadlineCellView.makeField()

    init() {
        super.init(frame: .zero)

        titleField.maximumNumberOfLines = 0
        detailField.maximumNumberOfLines = 1

        // No literal colours anywhere. These two follow the system, so a Dark Mode or Increase
        // Contrast switch is handled without this code hearing about it - and secondaryLabelColor
        // is dimmed in an ordinary theme but fully legible under Increase Contrast, which a fixed
        // grey would not be.
        titleField.textColor = .labelColor
        detailField.textColor = .secondaryLabelColor

        addSubview(titleField)
        addSubview(detailField)
        textField = titleField

        // A full vertical chain, which is what lets the table size rows to the text rather than
        // clipping a long headline to a fixed height.
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            detailField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            detailField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        titleField.setAccessibilityElement(false)
        detailField.setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// - Parameter showFeedName: True after a folder load, where the list holds headlines from
    ///   many feeds at once and the title alone does not say which. It is left out of a
    ///   single-feed load, where it would be the same words on every row.
    func show(_ article: ArticleItem, fontSize: Double, showFeedName: Bool) {
        titleField.font = .boldSystemFont(ofSize: fontSize)
        detailField.font = .systemFont(ofSize: fontSize)

        titleField.stringValue = article.title

        let detail = [showFeedName ? article.feedTitle : "", article.published]
            .filter { !$0.isEmpty }
            .joined(separator: " \u{2014} ")
        detailField.stringValue = detail

        // The title comes first so it is the first thing spoken and the first thing under the
        // reader's fingers on a braille line. The feed name is part of the label rather than the
        // help text only when it is load-bearing: in a merged folder of twenty publishers,
        // hearing the headline without hearing whose it is makes the list much less useful.
        titleField.toolTip = article.title
        setAccessibilityLabel(showFeedName && !article.feedTitle.isEmpty
            ? "\(article.title), \(article.feedTitle)"
            : article.title)
        setAccessibilityHelp(detail.isEmpty ? nil : detail)
    }

    private static func makeField() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byWordWrapping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}

/// One feed or folder in the tree.
final class FeedCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FeedCell")

    private let field = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)

        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        field.textColor = .labelColor
        addSubview(field)
        textField = field

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ item: FeedItem, fontSize: Double) {
        // Folders are distinguished by weight alone. Colour conveys nothing to a screen reader or
        // to a colour-blind reader, and the tree structure already says which nodes are folders -
        // VoiceOver announces the disclosure state and the level without being told to.
        field.font = item.isCategory
            ? .boldSystemFont(ofSize: fontSize)
            : .systemFont(ofSize: fontSize)
        field.stringValue = item.title
        field.toolTip = item.title
    }
}

extension NSEvent {
    /// True for Return and for the keypad's Enter, which are different keys and are both used.
    var isReturn: Bool {
        guard let characters = charactersIgnoringModifiers, let first = characters.unicodeScalars.first else {
            return false
        }
        // No modifiers: Command-Return and friends belong to whatever menu claims them.
        guard modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return false }

        return first == "\r" || first == "\u{3}"
    }
}
