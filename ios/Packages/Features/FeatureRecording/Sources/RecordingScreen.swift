import AppRouting
import DesignSystem
import Domain
import Localization
import SwiftUI
import UIKit

public struct RecordingScreen: View {
    @Bindable private var controller: RecordingController
    @Environment(AppRouter.self) private var router
    @State private var isAddingNote = false
    @State private var note = ""
    @State private var isTakingPhoto = false

    public init(controller: RecordingController) {
        self.controller = controller
    }

    private var snapshot: RecordingSnapshot {
        controller.snapshot
    }

    private var isPaused: Bool {
        if case .paused = snapshot.status {
            true
        } else {
            false
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.large) {
                Spacer(minLength: 0)
                timer
                WaveformView(levels: controller.levels, isActive: snapshot.status == .recording)
                    .frame(height: 96)
                    .padding(.horizontal, Spacing.medium)
                notices
                markerList
                Group {
                    if snapshot.status == .idle {
                        idleControls
                            .transition(.opacity)
                    } else {
                        activeControls
                            .riseTransition()
                    }
                }
                .motion(Motion.standard, value: snapshot.status == .idle)
            }
            .motion(Motion.standard, value: snapshot.isStorageLow)
            .motion(Motion.standard, value: snapshot.status == .paused(.interruption))
            .sensoryFeedback(.impact(weight: .light), trigger: snapshot.status.isActive)
            .sensoryFeedback(.impact(weight: .light), trigger: snapshot.markers.count)
            .padding(.bottom, Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .toolbar { toolbar }
            .navigationTitle(snapshot.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("screen.recorder")
        .alert(L10n.Recorder.addNote, isPresented: $isAddingNote) {
            TextField(L10n.Recorder.notePlaceholder, text: $note)
            Button(L10n.Common.save) {
                controller.addNote(note)
                note = ""
            }
            Button(L10n.Common.cancel, role: .cancel) { note = "" }
        }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { data in controller.addPhoto(data) }
                .ignoresSafeArea()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(L10n.Recorder.minimize, systemImage: "chevron.down") {
                router.isRecorderPresented = false
            }
            .accessibilityIdentifier("recorder.minimize")
        }
        if snapshot.status.isActive, controller.inputs.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(controller.inputs) { input in
                        Button(input.name) { controller.select(input) }
                    }
                } label: {
                    Label(L10n.Recorder.microphone, systemImage: "mic")
                }
            }
        }
    }

    private var timer: some View {
        VStack(spacing: Spacing.xSmall) {
            Text(snapshot.recorded.clock)
                .font(.dsDisplay)
            Text(statusText)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recorder.time")
    }

    private var statusText: String {
        switch snapshot.status {
        case .idle: L10n.Recorder.statusReady
        case .recording: L10n.Recorder.statusRecording
        case .paused(.user): L10n.Recorder.statusPaused
        case .paused(.interruption): L10n.Recorder.statusInterrupted
        case .finishing: L10n.Recorder.statusFinishing
        }
    }

    @ViewBuilder private var notices: some View {
        if snapshot.status == .paused(.interruption) {
            Notice(text: L10n.Recorder.interruptedMessage, symbol: "phone.down")
        }
        if snapshot.isStorageLow {
            Notice(text: L10n.Recorder.storageLow, symbol: "externaldrive.badge.exclamationmark")
        }
    }

    private var markerList: some View {
        List(snapshot.markers.reversed()) { marker in
            HStack(spacing: Spacing.small) {
                Text(marker.time.clock)
                    .font(.dsTimestamp)
                    .foregroundStyle(Color.dsSecondaryText)
                Image(systemName: marker.kind.symbol)
                    .foregroundStyle(Color.dsAction)
                    .accessibilityHidden(true)
                Text(marker.text ?? marker.kind.title)
            }
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
        .screenList()
        .frame(minHeight: 60, maxHeight: 180)
    }

    private var idleControls: some View {
        CircleButton(title: L10n.Home.record, symbol: "record.circle.fill", size: .large, tint: .dsRecord) {
            controller.record()
        }
        .accessibilityIdentifier("recorder.start")
    }

    private var activeControls: some View {
        VStack(spacing: Spacing.large) {
            HStack(spacing: Spacing.xLarge) {
                CircleButton(title: L10n.Recorder.flag, symbol: "flag", size: .regular) {
                    controller.flag()
                }
                .accessibilityIdentifier("recorder.flag")
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    CircleButton(title: L10n.Recorder.photo, symbol: "camera", size: .regular) {
                        isTakingPhoto = true
                    }
                }
                CircleButton(title: L10n.Recorder.addNote, symbol: "square.and.pencil", size: .regular) {
                    isAddingNote = true
                }
                .accessibilityIdentifier("recorder.note")
            }
            HStack(spacing: Spacing.xLarge) {
                CircleButton(
                    title: isPaused ? L10n.Recorder.resume : L10n.Recorder.pause,
                    symbol: isPaused ? "play.fill" : "pause.fill",
                    size: .regular,
                ) {
                    controller.togglePause()
                }
                .accessibilityIdentifier("recorder.pause")
                CircleButton(title: L10n.Recorder.stop, symbol: "stop.fill", size: .large, tint: .dsRecord) {
                    controller.stop()
                }
                .accessibilityIdentifier("recorder.stop")
            }
        }
        .disabled(snapshot.status == .finishing)
    }
}

private struct Notice: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.dsMeta)
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
            .padding(.horizontal, Spacing.medium)
    }
}

private struct CircleButton: View {
    enum Size {
        case regular, large

        var dimension: CGFloat {
            self == .large ? 84 : 60
        }
    }

    let title: String
    let symbol: String
    let size: Size
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(size == .large ? .dsIconLarge : .dsIcon)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(tint)
                .frame(width: size.dimension, height: size.dimension)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(title)
    }
}

extension MarkerKind {
    var symbol: String {
        switch self {
        case .flag: "flag.fill"
        case .note: "square.and.pencil"
        case .photo: "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .flag: L10n.Recorder.flag
        case .note: L10n.Recorder.addNote
        case .photo: L10n.Recorder.photo
        }
    }
}
