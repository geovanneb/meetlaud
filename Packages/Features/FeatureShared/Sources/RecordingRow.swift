import DesignSystem
import Domain
import Localization
import SwiftUI

/// One line for a recording, the same everywhere it appears.
public struct RecordingRow: View {
    private let recording: Recording
    private let progress: JobProgress?
    private let showsDay: Bool

    public init(recording: Recording, progress: JobProgress? = nil, showsDay: Bool = true) {
        self.recording = recording
        self.progress = progress
        self.showsDay = showsDay
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            RowLabel(recording.title, detail: detail)
            if let progress {
                progress.badge
                    .transition(.opacity)
            }
        }
        .motion(Motion.standard, value: progress?.phase)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xSmall)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recording.row")
    }

    private var detail: String {
        var parts = [recording.createdAt.formatted(date: showsDay ? .abbreviated : .omitted, time: .shortened)]
        parts.append(recording.status == .capturing ? L10n.Recorder.statusRecording : recording.duration.clock)
        if recording.wasRecovered {
            parts.append(L10n.Recorder.recovered)
        }
        return parts.joined(separator: " · ")
    }
}

public extension JobProgress {
    var statusText: String {
        switch phase {
        case .queued: L10n.Transcript.queued
        case .preparing: L10n.Transcript.preparing
        case .transcribing: L10n.Transcript.transcribing(fraction.formatted(.percent.precision(.fractionLength(0))))
        case .separatingSpeakers: L10n.Transcript.separatingSpeakers
        case .waitingForDevice: L10n.Transcript.waitingForDevice
        case .waitingForPower: L10n.Transcript.waitingForPower
        }
    }
}

public extension RecordingSort {
    var title: String {
        switch self {
        case .newest: L10n.Library.sortNewest
        case .oldest: L10n.Library.sortOldest
        case .name: L10n.Library.sortName
        case .longest: L10n.Library.sortLongest
        }
    }

    /// One stored choice, so that Home and Library stay in the same order.
    static let storageKey = "library.sort"
}

/// Asks for a name. Used for recordings and folders alike.
public struct NamePrompt: ViewModifier {
    private let title: String
    @Binding private var isPresented: Bool
    @Binding private var name: String
    private let onSave: () -> Void

    public init(title: String, isPresented: Binding<Bool>, name: Binding<String>, onSave: @escaping () -> Void) {
        self.title = title
        _isPresented = isPresented
        _name = name
        self.onSave = onSave
    }

    public func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            TextField(L10n.Library.namePlaceholder, text: $name)
            Button(L10n.Common.save, action: onSave)
            Button(L10n.Common.cancel, role: .cancel) {}
        }
    }
}
