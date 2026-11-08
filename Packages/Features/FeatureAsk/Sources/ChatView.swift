import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

struct ChatView: View {
    let model: ChatModel
    let controller: AskController
    @State private var scopeTitle: String?
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var suggestions: [String] {
        [L10n.Ask.suggestDecisions, L10n.Ask.suggestTasks, L10n.Ask.suggestRisks]
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.medium) {
                    // In the content, not the toolbar: toolbars keep a fixed size, and this name can be long.
                    scopeMenu
                    if let skill = model.skill {
                        Label(L10n.Skills.active(skill.displayName), systemImage: "wand.and.stars")
                            .font(.dsMeta)
                            .foregroundStyle(Color.dsSecondaryText)
                            .accessibilityIdentifier("ask.skill")
                    }
                    if !model.hasLanguageModel {
                        needsModel
                    }
                    if model.messages.isEmpty, !model.isBusy {
                        suggestionList
                    }
                    ForEach(model.messages) { message in
                        MessageView(message: message) { citation in
                            router.push(.recording(citation.recordingID, at: citation.time))
                        }
                        .riseTransition()
                    }
                    if model.isBusy {
                        activity
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            // Keeps the latest message in view when the keyboard or the prompt changes the space.
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .motion(Motion.standard, value: model.messages.count)
            .onChange(of: model.messages.count) { _, _ in
                withAnimation(reduceMotion ? nil : Motion.standard) { reader.scrollTo("end") }
            }
            .onChange(of: model.partial) { _, _ in reader.scrollTo("end") }
        }
        .safeAreaInset(edge: .bottom) {
            ChatComposer(placeholder: L10n.Ask.placeholder, isBusy: model.isBusy, onStop: model.stop) { question in
                Task { await model.send(question) }
            }
        }
        .task {
            await model.load()
            await loadScopeTitle()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask.chat")
    }

    private var needsModel: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(L10n.Ask.needsModel)
                .foregroundStyle(Color.dsSecondaryText)
            Button(L10n.Ask.getModel) { router.push(.modelSettings) }
                .secondaryAction(.regular)
        }
        .accessibilityIdentifier("ask.needsModel")
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button(suggestion) {
                    Task { await model.send(suggestion) }
                }
                .secondaryAction(.regular)
                .disabled(!model.hasLanguageModel)
                .accessibilityIdentifier("ask.suggestion")
            }
        }
    }

    @ViewBuilder private var activity: some View {
        if model.partial.isEmpty {
            HStack(spacing: Spacing.small) {
                ProgressView()
                Text(statusText)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ask.status")
        } else {
            Text(model.partial)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier("ask.partial")
        }
    }

    private var statusText: String {
        switch model.status {
        case .waiting: L10n.Ask.statusWaiting
        case .writing: L10n.Ask.statusWriting
        case .idle, .searching: L10n.Ask.statusSearching
        }
    }

    private var scopeMenu: some View {
        Menu {
            Button(L10n.Ask.scopeLibrary) { choose(.library) }
            ForEach(controller.folders) { folder in
                Button(folder.name) { choose(.folder(folder.id)) }
            }
        } label: {
            HStack(spacing: Spacing.xSmall) {
                Text(scopeLabel)
                    .font(.dsMeta.bold())
                    .foregroundStyle(Color.dsPrimaryText)
                Image(systemName: "chevron.down")
                    .font(.dsBadge)
                    .foregroundStyle(Color.dsPrimaryText)
                    .accessibilityHidden(true)
            }
            .tappableTarget()
        }
        .accessibilityLabel(L10n.Ask.scope)
        .accessibilityValue(scopeLabel)
        .accessibilityIdentifier("ask.scope")
    }

    private var scopeLabel: String {
        switch model.conversation.scope {
        case .library: L10n.Ask.scopeLibrary
        case let .folder(id): controller.folders.first { $0.id == id }?.name ?? L10n.Ask.scopeLibrary
        case .recording: scopeTitle ?? L10n.Ask.scopeMeeting
        }
    }

    private func choose(_ scope: AskScope) {
        Task { await model.setScope(scope) }
    }

    private func loadScopeTitle() async {
        if let id = model.conversation.scope.recordingID {
            scopeTitle = await controller.title(of: id)
        }
    }
}

