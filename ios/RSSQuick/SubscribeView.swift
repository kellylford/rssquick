import SwiftUI
import UniformTypeIdentifiers

/// Subscribe to Feed: an address, a folder, and a button.
///
/// The address can be the feed's or its website's; `FeedDiscovery` finds the feed a website
/// links to, as it does on the desktop. The sheet stays open on a failure, with the reason under
/// the address, so a typing mistake can be corrected rather than typed again.
struct SubscribeView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Told where the feed went, so the list can open that folder.
    var onSubscribed: (FolderChoice) -> Void = { _ in }

    @State private var address = ""
    @State private var folder: FolderChoice?
    @State private var problem: String?
    @State private var isLooking = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address of the feed or its website", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($addressFocused)
                        .onSubmit(subscribe)
                } footer: {
                    if let problem { Text(problem) }
                }

                Section {
                    Picker("Folder", selection: $folder) {
                        ForEach(store.folderChoices, id: \.self) { choice in
                            Text(choice.name).tag(Optional(choice))
                        }
                    }
                }
            }
            .navigationTitle("Subscribe to Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLooking {
                        ProgressView().accessibilityLabel("Looking for the feed")
                    } else {
                        Button("Subscribe", action: subscribe)
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear {
                folder = folder ?? store.topLevel
                addressFocused = true
            }
        }
    }

    private func subscribe() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLooking else { return }

        isLooking = true
        problem = nil
        Announcer.announce("Looking for a feed at \(text)", after: .zero)

        Task {
            let into = folder ?? store.topLevel
            let result = await store.subscribe(to: text, into: into)
            isLooking = false
            if result.succeeded {
                onSubscribed(into)
                dismiss()
                Announcer.announce(result.message)
            } else {
                problem = result.message
                Announcer.announce(result.message, after: .milliseconds(200))
            }
        }
    }
}

/// The feed list as a file, for Export Feed List.
struct OpmlFile: FileDocument {
    static let opml = UTType(importedAs: "org.opml.opml")
    static var readableContentTypes: [UTType] { [opml, .xml] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
