import DesignSystem
import Domain
import Localization
import SwiftUI

/// The text of a meeting. Tapping a phrase plays that moment, and the active phrase follows the audio.
struct TranscriptView: View {
    let model: DetailModel
    let proxy: ScrollViewProxy
    @Binding var isFollowing: Bool
    let showsPolished: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing: TranscriptSegment?
    @State private var editedText = ""
    @State private var selectedSpeaker: Speaker?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(model.segments) { segment in
                row(segment)
                    .id(segment.id)
            }
        }
        .padding(.horizontal, Spacing.medium)
        .onChange(of: model.activeSegmentID) { _, id in
            guard isFollowing, model.isPlaying, let id else { return }
            withAnimation(reduceMotion ? nil : Motion.standard) { proxy.scrollTo(id, anchor: .center) }
        }
        .sheet(item: $selectedSpeaker) { speaker in
            SpeakerSheet(speaker: speaker, model: model)
        }
        .alert(L10n.Transcript.edit, isPresented: Binding(
            get: { editing != nil },
            set: {
                if !$0 {
                    editing = nil
                }
            },
        )) {
            TextField(L10n.Transcript.edit, text: $editedText)
            Button(L10n.Common.save) {
                if var segment = editing {
                    segment.text = editedText
                    Task { await model.save(segment) }
                }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
    }

    private func row(_ segment: TranscriptSegment) -> some View {
        let isActive = model.activeSegmentID == segment.id
        return VStack(alignment: .leading, spacing: 0) {
            if let speaker = model.speaker(of: segment), startsTurn(segment, speaker: speaker) {
                Button {
                    selectedSpeaker = speaker
                } label: {
                    SpeakerChip(
                        name: model.name(of: speaker),
                        isNamed: speaker.name != nil,
                        isSuggested: speaker.isSuggested,
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.name(of: speaker))
                .accessibilityHint(speaker.name == nil ? L10n.People.addName : L10n.Transcript.edit)
                .accessibilityIdentifier("speaker.chip")
            }
            phrase(segment, isActive: isActive)
        }
    }

    /// The name repeats only when the speaker changes, like a script.
    private func startsTurn(_ segment: TranscriptSegment, speaker: Speaker) -> Bool {
        guard let index = model.segments.firstIndex(where: { $0.id == segment.id }), index > 0 else { return true }
        return model.segments[index - 1].speaker != speaker.id.uuidString
    }

    private func phrase(_ segment: TranscriptSegment, isActive: Bool) -> some View {
        Button {
            isFollowing = true
            model.play(from: segment.start)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(segment.start.clock)
                    .font(.dsTimestamp)
                    .foregroundStyle(Color.dsSecondaryText)
                Text(showsPolished ? TranscriptPolish.polish(segment.text) : segment.text)
                    .font(.dsRowTitle)
                    .foregroundStyle(Color.dsPrimaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.small)
            .background(isActive ? Color.dsSelection : .clear, in: .rect(cornerRadius: Radius.small))
            .motion(Motion.quick, value: isActive)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.Transcript.edit, systemImage: "pencil") {
                editedText = segment.text
                editing = segment
            }
            if model.speakers.count > 1 {
                Menu(L10n.People.changeSpeaker, systemImage: "person") {
                    ForEach(model.speakers) { speaker in
                        Button(model.name(of: speaker)) {
                            Task { await model.setSpeaker(speaker, for: segment) }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("transcript.segment")
    }
}

/// Looks like something to tap on purpose: the first thing most people want is to put a name on a voice.
private struct SpeakerChip: View {
    let name: String
    let isNamed: Bool
    let isSuggested: Bool

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            HStack(spacing: Spacing.xSmall) {
                Text(name)
                    .font(.dsMeta.bold())
                    .foregroundStyle(Color.dsPrimaryText)
                if isSuggested {
                    Text(L10n.People.suggested)
                        .font(.dsBadge)
                        .foregroundStyle(Color.dsAction)
                } else if !isNamed {
                    Text(L10n.People.addName)
                        .font(.dsBadge)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                Image(systemName: "pencil")
                    .font(.dsBadge)
                    .foregroundStyle(Color.dsSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.compact)
            .padding(.vertical, Spacing.xSmall + 2)
            .background(Color.dsSelection, in: .capsule)
            Spacer(minLength: 0)
        }
        .tappableTarget()
        .padding(.horizontal, Spacing.small)
    }
}

struct FindReplaceView: View {
    let model: DetailModel
    @State private var find = ""
    @State private var replacement = ""
    @State private var result: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.Transcript.find, text: $find)
                    .autocorrectionDisabled()
                TextField(L10n.Transcript.replaceWith, text: $replacement)
                    .autocorrectionDisabled()
                if let result {
                    Text(L10n.Transcript.replaced(result))
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }
            .navigationTitle(L10n.Transcript.findReplace)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.done) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Transcript.replaceAll) {
                        Task { result = await model.replaceAll(find, with: replacement) }
                    }
                    .disabled(find.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
