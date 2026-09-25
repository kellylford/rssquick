import SafariServices
import SwiftUI

/// The headlines of one feed, or of every feed in a folder merged newest first.
struct HeadlinesView: View {
    let source: FeedItem

    private enum Phase {
        case loading(done: Int, of: Int)
        case loaded
        case failed(String)
    }

    @State private var phase = Phase.loading(done: 0, of: 0)
    @State private var articles: [ArticleItem] = []
    @State private var failures: [FeedFailure] = []
    @State private var reading: ArticleItem?
    /// Bumped by every load, so a slow load that finishes after a newer one cannot overwrite it.
    @State private var generation = 0

    var body: some View {
        content
            .navigationTitle(source.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Pull to refresh is there too, but it is a gesture a VoiceOver user has to
                    // know about. A button is findable by swiping.
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                    .disabled(isLoading)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .fullScreenCover(item: $reading) { article in
                if let url = Self.readableURL(article.link) {
                    SafariView(url: url).ignoresSafeArea()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading(let done, let total) where articles.isEmpty:
            VStack(spacing: 12) {
                ProgressView()
                Text(total > 1 ? "Loading \(done) of \(total) feeds…" : "Loading…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let reason) where articles.isEmpty:
            ContentUnavailableView {
                Label("Could Not Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(reason)
            } actions: {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }

        default:
            List {
                if !failures.isEmpty {
                    Section {
                        DisclosureGroup(failureSummary) {
                            ForEach(failures, id: \.feedTitle) { failure in
                                Text("\(failure.feedTitle) \(failure.reason)")
                                    .font(.callout)
                            }
                        }
                    }
                }

                Section {
                    ForEach(articles) { article in
                        HeadlineRow(article: article, showsFeed: source.isCategory) {
                            open(article)
                        }
                    }
                } footer: {
                    if articles.isEmpty { Text("This feed has no headlines right now.") }
                }
            }
            .listStyle(.plain)
        }
    }

    private var isLoading: Bool {
        if case .loading = phase { true } else { false }
    }

    private var failureSummary: String {
        let attempted = source.allFeeds.count
        return "\(failures.count) of \(attempted) feeds could not be loaded"
    }

    private func open(_ article: ArticleItem) {
        guard Self.readableURL(article.link) != nil else {
            Announcer.announce("This headline has no link to open.", after: .zero)
            return
        }
        reading = article
    }

    /// SFSafariViewController takes http and https only, and throws on anything else.
    private static func readableURL(_ link: String) -> URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    private func load() async {
        generation += 1
        let mine = generation
        let feeds = source.allFeeds
        phase = .loading(done: 0, of: feeds.count)

        if source.isCategory {
            do {
                let result = try await FeedLoader.loadFolder(feeds) { done in
                    Task { @MainActor in
                        if mine == generation, case .loading = phase {
                            phase = .loading(done: done, of: feeds.count)
                        }
                    }
                }
                guard mine == generation else { return }
                articles = result.articles
                failures = result.failures
                phase = .loaded
                Announcer.announce(folderSummary(result))
            } catch {
                finish(mine, failedWith: error)
            }
        } else {
            do {
                let loaded = try await FeedLoader.loadFeed(source)
                guard mine == generation else { return }
                articles = loaded
                failures = []
                phase = .loaded
                Announcer.announce(Self.headlines(loaded.count))
            } catch {
                finish(mine, failedWith: error)
            }
        }
    }

    private func finish(_ mine: Int, failedWith error: Error) {
        // Leaving the screen cancels the load. That is not a failure worth saying anything about.
        guard mine == generation, !Task.isCancelled, !(error is CancellationError) else { return }
        let reason = "This feed \(ErrorText.describe(error))."
        phase = .failed(reason)
        Announcer.announce(articles.isEmpty ? reason : "Refresh failed. \(reason)")
    }

    private func folderSummary(_ result: FolderLoadResult) -> String {
        let headlines = Self.headlines(result.articles.count)
        guard !result.failures.isEmpty else { return headlines }
        return "\(headlines). \(result.failures.count) of \(result.feedsAttempted) feeds could not be loaded."
    }

    private static func headlines(_ count: Int) -> String {
        count == 1 ? "1 headline" : "\(count) headlines"
    }
}

/// One headline. The title comes first and stands alone, so a braille display shows the part
/// that matters without the reader panning past a date to find it.
private struct HeadlineRow: View {
    let article: ArticleItem
    let showsFeed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(article.title)
        .accessibilityValue(details)
        .accessibilityAddTraits(.isLink)
        .accessibilityRemoveTraits(.isButton)
    }

    /// The feed is named only in a folder's merged list, where nothing else says which feed a
    /// headline came from. The same rule the macOS version uses.
    private var details: String {
        [showsFeed ? article.feedTitle : "", article.published]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// Safari, inside the app, so Done returns to the same place in the headlines.
///
/// The desktop versions hand articles to the system browser. On a phone that is a trip to another
/// app and a hunt for the way back; this keeps Safari's Reader and its content blockers without
/// leaving the list.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
