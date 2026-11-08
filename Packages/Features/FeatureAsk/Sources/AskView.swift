import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

/// Every chat, and the way into a new one.
public struct AskView: View {
    private let controller: AskController
    @State private var chat: ChatModel?
    @State private var renaming: Conversation?
    @State private var name = ""

    public init(controller: AskController) {
        self.controller = controller
    }

    public var body: some View {
        Group {
            if let chat {
                ChatView(model: chat, controller: controller)
                    .id(chat.conversation.id)
                    .transition(Motion.crossfade)
            } else {
                history
                    .transition(Motion.crossfade)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(chat == nil ? L10n.Nav.ask : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task { await controller.reload() }
        .task { await controller.prepareSearch() }
        .modifier(NamePrompt(
            title: L10n.Library.rename,
            isPresented: Binding(get: { renaming != nil }, set: {
                if !$0 {
                    renaming = nil
                }
            }),
            name: $name,
        ) {
            guard let renaming else { return }
            let title = name
            Task { await controller.rename(renaming, to: title) }
        })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.ask")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(L10n.Ask.newChat, systemImage: "square.and.pencil") {
                chat = controller.newChat(scope: .library)
            }
            .accessibilityIdentifier("ask.new")
        }
        if chat != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button(L10n.Ask.history, systemImage: "clock") {
                    chat = nil
                    Task { await controller.reload() }
                }
                .accessibilityIdentifier("ask.history")
            }
        }
    }

    private var history: some View {
        List {
            if let progress = controller.indexing {
                IndexingRow(progress: progress)
                    .listRowBackground(Color.clear)
            }
            ForEach(controller.conversations) { conversation in
                Button {
                    chat = controller.chat(conversation)
                } label: {
                    RowLabel(
                        conversation.title,
                        detail: conversation.updatedAt.formatted(date: .abbreviated, time: .shortened),
                        titleLines: 2,
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tappableTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.conversation")
                .swipeActions {
                    Button(L10n.Ask.delete, systemImage: "trash", role: .destructive) {
                        Task { await controller.delete(conversation) }
                    }
                    Button(L10n.Library.rename, systemImage: "pencil") {
                        name = conversation.title
                        renaming = conversation
                    }
                }
                .contextMenu {
                    Button(L10n.Library.rename, systemImage: "pencil") {
                        name = conversation.title
                        renaming = conversation
                    }
                    Button(L10n.Ask.delete, systemImage: "trash", role: .destructive) {
                        Task { await controller.delete(conversation) }
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .screenList()
        .overlay {
            if controller.conversations.isEmpty, controller.indexing == nil {
                EmptyState(title: L10n.Ask.emptyTitle, message: L10n.Ask.emptyMessage, symbol: "sparkles")
            }
        }
        .safeAreaInset(edge: .bottom) {
            ChatComposer(placeholder: L10n.Ask.placeholder, isBusy: false, onStop: {}) { question in
                let model = controller.newChat(scope: .library)
                chat = model
                Task { await model.send(question) }
            }
        }
    }
}

struct IndexingRow: View {
    let progress: IndexProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            ProgressView(value: progress.fraction)
            Text(L10n.Ask.indexing(progress.done, progress.total))
                .font(.dsNote)
                .foregroundStyle(Color.dsSecondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ask.indexing")
    }
}

/// Opens the chat about one meeting or folder, on top of wherever the person was.
public struct ScopedChatView: View {
    private let controller: AskController
    private let scope: AskScope
    private let skill: Skill?
    @State private var chat: ChatModel?

    public init(controller: AskController, scope: AskScope, skill: Skill? = nil) {
        self.controller = controller
        self.scope = scope
        self.skill = skill
    }

    public var body: some View {
        Group {
            if let chat {
                ChatView(model: chat, controller: controller)
            } else {
                // Must stay a real view: SwiftUI never runs `.task` on an empty one.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if chat == nil {
                let model = skill == nil ? await controller.chat(about: scope) : controller.newChat(scope: scope)
                model.skill = skill
                chat = model
            }
        }
        .task { await controller.prepareSearch() }
    }
}