private struct MessageView: View {
    let message: ChatMessage
    let onOpen: (Citation) -> Void

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: Spacing.xLarge)
                Text(message.body)
                    .padding(Spacing.compact)
                    .background(Color.dsSelection, in: .rect(cornerRadius: Radius.medium))
                    .textSelection(.enabled)
            }
            .accessibilityIdentifier("ask.question")
        } else {
            VStack(alignment: .leading, spacing: Spacing.small) {
                if !text.isEmpty {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(message.state == .complete ? Color.dsPrimaryText : Color.dsSecondaryText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("ask.answer")
                }
                if message.state == .stopped {
                    Text(L10n.Ask.stopped)
                        .font(.dsNote)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                ForEach(message.citations, id: \.number) { citation in
                    Button { onOpen(citation) } label: { CitationLabel(citation: citation) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.Ask.openSource(citation.recordingTitle, citation.time.clock))
                        .accessibilityHint(citation.excerpt)
                        .accessibilityIdentifier("ask.citation")
                }
            }
        }
    }

    private var text: String {
        switch message.state {
        case .complete, .stopped: message.body
        case .noBasis: L10n.Ask.noBasis
        case .remembered: L10n.Ask.remembered(message.body)
        case .failed: L10n.Ask.failed
        }
    }
}

private struct CitationLabel: View {
    let citation: Citation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Text(verbatim: "\(citation.number)")
                .font(.dsTimestamp.bold())
                .foregroundStyle(Color.dsAction)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(citation.recordingTitle) · \(citation.time.clock)")
                    .font(.dsNote.bold())
                    .foregroundStyle(Color.dsPrimaryText)
                Text(citation.excerpt)
                    .font(.dsNote)
                    .foregroundStyle(Color.dsSecondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.compact)
        .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
        .contentShape(.rect)
    }
}

/// Where a question is typed. It is the bar from Home, opened: same size, same place, and same surface.
struct ChatComposer: View {
    let placeholder: String
    let isBusy: Bool
    let onStop: () -> Void
    let onSend: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    /// The round button inside the 44-point tap target, which leaves even margins at a height of one line.
    private static let buttonSize: CGFloat = 36

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xSmall) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1 ... 5)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(.vertical, Spacing.compact - 1)
                .frame(minHeight: 44)
                .accessibilityIdentifier("ask.prompt")
            actionButton
        }
        .padding(.leading, PromptMetrics.textInset)
        .padding(.trailing, Spacing.xSmall)
        .padding(.vertical, (PromptMetrics.minimumHeight - 44) / 2)
        .glassEffect(.regular, in: .rect(cornerRadius: PromptMetrics.cornerRadius))
        // The whole surface is the field, not only the text.
        .contentShape(.rect(cornerRadius: PromptMetrics.cornerRadius))
        .onTapGesture { isFocused = true }
        .promptPlacement()
    }

    private var isActive: Bool {
        isBusy || canSend
    }

    /// One button that changes, so that sending and stopping happen in the same place under the same finger.
    private var actionButton: some View {
        Button {
            if isBusy {
                onStop()
            } else {
                let question = text
                text = ""
                onSend(question)
            }
        } label: {
            Label(isBusy ? L10n.Ask.stop : L10n.Ask.send, systemImage: isBusy ? "stop.fill" : "arrow.up")
                .labelStyle(.iconOnly)
                .font(.dsHeading)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isActive ? Color.dsOnAction : Color.dsSecondaryText)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(isActive ? Color.dsAction : Color.dsSelection, in: .circle)
                .tappableTarget()
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
        .motion(Motion.quick, value: isActive)
        .motion(Motion.quick, value: isBusy)
        .accessibilityIdentifier(isBusy ? "ask.stop" : "ask.send")
    }
}
