import SwiftUI
import UniformTypeIdentifiers

/// The feed tree: folders that expand and collapse, and feeds that open their headlines.
struct FeedListView: View {
    @Environment(FeedStore.self) private var store
    @State private var path: [HeadlinesRoute] = []
    @State private var isImporting = false
    @State private var isSubscribing = false
    @State private var isExporting = false
    @State private var isSearching = false
    /// Open folders, by name with the folders above them ("News / Wires"), the same form as
    /// `FolderChoice.name`. By name rather than by object, so a folder stays open when
    /// subscribing or removing a feed rebuilds the tree underneath it.
    @State private var expanded: Set<String> = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("RSS Quick")
                .navigationDestination(for: HeadlinesRoute.self) { route in
                    HeadlinesView(source: route.source)
                }
                .navigationDestination(isPresented: $isSearching) {
                    SearchView()
                }
                .toolbar {
                    // Its own button rather than a menu item, because it is the one reached for
                    // most. Command-F from a hardware keyboard, as on the Mac.
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Search All Feeds", systemImage: "magnifyingglass") {
                            isSearching = true
                        }
                        .keyboardShortcut("f", modifiers: .command)
                        .disabled(store.roots.isEmpty)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Subscribe to Feed…", systemImage: "plus") {
                                isSubscribing = true
                            }
                            Button("Import OPML File…", systemImage: "square.and.arrow.down") {
                                isImporting = true
                            }
                            Button("Export Feed List…", systemImage: "square.and.arrow.up") {
                                isExporting = true
                            }
                            .disabled(store.exportData == nil)
                            // Dimmed rather than hidden when there is nothing for them to do, so
                            // VoiceOver reads them as unavailable and the reader learns they exist.
                            Button("Make This My Default Feed List", systemImage: "star") {
                                Announcer.announce(store.makeCurrentListDefault(), after: .milliseconds(200))
                            }
                            .disabled(!store.canMakeDefault)
                            Button("Use Starter Feed List", systemImage: "arrow.uturn.backward") {
                                expanded = []
                                Announcer.announce(store.restoreStarterList(), after: .milliseconds(200))
                            }
                            .disabled(!store.hasSavedList)
                        } label: {
                            Label("Feed List", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .task {
                    // Said once the screen is up: without it the reader has no way to know the
                    // list in front of them is not their own.
                    if let problem = store.takeStartupProblem() { Announcer.announce(problem) }
                }
                .sheet(isPresented: $isSubscribing) {
                    // Opens the folder the feed went into, and those above it, so the new feed
                    // is there to be found.
                    SubscribeView { folder in
                        var name = ""
                        for part in folder.name.components(separatedBy: " / ") {
                            name = name.isEmpty ? part : "\(name) / \(part)"
                            expanded.insert(name)
                        }
                    }
                }
                // On a view of its own: a fileExporter and a fileImporter on the same view
                // interfere, and only one of them presents.
                .background {
                    Color.clear.fileExporter(
                        isPresented: $isExporting,
                        document: store.exportData.map(OpmlFile.init(data:)),
                        contentType: OpmlFile.opml,
                        defaultFilename: "RSS Quick Feeds"
                    ) { result in
                        switch result {
                        case .success(let url):
                            Announcer.announce("Exported \(FeedStore.feeds(store.feedCount)) to \(url.lastPathComponent).")
                        case .failure(let error):
                            Announcer.announce("Could not export the feed list. \(error.localizedDescription)")
                        }
                    }
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: Self.importTypes
                ) { result in
                    switch result {
                    case .success(let url):
                        expanded = []
                        Announcer.announce(store.importList(from: url))
                    case .failure(let error):
                        Announcer.announce("Could not open the file. \(error.localizedDescription)")
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.loadError, store.roots.isEmpty {
            ContentUnavailableView {
                Label("No Feeds", systemImage: "dot.radiowaves.up.forward")
            } description: {
                Text(error)
            } actions: {
                Button("Import OPML File…") { isImporting = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                ForEach(store.roots) { node in
                    FeedNodeRow(node: node, name: node.title, expanded: $expanded) { path.append($0) }
                }
            }
            .listStyle(.sidebar)
        }
    }

    /// OPML has no system-declared type, so the Info.plist declares one. Plain XML is allowed as
    /// well because plenty of exporters save a feed list as .xml.
    private static let importTypes: [UTType] = [UTType(importedAs: "org.opml.opml"), .xml]
}

/// One node of the tree, and everything under it.
private struct FeedNodeRow: View {
    @Environment(FeedStore.self) private var store
    let node: FeedItem
    /// The folder's name with those above it, which is its key in `expanded`.
    let name: String
    @Binding var expanded: Set<String>
    /// Pushes a headlines screen, for the accessibility action a `NavigationLink` cannot serve.
    let openHeadlines: (HeadlinesRoute) -> Void

    var body: some View {
        if node.isCategory {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { child in
                    FeedNodeRow(node: child, name: "\(name) / \(child.title)", expanded: $expanded, openHeadlines: openHeadlines)
                }
            } label: {
                folderLabel
            }
        } else {
            NavigationLink(value: HeadlinesRoute(source: node)) {
                Text(node.title)
            }
            // A swipe for touch, and the same action in VoiceOver's actions rotor, which is where
            // a swipe action appears for a VoiceOver user. No confirmation: that is how removing
            // a row works everywhere else on iOS.
            .swipeActions {
                Button("Remove", systemImage: "trash", role: .destructive, action: remove)
            }
            .contextMenu {
                Button("Remove Feed", systemImage: "trash", role: .destructive, action: remove)
            }
        }
    }

    /// Folders are set apart by weight and by the feed count, never by colour alone.
    ///
    /// Reading every feed in a folder at once, which Enter does on Windows, is offered as an
    /// action rather than as the tap: the tap has to be expand and collapse, because that is what
    /// a disclosure row does everywhere else on iOS.
    private var folderLabel: some View {
        let count = node.allFeeds.count
        return HStack {
            Text(node.title).fontWeight(.semibold)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("\(node.title), \(FeedStore.feeds(count))")
        .contextMenu {
            Button("Show All Headlines", systemImage: "list.bullet", action: showAll)
        }
        .accessibilityAction(named: "Show all headlines") {
            showAll()
        }
    }

    private func remove() {
        Announcer.announce(store.remove(node), after: .milliseconds(300))
    }

    private func showAll() {
        openHeadlines(HeadlinesRoute(source: node))
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expanded.contains(name) },
            set: { isOpen in
                if isOpen { expanded.insert(name) } else { expanded.remove(name) }
            }
        )
    }
}
