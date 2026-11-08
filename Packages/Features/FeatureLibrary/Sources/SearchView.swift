import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

public struct SearchView: View {
    private let library: LibraryController
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var isPresented = true

    public init(library: LibraryController) {
        self.library = library
    }

    public var body: some View {
        Group {
            if hits.isEmpty {
                EmptyState(
                    title: query.isEmpty ? L10n.Library.search : L10n.Library.noResults,
                    message: L10n.Library.searchHint,
                    symbol: "magnifyingglass",
                )
            } else {
                List(hits) { hit in
                    Button {
                        router.push(.recording(hit.recording.id, at: hit.time))
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            RecordingRow(recording: hit.recording)
                            if let excerpt = hit.excerpt {
                                Text([(hit.time ?? 0).clock, excerpt].joined(separator: " · "))
                                    .font(.dsMeta)
                                    .foregroundStyle(Color.dsSecondaryText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                .screenList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Library.search)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isPresented, prompt: L10n.Library.search)
        .task(id: query) {
            // Waits for a pause in typing, and is canceled by the next keystroke.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            hits = await library.search(query)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.search")
    }
}
