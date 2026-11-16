import AppRouting
import Domain
import Foundation
import Localization
import Observation

/// Connects the recording screens to the coordinator. There is one for the life of the app.
@MainActor
@Observable
public final class RecordingController {
    public private(set) var snapshot = RecordingSnapshot()
    public private(set) var levels: [Float] = []
    public private(set) var inputs: [AudioInput] = []
    public private(set) var recoveredCount = 0
    public var showsConsent = false
    public var showsPermissionDenied = false
    public var showsStartFailure = false

    @ObservationIgnored private let coordinator: RecordingCoordinator
    @ObservationIgnored private let permission: any MicrophonePermission
    @ObservationIgnored private let router: AppRouter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pendingTitle: String?
    @ObservationIgnored private var pendingAttendees: [String] = []

    /// Called with each finished recording, so that the rest of the app can react.
    @ObservationIgnored public var onSaved: ((RecordingID) -> Void)?
    /// Called when capture starts and ends. Anything heavy has to step aside for it.
    @ObservationIgnored public var onActivityChanged: ((Bool) -> Void)?

    private static let consentKey = "recorder.hasSeenConsent"
    private static let maximumLevels = 200

    public init(
        coordinator: RecordingCoordinator,
        permission: any MicrophonePermission,
        router: AppRouter,
        defaults: UserDefaults = .standard,
    ) {
        self.coordinator = coordinator
        self.permission = permission
        self.router = router
        self.defaults = defaults
        task = Task { [weak self] in
            for await snapshot in coordinator.snapshots {
                self?.apply(snapshot)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    private func apply(_ next: RecordingSnapshot) {
        if next.status == .recording, next.recorded != snapshot.recorded {
            levels.append(next.level)
            if levels.count > Self.maximumLevels {
                levels.removeFirst(levels.count - Self.maximumLevels)
            }
        }
        let wasActive = snapshot.status.isActive
        snapshot = next
        if next.status.isActive != wasActive {
            onActivityChanged?(next.status.isActive)
        }
    }

    // MARK: - Start

    public func record(title: String? = nil, attendees: [String] = []) {
        pendingTitle = title
        pendingAttendees = attendees
        guard !snapshot.status.isActive else {
            router.isRecorderPresented = true
            return
        }
        guard defaults.bool(forKey: Self.consentKey) else {
            showsConsent = true
            return
        }
        Task { await start() }
    }

    public func acceptConsent() {
        defaults.set(true, forKey: Self.consentKey)
        showsConsent = false
        Task { await start() }
    }

    private func start() async {
        switch permission.access {
        case .granted:
            break
        case .denied:
            showsPermissionDenied = true
            return
        case .undetermined:
            guard await permission.request() else {
                showsPermissionDenied = true
                return
            }
        }
        // Show the screen first, so that the tap gets an instant answer.
        router.isRecorderPresented = true
        let title = pendingTitle
            ?? L10n.Recorder.defaultTitle(Date.now.formatted(date: .abbreviated, time: .shortened))
        do {
            try await coordinator.start(title: title, attendees: pendingAttendees)
            inputs = await coordinator.availableInputs()
        } catch {
            showsStartFailure = true
        }
    }

    // MARK: - Controls

    public func togglePause() {
        Task {
            if case .paused = snapshot.status {
                try? await coordinator.resume()
            } else {
                await coordinator.pause()
            }
        }
    }

    public func stop() {
        Task {
            let saved = try? await coordinator.stop()
            router.isRecorderPresented = false
            levels = []
            if let saved {
                router.push(.recording(saved.id, at: nil))
                onSaved?(saved.id)
            }
        }
    }

    public func flag() {
        Task { try? await coordinator.addMarker(kind: .flag) }
    }

    public func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { try? await coordinator.addMarker(kind: .note, text: trimmed) }
    }

    public func addPhoto(_ data: Data) {
        Task { try? await coordinator.addPhoto(data) }
    }

    public func select(_ input: AudioInput) {
        Task { try? await coordinator.selectInput(input) }
    }

    // MARK: - Recovery

    public func recover() {
        Task {
            let recovered = await (try? coordinator.recoverInterrupted()) ?? []
            recoveredCount = recovered.count
        }
    }

    public func dismissRecoveryNotice() {
        recoveredCount = 0
    }
}
