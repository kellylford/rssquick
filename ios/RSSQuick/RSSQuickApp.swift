import SwiftUI

@main
struct RSSQuickApp: App {
    @State private var store = FeedStore()

    var body: some Scene {
        WindowGroup {
            FeedListView()
                .environment(store)
        }
    }
}
