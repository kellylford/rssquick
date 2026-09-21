import AppKit
import RSSQuickCore

// MARK: - The feed tree

extension MainWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FeedItem).map { !$0.children.isEmpty } ?? false
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let feed = item as? FeedItem else { return nil }

        let cell = outlineView.makeView(withIdentifier: FeedCellView.identifier, owner: self) as? FeedCellView
            ?? {
                let fresh = FeedCellView()
                fresh.identifier = FeedCellView.identifier
                return fresh
            }()

        cell.show(feed, fontSize: TextScale.baseFontSize)
        return cell
    }

    /// Type-ahead: typing "guar" jumps to the Guardian rather than making the reader arrow
    /// through a hundred and ninety feeds to reach it.
    public func outlineView(
        _ outlineView: NSOutlineView,
        typeSelectStringFor tableColumn: NSTableColumn?,
        item: Any
    ) -> String? {
        (item as? FeedItem)?.title
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        // Selecting a feed does not load it, and does not announce anything either: VoiceOver
        // has just read the row, and following it with a status message would say the feed's
        // name twice for every arrow key.
        reportFeedTreeSelection()
    }

    func reportFeedTreeSelection() {
        guard let item = outline.item(atRow: outline.selectedRow) as? FeedItem else { return }
        status = item.isCategory
            ? "\(item.title) - folder of \(item.allFeeds.count) feeds; Return loads all of them"
            : "\(item.title) - Return loads headlines"
    }

    private func children(of item: Any?) -> [FeedItem] {
        guard let item else { return roots }
        return (item as? FeedItem)?.children ?? []
    }
}

// MARK: - The headlines

extension MainWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { headlines.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard headlines.indices.contains(row) else { return nil }

        let cell = tableView.makeView(withIdentifier: HeadlineCellView.identifier, owner: self) as? HeadlineCellView
            ?? {
                let fresh = HeadlineCellView()
                fresh.identifier = HeadlineCellView.identifier
                return fresh
            }()

        cell.show(headlines[row], fontSize: TextScale.baseFontSize, showFeedName: headlinesAreMerged)
        return cell
    }

    public func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        headlines.indices.contains(row) ? headlines[row].title : nil
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        // Suppressed while a load is in progress, so clearing the list on the way in does not
        // report a position in a list that is about to be replaced.
        guard !isLoadingFeed else { return }

        let row = table.selectedRow

        guard row >= 0, headlines.indices.contains(row) else {
            openButton.isEnabled = false
            return
        }

        lastSelectedHeadlineRow = row
        openButton.isEnabled = !headlines[row].link.isEmpty

        // Position and source. Written, not announced - see setStatus. The name comes from the
        // article rather than from the tree selection: after a folder load the list holds
        // headlines from many feeds, and arrowing around the tree does not change which feed the
        // headlines on screen came from.
        guard !keepLoadSummary else { return }
        status = describePosition(at: row)
    }
}

// MARK: - Keys and menu commands

extension MainWindowController: NSMenuItemValidation {
    /// Keys AppKit will not route for us.
    ///
    /// Refresh, Open in Browser and the rest are menu items with Command equivalents, which is
    /// how a Mac application is expected to expose them and how VoiceOver users discover them.
    /// These three are not: Control-Tab cannot be a menu key equivalent, and the function keys
    /// are worth supporting as well as Command-R so that muscle memory carried over from the
    /// Windows build still works.
    func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === window, window?.attachedSheet == nil else { return event }
            return handle(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers

        // Control-Tab and Control-Shift-Tab, the Windows binding, alongside F6.
        if event.keyCode == 48, modifiers.contains(.control) {
            cycleSections()
            return true
        }

        guard modifiers.isEmpty || modifiers == .shift else { return false }

        switch key {
        case String(NSEvent.SpecialKey.f5.unicodeScalar):
            refreshCurrentFeed()
            return true

        case String(NSEvent.SpecialKey.f6.unicodeScalar):
            cycleSections()
            return true

        default:
            return false
        }
    }

    /// Escape: abandon the load in progress.
    ///
    /// Reached through the responder chain rather than through the key monitor, so a sheet or a
    /// text field in front of the window still gets Escape first and can dismiss itself with it.
    public override func cancelOperation(_ sender: Any?) {
        cancelLoad()
    }

    @objc func refresh(_ sender: Any?) { refreshCurrentFeed() }

    @objc func focusFeedTreeCommand(_ sender: Any?) {
        focusFeedTree()
        setStatus("Feed tree")
    }

    @objc func focusHeadlinesCommand(_ sender: Any?) {
        focusHeadlines()
        setStatus("Headlines")
    }

    @objc func cyclePanes(_ sender: Any?) { cycleSections() }

    @objc func stopLoading(_ sender: Any?) { cancelLoad() }

    @objc func increaseTextSize(_ sender: Any?) {
        TextScale.larger()
        applyTextScale()
        setStatus("Text size \(Int(TextScale.current * 100)) percent")
    }

    @objc func decreaseTextSize(_ sender: Any?) {
        TextScale.smaller()
        applyTextScale()
        setStatus("Text size \(Int(TextScale.current * 100)) percent")
    }

    @objc func resetTextSize(_ sender: Any?) {
        TextScale.reset()
        applyTextScale()
        setStatus("Text size 100 percent")
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openInBrowser(_:)):
            return table.selectedRow >= 0
                && headlines.indices.contains(table.selectedRow)
                && !headlines[table.selectedRow].link.isEmpty

        case #selector(refresh(_:)):
            return currentlyLoadedFeed != nil

        case #selector(stopLoading(_:)):
            return loadTask != nil

        case #selector(increaseTextSize(_:)):
            return TextScale.current < TextScale.maximum

        case #selector(decreaseTextSize(_:)):
            return TextScale.current > TextScale.minimum

        default:
            return true
        }
    }
}
