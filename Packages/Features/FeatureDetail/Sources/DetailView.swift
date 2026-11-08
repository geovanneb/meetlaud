import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI
import UIKit

public struct DetailView: View {
    /// Parents can redraw at any time, and the model loaded for this screen must survive that.
    @State private var model: DetailModel
    @State private var isRenaming = false
    @State private var name = ""
    @State private var tab = Tab.transcript
    @State private var isFindingAndReplacing = false
    @State private var isExporting = false
    @State private var isFollowing = true
    @State private var versions: [TranscriptVersion] = []
    @State private var restoring: TranscriptVersion?
    @State private var pendingStart: PendingStart?
    @AppStorage("transcript.polished") private var showsPolished = false
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Tab: Hashable {
        case summary, transcript, notes
    }

    public init(model: @autoclosure @escaping () -> DetailModel) {
        _model = State(wrappedValue: model())
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu(L10n.Library.more, systemImage: "ellipsis") {
                        Button(L10n.Library.rename, systemImage: "pencil") {
                            name = model.recording?.title ?? ""
                            isRenaming = true
                        }
                        if !model.segments.isEmpty {
                            Toggle(L10n.Transcript.polish, systemImage: "wand.and.stars", isOn: $showsPolished)
                                .accessibilityIdentifier("detail.polish")
                            Button(L10n.Transcript.findReplace, systemImage: "text.magnifyingglass") {
                                isFindingAndReplacing = true
                            }
                            Menu(L10n.Transcript.retranscribe, systemImage: "arrow.clockwise") {
                                languageButtons
                            }
                            if !versions.isEmpty {
                                Menu(L10n.Transcript.earlier, systemImage: "clock.arrow.circlepath") {
                                    ForEach(versions) { version in
                                        Button(version.savedAt.formatted(date: .abbreviated, time: .shortened)) {
                                            restoring = version
                                        }
                                    }
                                }
                                .accessibilityIdentifier("detail.versions")
                            }
                        }
                        Button(L10n.Detail.export, systemImage: "square.and.arrow.up") { isExporting = true }
                            .accessibilityIdentifier("detail.export")
                        Button(L10n.Library.moveToTrash, systemImage: "trash", role: .destructive) {
                            Task {
                                await model.moveToTrash()
                                router.pop()
                            }
                        }
                    }
                    .accessibilityIdentifier("detail.more")
                }
            }
            .modifier(NamePrompt(title: L10n.Library.rename, isPresented: $isRenaming, name: $name) {
                let title = name
                Task { await model.rename(to: title) }
            })
            .alert(
                L10n.Transcript.restoreTitle,
                isPresented: Binding(get: { restoring != nil }, set: {
                    if !$0 {
                        restoring = nil
                    }
                }),
            ) {
                Button(L10n.Transcript.restore) {
                    guard let version = restoring else { return }
                    Task {
                        await model.restore(version)
                        versions = await model.versions()
                    }
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text(L10n.Transcript.restoreMessage)
            }
            .confirmationDialog(
                L10n.Transcript.planTitle,
                isPresented: Binding(get: { pendingStart != nil }, set: {
                    if !$0 {
                        pendingStart = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: pendingStart,
            ) { pending in
                Button(L10n.Transcript.startNow) { begin(pending.language, whenCharging: false) }
                    .accessibilityIdentifier("transcript.startNow")
                if pending.plan.canWaitForCharger {
                    Button(L10n.Transcript.startWhenCharging) { begin(pending.language, whenCharging: true) }
                        .accessibilityIdentifier("transcript.startWhenCharging")
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: { pending in
                Text(pending.plan.message)
            }
            .sheet(isPresented: $isFindingAndReplacing) { FindReplaceView(model: model) }
            .sheet(isPresented: $isExporting) { ExportSheet(model: model) }
            .onChange(of: model.progress) { _, _ in
                Task {
                    await model.refreshTranscript()
                    versions = await model.versions()
                }
            }
            .onChange(of: model.summarySteps) { _, _ in
                Task { await model.refreshSummaries() }
            }
            .task {
                await model.load()
                versions = await model.versions()
                if model.opensOnSummary {
                    tab = .summary
                }
            }
            .task { await model.trackPlayback() }
            .onDisappear { model.close() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.detail")
    }

    @ViewBuilder private var content: some View {
        if model.failed {
            EmptyState(
                title: L10n.Detail.unavailableTitle,
                message: L10n.Detail.unavailableMessage,
                symbol: "exclamationmark.triangle",
            )
        } else if let recording = model.recording {
            VStack(spacing: 0) {
                scrollingContent(recording)
                if !model.segments.isEmpty {
                    AskBar(id: recording.id)
                }
                if model.hasAudio {
                    player
                }
            }
        } else {
            // Must stay a real view: SwiftUI never runs `.task` on an empty one, so nothing would load.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One page: the title scrolls away with the content, and the tabs stay within reach under the bar.
    private func scrollingContent(_ recording: Recording) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    header(recording)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.medium)
                        .padding(.bottom, Spacing.small)
                    Section {
                        tabContent(proxy)
                            .id(tab)
                            .transition(Motion.crossfade)
                    } header: {
                        tabPicker
                    }
                }
            }
            .scrollEdgeEffectHidden(true, for: .bottom)
            // Only a drag by the person stops following. Automatic scrolling must not count.
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in isFollowing = false })
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if showsBackToCurrent {
                        backToCurrent(proxy).riseTransition()
                    }
                }
                .motion(Motion.standard, value: showsBackToCurrent)
            }
        }
    }

    private var showsBackToCurrent: Bool {
        tab == .transcript && !isFollowing && model.isPlaying
    }

    private func backToCurrent(_ proxy: ScrollViewProxy) -> some View {
        Button(L10n.Transcript.backToCurrent) {
            isFollowing = true
            if let id = model.activeSegmentID {
                withAnimation(reduceMotion ? nil : Motion.standard) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .secondaryAction(.regular)
        .padding(Spacing.medium)
        .accessibilityIdentifier("transcript.backToCurrent")
    }

    private var tabPicker: some View {
        Picker(L10n.Detail.section, selection: $tab) {
            Text(L10n.Summary.title).tag(Tab.summary)
            Text(L10n.Transcript.title).tag(Tab.transcript)
            Text(L10n.Detail.moments).tag(Tab.notes)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .background(Color.dsBackground)
    }

    @ViewBuilder private func tabContent(_ proxy: ScrollViewProxy) -> some View {
        switch tab {
        case .summary: SummaryTab(model: model) { tab = .transcript }
        case .transcript: transcriptTab(proxy)
        case .notes: MomentsTab(model: model)
        }
    }

    @ViewBuilder private func transcriptTab(_ proxy: ScrollViewProxy) -> some View {
        if let progress = model.progress {
            VStack(spacing: Spacing.small) {
                ProgressView(value: progress.fraction)
                Text(progress.statusText)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                    .accessibilityIdentifier("transcript.status")
                Button(L10n.Common.cancel) {
                    Task { await model.cancelTranscription() }
                }
            }
            .padding(Spacing.medium)
        }
        if model.segments.isEmpty, model.progress == nil {
            VStack(spacing: Spacing.medium) {
                Text(L10n.Transcript.emptyMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.dsSecondaryText)
                Menu(L10n.Transcript.transcribe) {
                    languageButtons
                }
                .primaryAction()
                .accessibilityIdentifier("transcript.start")
            }
            .padding(Spacing.large)
            .frame(maxWidth: .infinity)
            .fillsTab()
        } else {
            TranscriptView(model: model, proxy: proxy, isFollowing: $isFollowing, showsPolished: showsPolished)
        }
    }
}

private extension DetailView {
    @ViewBuilder var languageButtons: some View {
        Button(L10n.Transcript.detectLanguage) { start(language: nil) }
        ForEach(["en", "ja", "pt", "es"], id: \.self) { code in
            Button(Locale.current.localizedString(forLanguageCode: code) ?? code) { start(language: code) }
        }
    }

    /// A long job, or a device that is not at its best, gets a word before it starts.
    func start(language: String?) {
        Task {
            if let plan = await model.transcribePlan(language: language), plan.deservesNote {
                pendingStart = PendingStart(language: language, plan: plan)
            } else {
                begin(language, whenCharging: false)
            }
        }
    }

    func begin(_ language: String?, whenCharging: Bool) {
        Task {
            if await model.transcribe(language: language, whenCharging: whenCharging) == .needsModel {
                router.push(.modelSettings)
            }
        }
    }
}

private extension DetailView {
    func header(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(recording.title)
                .font(.dsPageTitle)
                .accessibilityAddTraits(.isHeader)
            Text(summary(recording))
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
        }
    }

    func summary(_ recording: Recording) -> String {
        var parts = [
            recording.createdAt.formatted(date: .abbreviated, time: .shortened),
            recording.duration.clock,
        ]
        if recording.wasRecovered {
            parts.append(L10n.Recorder.recovered)
        }
        if !recording.attendees.isEmpty {
            parts.append(recording.attendees.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    var player: some View {
        PlayerBar(
            time: model.time,
            duration: model.duration,
            isPlaying: model.isPlaying,
            markers: model.markers.map(\.time),
            rate: model.rate,
            labels: PlayerBarLabels(
                play: L10n.Detail.play,
                pause: L10n.Recorder.pause,
                back: L10n.Detail.back,
                forward: L10n.Detail.forward,
                position: L10n.Detail.position,
                speed: L10n.Detail.speed,
            ),
            onSeek: model.seek,
            onToggle: model.togglePlayback,
            onRate: model.setRate,
        )
    }
}

private struct PendingStart {
    let language: String?
    let plan: TranscribePlan
}

private extension TranscribePlan {
    var message: String {
        var lines: [String] = []
        if let minutes {
            lines.append(minutes.lowerBound == minutes.upperBound
                ? L10n.Transcript.planMinutes(minutes.upperBound)
                : L10n.Transcript.planMinutesRange(minutes.lowerBound, minutes.upperBound))
        } else {
            lines.append(L10n.Transcript.planUnknownTime)
        }
        lines.append(rightNow.title)
        if let detail = rightNow.detail {
            lines.append(detail)
        }
        return lines.joined(separator: "\n")
    }
}
