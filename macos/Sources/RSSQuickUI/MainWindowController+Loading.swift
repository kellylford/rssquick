import AppKit
import RSSQuickCore

extension MainWindowController {
    // MARK: The status line

    /// Writes the status line, and says it aloud when VoiceOver would not otherwise know.
    ///
    /// - Parameter announce: False for anything VoiceOver reports for itself. Moving between
    ///   rows is the case that matters: VoiceOver already says "3 of 45" for a table row, so
    ///   announcing the same thing again makes every arrow key speak twice.
    func setStatus(_ message: String, announce: Bool = true) {
        status = message
        if announce { Announcer.announce(message, in: window) }
    }

    // MARK: Opening the feed list

    func loadDefaultOpml() {
        guard let url = DefaultOpml.find() else {
            status = "No feed list found - use Import OPML File to choose one"
            // Focus goes where the reader can act. Deferred to the next turn of the run loop
            // because the window has no views laid out yet at this point in construction.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                window?.makeFirstResponder(importButton)
                setStatus("No feed list found - press Space to import an OPML file")
            }
            return
        }

        do {
            try open(url, describe: { "Loaded \($0) from the default feed list" })
        } catch {
            status = "Could not read the default feed list: \(ErrorText.describe(error))"
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                window?.makeFirstResponder(importButton)
            }
            return
        }

        // Startup focus is set on the next turn of the run loop, not here: the outline has no
        // rows yet, because it has not been asked to reload against a window that is not on
        // screen. Doing it inline silently leaves focus nowhere.
        DispatchQueue.main.async { [weak self] in
            guard let self, outline.numberOfRows > 0 else { return }
            focusFeedTree()
        }
    }

    /// Replaces the feed tree with the contents of an OPML file.
    func open(_ url: URL, describe summary: (String) -> String) throws {
        let document = try OpmlParser.parse(contentsOf: url)

        roots = document.roots
        outline.reloadData()

        let feeds = document.feedCount == 1 ? "1 feed" : "\(document.feedCount) feeds"
        status = summary(feeds)
    }

    @objc func importOpml(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Import OPML File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.xml, .init(filenameExtension: "opml") ?? .xml]
        panel.allowsOtherFileTypes = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try open(url, describe: { "Imported \($0) from \(url.lastPathComponent)" })
            Announcer.announce(status, in: window)
            focusFeedTree()
        } catch {
            setStatus("Could not import \(url.lastPathComponent): \(ErrorText.describe(error))")
            alert(title: "Import Error", message: "Could not import \(url.lastPathComponent).\n\n\(ErrorText.describe(error))")
        }
    }

    // MARK: Loading

    /// Begins a load, cancelling whatever was already running.
    func beginLoad(_ target: FeedItem, merged: Bool) {
        loadTask?.cancel()
        loadTask = nil

        isLoadingFeed = true
        currentlyLoadedFeed = target
        headlinesAreMerged = merged
        headlines = []
        lastSelectedHeadlineRow = -1
        openButton.isEnabled = false
        table.reloadData()
    }

    /// Return on a tree row: load one feed, or every feed under a folder.
    func activateSelectedFeed() {
        guard let item = outline.item(atRow: outline.selectedRow) as? FeedItem else { return }

        if item.isCategory { loadFolder(item) } else { loadFeed(item) }
    }

    func loadFeed(_ feed: FeedItem) {
        beginLoad(feed, merged: false)
        setStatus("Loading \(feed.title)…")

        loadTask = Task { [weak self] in
            do {
                let articles = try await FeedLoader.loadFeed(feed)
                guard !Task.isCancelled, let self else { return }

                show(articles, status: articles.isEmpty
                    ? "\(feed.title) has no headlines right now"
                    : "Loaded \(articles.count) headlines from \(feed.title)")
            } catch {
                guard !Task.isCancelled, let self else { return }

                isLoadingFeed = false
                let reason = ErrorText.describe(error)
                setStatus("Could not load \(feed.title): \(reason)")

                // A dialog only where the reader asked for one specific thing and got nothing.
                // The folder path deliberately does not do this; see describeFolderLoad.
                alert(title: "Feed Load Error", message: "Could not load \(feed.title).\n\nThis feed \(reason).")
            }
        }
    }

    func loadFolder(_ folder: FeedItem) {
        beginLoad(folder, merged: true)

        let feeds = folder.allFeeds
        guard !feeds.isEmpty else {
            isLoadingFeed = false
            setStatus("\(folder.title) has no feeds in it")
            return
        }

        setStatus("Loading \(feeds.count) feeds in \(folder.title)…")

        let title = folder.title
        let total = feeds.count

        loadTask = Task { [weak self] in
            let progress: @Sendable (Int) -> Void = { done in
                Task { @MainActor [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    // Progress is written but not announced: a twenty-feed folder would
                    // otherwise interrupt the reader twenty times on the way to the result.
                    status = "Loading \(title) - \(done) of \(total) feeds…"
                }
            }

            do {
                let result = try await FeedLoader.loadFolder(feeds, progress: progress)
                guard !Task.isCancelled, let self else { return }

                show(result.articles, status: MainWindowController.describeFolderLoad(title, result))
            } catch is CancellationError {
                // Escape, or a newer load superseding this one. Either way the status line has
                // already been given something better to say.
                self?.isLoadingFeed = false
            } catch {
                guard !Task.isCancelled, let self else { return }

                isLoadingFeed = false
                setStatus("Could not load \(title): \(ErrorText.describe(error))")
            }
        }
    }

    /// Puts articles on screen and hands focus to the first of them.
    func show(_ articles: [ArticleItem], status summary: String) {
        headlines = articles
        table.reloadData()

        setStatus(summary)

        // Cleared before focusing, so the selection this makes is allowed to do its other work -
        // tracking the row, enabling the browser button - rather than being suppressed as part
        // of the load.
        isLoadingFeed = false

        guard !articles.isEmpty else { return }

        keepLoadSummary = true
        defer { keepLoadSummary = false }

        lastSelectedHeadlineRow = 0
        table.selectRowIndexes([0], byExtendingSelection: false)
        table.scrollRowToVisible(0)
        window?.makeFirstResponder(table)
    }

    /// One line covering how much of a folder arrived, and what did not.
    ///
    /// Partial failure is reported here rather than in a dialog. A folder of twenty feeds where
    /// one publisher is down is a normal morning, and it does not warrant a modal sheet standing
    /// between the reader and the nineteen that worked.
    static func describeFolderLoad(_ folder: String, _ result: FolderLoadResult) -> String {
        if result.failures.isEmpty {
            return "Loaded \(result.articles.count) headlines from \(result.feedsAttempted) feeds in \(folder)"
        }

        if result.feedsSucceeded == 0 {
            return "None of the \(result.feedsAttempted) feeds in \(folder) could be loaded"
        }

        // Name them while the list is short enough to be useful rather than a wall of text.
        let named = result.failures.count <= 3
            ? ": " + result.failures.map { "\($0.feedTitle) \($0.reason)" }.joined(separator: ", ")
            : ""

        return "Loaded \(result.articles.count) headlines from \(result.feedsSucceeded) of "
            + "\(result.feedsAttempted) feeds in \(folder); \(result.failures.count) failed\(named)"
    }

    /// Escape: abandon the load in progress.
    func cancelLoad() {
        guard let loadTask, !loadTask.isCancelled else { return }

        loadTask.cancel()
        self.loadTask = nil
        isLoadingFeed = false
        setStatus("Loading cancelled")
    }

    /// Refresh: reload whatever is currently in the headlines list.
    func refreshCurrentFeed() {
        guard let loaded = currentlyLoadedFeed else {
            setStatus("Nothing to refresh yet - press Return on a feed first")
            return
        }

        if loaded.isCategory { loadFolder(loaded) } else { loadFeed(loaded) }
    }

    // MARK: Opening an article

    @objc func openInBrowser(_ sender: Any?) {
        guard table.selectedRow >= 0, table.selectedRow < headlines.count else {
            setStatus("Select a headline first")
            return
        }

        let article = headlines[table.selectedRow]

        guard !article.link.isEmpty, let url = URL(string: article.link), url.scheme != nil else {
            setStatus("\(article.title) has no link to open")
            return
        }

        if NSWorkspace.shared.open(url) {
            setStatus("Opened in browser: \(article.title)")
        } else {
            setStatus("Could not open \(article.title) in your browser")
            alert(title: "Browser Error", message: "Could not open this article:\n\n\(article.link)")
        }
    }

    // MARK: Focus

    func focusFeedTree() {
        guard outline.numberOfRows > 0 else {
            setStatus("Feed tree is empty - import an OPML file")
            return
        }

        if outline.selectedRow < 0 {
            outline.selectRowIndexes([0], byExtendingSelection: false)
        }
        outline.scrollRowToVisible(outline.selectedRow)
        window?.makeFirstResponder(outline)
    }

    func focusHeadlines() {
        guard table.numberOfRows > 0 else {
            window?.makeFirstResponder(table)
            setStatus("Headlines list is empty - press Return on a feed to load it")
            return
        }

        let row = (0..<table.numberOfRows).contains(lastSelectedHeadlineRow) ? lastSelectedHeadlineRow : 0
        lastSelectedHeadlineRow = row
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        window?.makeFirstResponder(table)
    }

    /// Move to the other panel.
    ///
    /// Tested by containment rather than by asking whether the view itself is first responder:
    /// on Windows the equivalent check read false in both branches because focus sits on a row
    /// rather than on the container, so every press went the same way and the key only ever
    /// moved one direction.
    func cycleSections() {
        if isWithin(outline, window?.firstResponder) {
            focusHeadlines()
            setStatus("Headlines")
        } else {
            focusFeedTree()
            setStatus("Feed tree")
        }
    }

    func reportFeedTreeFocus() {
        guard !keepLoadSummary else { return }

        let selected = outline.item(atRow: outline.selectedRow) as? FeedItem
        status = selected.map { "Feed tree - \($0.title)" }
            ?? "Feed tree - select a feed and press Return to load headlines"
    }

    func reportHeadlinesFocus() {
        // The other half of the guard in tableViewSelectionDidChange, and just as necessary.
        // A load selects its first headline and then focuses the list, and focus arriving is a
        // second, separate chance to overwrite the summary the load just wrote - which is how
        // "3 of 20 feeds failed" disappeared before anyone could read it.
        guard !keepLoadSummary else { return }

        guard table.numberOfRows > 0 else {
            status = "Headlines - empty"
            return
        }
        status = describePosition(at: max(table.selectedRow, 0))
    }

    /// What the status line says about where you are in the headlines.
    func describePosition(at row: Int) -> String {
        guard headlines.indices.contains(row) else { return status }

        let article = headlines[row]
        let source = article.feedTitle.isEmpty
            ? currentlyLoadedFeed?.title ?? "Headlines"
            : article.feedTitle

        return "\(source) - \(row + 1) of \(headlines.count)"
    }

    func isWithin(_ ancestor: NSView, _ responder: NSResponder?) -> Bool {
        var view = responder as? NSView
        while let current = view {
            if current === ancestor { return true }
            view = current.superview
        }
        return false
    }

    // MARK: Errors

    func alert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
