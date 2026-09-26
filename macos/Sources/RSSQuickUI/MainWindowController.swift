import AppKit
import RSSQuickCore

/// The window: two panels, a status line, and all the focus management.
@MainActor
public final class MainWindowController: NSWindowController {
    // MARK: Views

    let importButton = NSButton(title: "Import OPML File…", target: nil, action: nil)
    let openButton = NSButton(title: "Open in Browser", target: nil, action: nil)
    let outline = FeedOutlineView()
    let table = HeadlinesTableView()
    let statusField = NSTextField(labelWithString: "")
    let splitView = NSSplitView()

    // MARK: State

    var roots: [FeedItem] = []
    var headlines: [ArticleItem] = []

    /// Cancels the load in flight.
    ///
    /// Without this, pressing Return on a second feed before the first returned left both
    /// completions appending to the same list: the headlines interleaved, and the status line
    /// reported whichever finished last. Easy to hit with a slow feed, which is exactly when
    /// someone is most likely to give up and try a different one.
    var loadTask: Task<Void, Never>?

    /// Suppresses selection side effects while a load is in progress.
    var isLoadingFeed = false

    /// Set while a load hands focus to its first headline, so the selection that causes does not
    /// overwrite the summary the load just wrote.
    ///
    /// Two things want the status line at the same moment: what the load did, and where you now
    /// are in the list. The load summary was losing, silently - including "3 of 20 feeds failed",
    /// which is the one message there is no other way to discover. Position takes over from the
    /// first arrow key.
    var keepLoadSummary = false

    /// The row to come back to when focus returns to the headlines.
    var lastSelectedHeadlineRow = -1

    /// What Refresh reloads. Keyed on the loaded feed, not the tree selection: using the
    /// selection meant Refresh loaded a different feed from the one on screen whenever the reader
    /// had arrowed on past it, and did nothing at all after a folder load.
    var currentlyLoadedFeed: FeedItem?

    /// True when the headlines came from a folder, so rows name the feed they came from.
    var headlinesAreMerged = false

    /// The reader's saved default feed list.
    ///
    /// Settable so the tests can point it at a temporary folder. Without that, every test that
    /// builds a window would read - and could overwrite - the real saved list of whoever runs
    /// the suite.
    static var savedFeedList = SavedFeedList(url: StarterOpml.savedListURL)

    /// The feed list in the tree, kept so it can be saved as the default.
    var currentFeedList: OpenedFeedList?

    /// True while the tree shows the list RSS Quick opens at startup, which is what dims
    /// Make This My Default Feed List.
    var currentListIsDefault = false

    var keyMonitor: Any?

    /// The status line, and the only thing that writes to it.
    var status: String = "" {
        didSet { statusField.stringValue = status }
    }

    // MARK: Construction

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RSS Quick"
        window.setFrameAutosaveName("RSSQuickMainWindow")
        window.minSize = NSSize(width: 640, height: 400)
        self.init(window: window)
    }

    public override init(window: NSWindow?) {
        super.init(window: window)
        buildInterface()
        loadDefaultOpml()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // MARK: Interface

    private func buildInterface() {
        guard let window, let content = window.contentView else { return }

        content.wantsLayer = true

        let topBar = NSStackView(views: [importButton])
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.orientation = .horizontal
        topBar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        topBar.alignment = .centerY

        importButton.target = self
        importButton.action = #selector(importOpml(_:))
        importButton.bezelStyle = .rounded
        importButton.setAccessibilityHelp("Choose an OPML file to replace the feed list")

        openButton.target = self
        openButton.action = #selector(openInBrowser(_:))
        openButton.bezelStyle = .rounded
        openButton.isEnabled = false
        openButton.setAccessibilityHelp("Open the selected headline in your default web browser")

        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(makeFeedPanel())
        splitView.addArrangedSubview(makeHeadlinePanel())

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        statusField.translatesAutoresizingMaskIntoConstraints = false
        statusField.textColor = .labelColor
        statusField.lineBreakMode = .byTruncatingTail
        statusField.setAccessibilityLabel("Status")

        let statusBar = NSStackView(views: [statusField])
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.orientation = .horizontal
        statusBar.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 8, right: 12)

        for view in [topBar, splitView, separator, statusBar] { content.addSubview(view) }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: content.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            splitView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            separator.topAnchor.constraint(equalTo: splitView.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            statusBar.topAnchor.constraint(equalTo: separator.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        applyTextScale()
        setUpTabRing()
        installKeyMonitor()
    }

    private func makeFeedPanel() -> NSView {
        outline.dataSource = self
        outline.delegate = self
        outline.headerView = nil
        outline.allowsEmptySelection = false
        outline.allowsMultipleSelection = false
        outline.indentationPerLevel = 16
        outline.autoresizesOutlineColumn = false
        outline.backgroundColor = .textBackgroundColor
        outline.usesAlternatingRowBackgroundColors = false
        outline.setAccessibilityLabel("Feed tree")
        outline.setAccessibilityHelp("Navigate with arrow keys; press Return to load headlines")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("feed"))
        column.title = "Feeds"
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        outline.onActivate = { [weak self] in self?.activateSelectedFeed() }
        outline.onFocusArrived = { [weak self] in self?.reportFeedTreeFocus() }

        return scrolled(outline, width: 340)
    }

    private func makeHeadlinePanel() -> NSView {
        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.usesAutomaticRowHeights = true
        table.backgroundColor = .textBackgroundColor
        table.usesAlternatingRowBackgroundColors = true
        table.style = .plain
        table.setAccessibilityLabel("Headlines")
        table.setAccessibilityHelp("Browse with arrow keys; press Return or Command-B to open in your browser")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("headline"))
        column.title = "Headlines"
        table.addTableColumn(column)

        table.onActivate = { [weak self] in self?.openInBrowser(nil) }
        table.onFocusArrived = { [weak self] in self?.reportHeadlinesFocus() }

        let scroll = scrolled(table, width: nil)

        let buttonBar = NSStackView(views: [openButton])
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.orientation = .horizontal
        buttonBar.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)

        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroll)
        panel.addSubview(buttonBar)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: panel.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),

            buttonBar.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            buttonBar.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            buttonBar.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            buttonBar.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])

        return panel
    }

    private func scrolled(_ view: NSView, width: CGFloat?) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        if let width { scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true }
        return scroll
    }

    /// Tab order is explicit and fixed: Import, feed tree, headlines, Open in Browser.
    ///
    /// Adding another focusable control means placing it in this chain deliberately and updating
    /// `TabOrderTests`. Leaving it to AppKit's automatic loop orders controls geometrically,
    /// which put the Open in Browser button before the headlines it acts on.
    private func setUpTabRing() {
        guard let window else { return }

        window.autorecalculatesKeyViewLoop = false

        importButton.nextKeyView = outline
        outline.nextKeyView = table
        table.nextKeyView = openButton
        openButton.nextKeyView = importButton

        window.initialFirstResponder = outline
    }

    // MARK: Text size

    /// Applies the reader's text size to everything the window draws.
    func applyTextScale() {
        let size = TextScale.baseFontSize

        importButton.font = .systemFont(ofSize: size)
        openButton.font = .systemFont(ofSize: size)
        statusField.font = .systemFont(ofSize: size)

        // Rows are measured, not guessed: the tree's rows are a single line of this font, and
        // the headline rows size themselves to their wrapped text.
        outline.rowHeight = ceil(size * 1.6)
        outline.reloadData()
        table.reloadData()
    }
}
