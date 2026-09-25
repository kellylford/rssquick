import SwiftUI
import UniformTypeIdentifiers

/// The feed tree: folders that expand and collapse, and feeds that open their headlines.
struct FeedListView: View {
    @Environment(FeedStore.self) private var store
    @State private var path: [HeadlinesRoute] = []
    @State private var isImporting = false
    @State private var expanded: Set<ObjectIdentifier> = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("RSS Quick")
                .navigationDestination(for: HeadlinesRoute.self) { route in
                    HeadlinesView(source: route.source)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Import OPML File…", systemImage: "square.and.arrow.down") {
                                isImporting = true
                            }
                            if store.isUsingImportedList {
                                Button("Use Starter Feed List", systemImage: "arrow.uturn.backward") {
                                    expanded = []
                                    Announcer.announce(store.restoreStarterList(), after: .milliseconds(200))
                                }
                            }
                        } label: {
                            Label("Feed List", systemImage: "ellipsis.circle")
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
                    FeedNodeRow(node: node, expanded: $expanded) { path.append($0) }
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
    let node: FeedItem
    @Binding var expanded: Set<ObjectIdentifier>
    /// Pushes a headlines screen, for the accessibility action a `NavigationLink` cannot serve.
    let openHeadlines: (HeadlinesRoute) -> Void

    var body: some View {
        if node.isCategory {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { child in
                    FeedNodeRow(node: child, expanded: $expanded, openHeadlines: openHeadlines)
                }
            } label: {
                folderLabel
            }
        } else {
            NavigationLink(value: HeadlinesRoute(source: node)) {
                Text(node.title)
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

    private func showAll() {
        openHeadlines(HeadlinesRoute(source: node))
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expanded.contains(node.id) },
            set: { isOpen in
                if isOpen { expanded.insert(node.id) } else { expanded.remove(node.id) }
            }
        )
    }
}
