import AppKit
import RSSQuickCore
import UniformTypeIdentifiers

/// Searching every feed, subscribing, removing a feed, and exporting the list.
///
/// Each command comes in two halves, as on Windows. The first asks - a sheet, a save panel - and
/// is all a test cannot drive. The second does the work and is reachable directly, so the tests
/// call `search(for:)` rather than typing into a sheet. The Windows version is
/// `src/RSSQuick/MainWindow.Commands.cs`.
extension MainWindowController {
    // MARK: Search

    /// Edit, Search All Feeds (Command-F), or / in either panel: ask what to look for, then look.
    @objc func searchAllFeeds(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }

        let field = NSTextField(string: lastSearch)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        field.setAccessibilityLabel("Search the headlines of every feed for")

        let alert = NSAlert()
        alert.messageText = "Search All Feeds"
        alert.informativeText = "Search the headlines of every feed for:"
        alert.accessoryView = field
        alert.addButton(withTitle: "Search")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.search(for: field.stringValue)
        }
    }

    /// Fetches every feed in the tree and shows the headlines that match.
    ///
    /// A load in all but name, and it goes through the same path - `beginLoad`, `show`, Escape to
    /// stop it - so the status line and focus behave exactly as they do for a folder. Refresh runs
    /// the search again.
    func search(for query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !HeadlineSearch.words(query).isEmpty else { return }
        lastSearch = query

        let feeds = HeadlineSearch.feedsToSearch(roots)
        guard !feeds.isEmpty else {
            setStatus("There are no feeds to search - import a feed list first")
            return
        }

        beginLoad(FeedItem(title: query, isCategory: true), merged: true)
        currentSearch = query
        setStatus(HeadlineSearch.describeStart(query, feedCount: feeds.count))

        loadTask = Task { [weak self] in
            do {
                let result = try await FeedLoader.loadFolder(feeds)
                guard !Task.isCancelled, let self else { return }

                let matches = HeadlineSearch.filter(result.articles, query: query)
                let hadHeadlineFocus = isWithin(table, window?.firstResponder)

                show(matches, status: HeadlineSearch.describe(query, matches: matches.count, result: result))

                // Nothing matched, and the list focus was in is empty: the tree is the one place
                // left to be. No message, so the result is what is heard.
                if matches.isEmpty, hadHeadlineFocus, outline.numberOfRows > 0 {
                    if outline.selectedRow < 0 { outline.selectRowIndexes([0], byExtendingSelection: false) }
                    window?.makeFirstResponder(outline)
                }
            } catch is CancellationError {
                // Escape, or a newer load: see loadFolder.
            } catch {
                guard !Task.isCancelled, let self else { return }

                isLoadingFeed = false
                reportLoadOutcome("Could not search: \(ErrorText.describe(error))")
            }
        }
    }

    // MARK: Subscribing

    /// File, Subscribe to Feed (Command-N): ask for an address and a folder.
    @objc func subscribeToFeed(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }

        let currentRoots = currentFeedList?.document.roots ?? []
        let folders = OpmlEditor.folders(currentRoots)
        let selected = outline.item(atRow: outline.selectedRow) as? FeedItem
        let suggested = OpmlEditor.suggest(folders, roots: currentRoots, selected: selected)

        let addressLabel = NSTextField(labelWithString: "Address of the feed or its website:")
        let address = NSTextField(string: "")
        address.placeholderString = "example.com"
        address.setAccessibilityLabel("Address of the feed or its website")

        let folderLabel = NSTextField(labelWithString: "Folder:")
        let folderMenu = NSPopUpButton(frame: .zero, pullsDown: false)
        // One item per choice, tagged with its place. addItems(withTitles:) drops a title it
        // already has, so two folders with the same name would put every choice after them one
        // off - and the feed into the wrong folder.
        for (index, choice) in folders.enumerated() {
            let item = NSMenuItem(title: choice.name, action: nil, keyEquivalent: "")
            item.tag = index
            folderMenu.menu?.addItem(item)
        }
        folderMenu.selectItem(withTag: folders.firstIndex(of: suggested) ?? 0)
        folderMenu.setAccessibilityLabel("Folder")

        let stack = NSStackView(views: [addressLabel, address, folderLabel, folderMenu])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 110)
        for view in [address, folderMenu] {
            view.widthAnchor.constraint(equalToConstant: 340).isActive = true
        }

        let alert = NSAlert()
        alert.messageText = "Subscribe to Feed"
        alert.accessoryView = stack
        alert.addButton(withTitle: "Subscribe")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = address

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let text = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let index = folderMenu.selectedTag()
            self?.subscribe(to: text, into: folders.indices.contains(index) ? folders[index] : nil)
        }
    }

    /// Finds the feed at an address, adds it to the list, and saves the list as the default.
    ///
    /// Saving is not optional. A subscription that vanished the next time RSS Quick started would
    /// be worse than none, and the saved default is the only thing RSS Quick keeps - so
    /// subscribing to a feed in an imported list makes that list the default, and the status line
    /// says so. Nothing changes until the feed has been found and the list saved.
    ///
    /// - Parameter folder: Where it goes. Nil for the top level.
    func subscribe(to address: String, into folder: FolderChoice?) {
        subscribeTask?.cancel()

        // Before the network: the same address pasted twice is caught without a fetch.
        if let typed = FeedDiscovery.normalize(address),
           let known = OpmlEditor.findFeed(currentFeedList?.document.roots ?? [], url: typed.absoluteString) {
            alreadySubscribed(known)
            return
        }

        setStatus("Looking for a feed at \(address)…")

        // The folder's path is a position in this list. If the list changes while the feed is
        // being looked for - a feed removed, another list imported - the path would point
        // somewhere else, or into a list the reader never meant to change.
        let listAtStart = currentFeedList?.data

        subscribeTask = Task { [weak self] in
            let feed: DiscoveredFeed
            do {
                feed = try await FeedDiscovery.find(address)
            } catch {
                guard !Task.isCancelled, let self else { return }
                setStatus("Could not subscribe: \(address) \(ErrorText.describe(error))")
                return
            }
            guard !Task.isCancelled, let self else { return }
            guard currentFeedList?.data == listAtStart else {
                setStatus("Your feed list changed while RSS Quick was looking for \(feed.title), so it was not added. Subscribe again to add it")
                return
            }
            finishSubscribing(feed, into: folder)
        }
    }

    private func finishSubscribing(_ feed: DiscoveredFeed, into folder: FolderChoice?) {
        let roots = currentFeedList?.document.roots ?? []

        // Again, now the real address is known: a website's address leads to a feed that may
        // already be in the list under its own.
        if let existing = OpmlEditor.findFeed(roots, url: feed.url) {
            alreadySubscribed(existing)
            return
        }

        let into = folder ?? OpmlEditor.folders(roots).first { $0.path == nil }
            ?? FolderChoice(name: "Uncategorized", path: nil)

        guard let change = changeFeedList(failure: "Could not add \(feed.title) to your feed list", {
            try OpmlEditor.addFeed(to: $0, folder: into.path, title: feed.title, url: feed.url)
        }) else { return }

        if let added = OpmlEditor.findFeed(change.list.document.roots, url: feed.url) { selectInTree(added) }
        setStatus("Subscribed to \(feed.title) in \(into.name).\(change.defaultNote)")
    }

    private func alreadySubscribed(_ feed: FeedItem) {
        selectInTree(feed)
        setStatus("You already subscribe to \(feed.title), in \(feed.category)")
    }

    // MARK: Removing

    /// File, Remove Feed (Command-Delete): confirm, then remove.
    @objc func removeFeed(_ sender: Any?) {
        guard let feed = outline.item(atRow: outline.selectedRow) as? FeedItem else {
            setStatus("Select a feed in the feed tree first")
            return
        }
        guard !feed.isCategory else {
            setStatus("\(feed.title) is a folder. Remove Feed removes one feed at a time")
            return
        }
        guard let window, window.attachedSheet == nil else { return }

        let alert = NSAlert()
        alert.messageText = "Remove \(feed.title) from your feed list?"
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                remove(feed)
            } else {
                window.makeFirstResponder(outline)
            }
        }
    }

    /// Takes a feed out of the list and saves the list as the default.
    ///
    /// Focus goes to the feed that took its place, the way deleting from any list does, or the one
    /// before it when it was last, or its folder when it was the only one - never nowhere.
    func remove(_ feed: FeedItem) {
        guard !feed.isCategory, let path = feed.outlinePath else { return }

        let roots = currentFeedList?.document.roots ?? []
        let parent = OpmlEditor.parent(of: feed, in: roots)
        let index = (parent?.children ?? roots).firstIndex { $0 === feed } ?? 0

        guard let change = changeFeedList(failure: "Could not remove \(feed.title)", {
            try OpmlEditor.remove(from: $0, at: path)
        }) else { return }

        let newRoots = change.list.document.roots
        var newParent: FeedItem?
        if let parentPath = parent?.outlinePath {
            newParent = OpmlEditor.find(path: parentPath, in: newRoots)
        } else if parent != nil {
            // The Uncategorized folder, which has no path; gone if this was its last feed.
            newParent = newRoots.first { $0.isCategory && $0.outlinePath == nil }
        }
        let siblings = newParent?.children ?? newRoots
        let next = siblings.isEmpty ? newParent : siblings[min(index, siblings.count - 1)]

        if let next { selectInTree(next) } else { focusFeedTree() }
        setStatus("Removed \(feed.title).\(change.defaultNote)")
    }

    // MARK: Exporting

    /// File, Export Feed List (Command-E): ask where, then write it.
    @objc func exportFeedList(_ sender: Any?) {
        guard currentFeedList != nil else {
            setStatus("There is no feed list to export - import one first")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Feed List"
        panel.nameFieldStringValue = "RSS Quick Feeds.opml"
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportFeedList(to: url)
    }

    /// Writes the list on screen to a file, exactly as it was read or last changed, so it imports
    /// into another reader - or into RSS Quick on another Mac - unchanged.
    func exportFeedList(to url: URL) {
        guard let list = currentFeedList else { return }

        do {
            try list.data.write(to: url, options: .atomic)
            setStatus("Exported \(StartupFeedList.feeds(list.document.feedCount)) to \(url.lastPathComponent)")
        } catch {
            setStatus("Could not export to \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: Shared

    /// A change made and saved, and what to add to the status line when it made the list the
    /// default, which the reader did not ask for in so many words.
    struct FeedListChange {
        let list: OpenedFeedList
        let defaultNote: String
    }

    /// Applies an edit to the list on screen, saves it as the default, and shows it.
    ///
    /// - Returns: Nil, having said why in the status line, when it could not be made or saved.
    func changeFeedList(failure: String, _ edit: (Data) throws -> Data) -> FeedListChange? {
        let list: OpenedFeedList
        do {
            let data = try edit(currentFeedList?.data ?? OpmlEditor.empty)
            list = try OpenedFeedList(data: data, isSaved: true)
            try savedList.save(data)
        } catch {
            setStatus("\(failure): \(ErrorText.describe(error))")
            return nil
        }

        let note = currentListIsDefault
            ? ""
            : " This feed list is now your default, so it opens every time RSS Quick starts."

        let open = openFolders()
        show(list, isDefault: true)
        reopen(open)

        // Refresh must not bring back a feed that is no longer in the list.
        if let loaded = currentlyLoadedFeed, !loaded.isCategory,
           OpmlEditor.findFeed(list.document.roots, url: loaded.url) == nil {
            currentlyLoadedFeed = nil
        }

        return FeedListChange(list: list, defaultNote: note)
    }

    /// The names of the open folders, with the folders above them.
    ///
    /// By name rather than by item, because a change rebuilds every item. Without this, each
    /// subscription or removal closed every folder, and a reader in a large tree lost their place.
    /// iOS and Windows keep their open folders the same way.
    func openFolders() -> Set<String> {
        var open = Set<String>()
        func walk(_ nodes: [FeedItem], _ prefix: String) {
            for node in nodes where node.isCategory && outline.isItemExpanded(node) {
                let name = prefix.isEmpty ? node.title : "\(prefix) / \(node.title)"
                open.insert(name)
                walk(node.children, name)
            }
        }
        walk(roots, "")
        return open
    }

    func reopen(_ open: Set<String>) {
        func walk(_ nodes: [FeedItem], _ prefix: String) {
            for node in nodes where node.isCategory {
                let name = prefix.isEmpty ? node.title : "\(prefix) / \(node.title)"
                guard open.contains(name) else { continue }
                outline.expandItem(node)
                walk(node.children, name)
            }
        }
        walk(roots, "")
    }

    /// Selects and focuses a node anywhere in the tree, opening the folders above it.
    func selectInTree(_ target: FeedItem) {
        var chain: [FeedItem] = []
        func find(_ nodes: [FeedItem]) -> Bool {
            for node in nodes {
                chain.append(node)
                if node === target || find(node.children) { return true }
                chain.removeLast()
            }
            return false
        }
        guard find(roots) else { return }

        for folder in chain.dropLast() { outline.expandItem(folder) }

        let row = outline.row(forItem: target)
        guard row >= 0 else { return }
        outline.selectRowIndexes([row], byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        window?.makeFirstResponder(outline)
    }
}
