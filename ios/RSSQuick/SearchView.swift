import SwiftUI

/// Search All Feeds: fetch every feed in the list and show the headlines that match.
///
/// The same search as the desktop versions, from `HeadlineSearch`: every word has to appear in the
/// headline or its feed's name, ignoring case and accents. There is no cache, so each search
/// fetches the whole list; it starts when the reader presses Search on the keyboard rather than
/// on every letter typed, and leaving the screen stops it.
struct SearchView: View {
    @Environment(FeedStore.self) private var store

    private enum Phase {
        case idle
        case searching(feeds: Int)
        case done(summary: String)
    }

    @State private var query = ""
    /// The search that was submitted, which is what runs. Changing it cancels the one before.
    @State private var submitted: String?
    @State private var phase = Phase.idle
    @State private var results: [ArticleItem] = []
    @State private var reading: ArticleItem?

    var body: some View {
        content
            .navigationTitle("Search All Feeds")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Words in a headline")
            .onSubmit(of: .search) {
                let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !HeadlineSearch.words(text).isEmpty { submitted = text }
            }
            .task(id: submitted) { await run() }
            .fullScreenCover(item: $reading) { article in
                if let url = HeadlinesView.readableURL(article.link) {
                    SafariView(url: url).ignoresSafeArea()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            ContentUnavailableView(
                "Search Every Feed",
                systemImage: "magnifyingglass",
                description: Text("Type words to find in the headlines of every feed in your list, then press Search.")
            )

        case .searching(let feeds):
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching \(FeedStore.feeds(feeds))…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .done(let summary) where results.isEmpty:
            ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text(summary))

        case .done(let summary):
            List {
                Section {
                    ForEach(results) { article in
                        HeadlineRow(article: article, showsFeed: true) { open(article) }
                    }
                } header: {
                    Text(summary)
                }
            }
            .listStyle(.plain)
        }
    }

    private func open(_ article: ArticleItem) {
        guard HeadlinesView.readableURL(article.link) != nil else {
            Announcer.announce("This headline has no link to open.", after: .zero)
            return
        }
        reading = article
    }

    private func run() async {
        guard let query = submitted else { return }

        let feeds = HeadlineSearch.feedsToSearch(store.roots)
        guard !feeds.isEmpty else {
            phase = .done(summary: "There are no feeds to search. Import a feed list first.")
            return
        }

        phase = .searching(feeds: feeds.count)
        results = []
        Announcer.announce(HeadlineSearch.describeStart(query, feedCount: feeds.count), after: .zero)

        do {
            let result = try await FeedLoader.loadFolder(feeds)
            guard !Task.isCancelled else { return }
            results = HeadlineSearch.filter(result.articles, query: query)
            let summary = HeadlineSearch.describe(query, matches: results.count, result: result)
            phase = .done(summary: summary)
            Announcer.announce(summary)
        } catch {
            // Leaving the screen, or a newer search, cancels this one. Nothing worth saying.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            let summary = "Could not search. \(ErrorText.describe(error))"
            phase = .done(summary: summary)
            Announcer.announce(summary)
        }
    }
}
