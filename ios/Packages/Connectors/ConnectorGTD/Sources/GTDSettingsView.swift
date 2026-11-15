import DesignSystem
import SwiftUI
import VisionKit

/// Strings of this connector. It carries them in its own catalog, in the four app languages.
enum GTDText {
    private static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    static var summary: String { text("gtd.summary") }
    static var title: String { text("gtd.title") }
    static var notConnected: String { text("gtd.not_connected") }
    static var scanHint: String { text("gtd.scan_hint") }
    static var scan: String { text("gtd.scan") }
    static var sharing: String { text("gtd.sharing") }
    static var audio: String { text("gtd.audio") }
    static var transcripts: String { text("gtd.transcripts") }
    static var photos: String { text("gtd.photos") }
    static var sharingNote: String { text("gtd.sharing_note") }
    static var disconnect: String { text("gtd.disconnect") }
    static var connectedNote: String { text("gtd.connected_note") }
    static var done: String { text("gtd.done") }
    static var tryAgain: String { text("gtd.try_again") }
    static var notACodeTitle: String { text("gtd.not_a_code_title") }
    static var notACodeMessage: String { text("gtd.not_a_code_message") }
    static var expiredTitle: String { text("gtd.expired_title") }
    static var expiredMessage: String { text("gtd.expired_message") }
    static var unreachableTitle: String { text("gtd.unreachable_title") }
    static var unreachableMessage: String { text("gtd.unreachable_message") }
    static var cameraUnavailable: String { text("gtd.camera_unavailable") }
    static var cancel: String { text("gtd.cancel") }

    static func connected(_ name: String) -> String {
        String(format: text("gtd.connected"), name)
    }

    static func connecting(_ name: String) -> String {
        String(format: text("gtd.connecting"), name)
    }
}

/// Where a pairing stands. The sheet stays open through all of it, so that a person always sees what is happening
/// and how it ended.
enum GTDPairing: Equatable {
    case scanning
    case connecting(String)
    case connected(String)
    case failed(GTDPairingFailure)
}

enum GTDPairingFailure: Equatable {
    /// A QR code from anything else.
    case notACode
    /// The code expired, was already used, or was mistyped by a stranger's attempt.
    case expired
    /// The computer did not answer at any address.
    case unreachable

    init(_ error: any Error) {
        switch error {
        case GTDError.wrongCode, GTDError.wrongComputer: self = .expired
        case is DecodingError: self = .notACode
        default: self = .unreachable
        }
    }

    var title: String {
        switch self {
        case .notACode: GTDText.notACodeTitle
        case .expired: GTDText.expiredTitle
        case .unreachable: GTDText.unreachableTitle
        }
    }

    var message: String {
        switch self {
        case .notACode: GTDText.notACodeMessage
        case .expired: GTDText.expiredMessage
        case .unreachable: GTDText.unreachableMessage
        }
    }
}

/// Everything about this one connection: whether it is linked, and what it may receive.
struct GTDSettingsView: View {
    let store: GTDStore
    @State private var link: GTDLink?
    @State private var isPairing = false
    @AppStorage(GTDStore.transcriptsKey) private var sendsTranscripts = false
    @AppStorage(GTDStore.photosKey) private var sendsPhotos = false

    var body: some View {
        List {
            Section {
                if let link {
                    Label {
                        RowLabel(GTDText.connected(link.computerName), detail: GTDText.connectedNote)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.dsAction)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("gtd.status")
                } else {
                    RowLabel(GTDText.notConnected, detail: GTDText.scanHint)
                    Button(GTDText.scan) { isPairing = true }
                        .primaryAction()
                        .accessibilityIdentifier("gtd.scan")
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section(title: GTDText.sharing) {
                Label(GTDText.audio, systemImage: "waveform")
                Toggle(GTDText.transcripts, isOn: $sendsTranscripts)
                    .accessibilityIdentifier("gtd.transcripts")
                Toggle(GTDText.photos, isOn: $sendsPhotos)
                    .accessibilityIdentifier("gtd.photos")
                Text(GTDText.sharingNote)
                    .font(.dsNote)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            if link != nil {
                Section {
                    Button(GTDText.disconnect, role: .destructive) {
                        store.forget()
                        link = nil
                    }
                    .accessibilityIdentifier("gtd.disconnect")
                }
                .listRowBackground(Color.clear)
            }
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(GTDText.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { link = store.link }
        .fullScreenCover(isPresented: $isPairing, onDismiss: { link = store.link }) {
            GTDPairingScreen(store: store)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.gtd")
    }
}

/// From the camera to a clear ending. It closes only when the person closes it.
private struct GTDPairingScreen: View {
    let store: GTDStore
    @State private var pairing = GTDPairing.scanning
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.dsBackground.ignoresSafeArea()
            if pairing == .scanning {
                GTDScanner(onCode: pair)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else {
                result
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if case .connected = pairing {} else {
                Button(GTDText.cancel) { dismiss() }
                    .secondaryAction(.regular)
                    .padding(Spacing.medium)
                    .accessibilityIdentifier("gtd.cancel")
            }
        }
        .motion(Motion.standard, value: pairing)
        .sensoryFeedback(trigger: pairing) { _, new in
            switch new {
            case .scanning: nil
            case .connecting: .impact(weight: .light)
            case .connected: .success
            case .failed: .error
            }
        }
        .onChange(of: pairing) { _, new in announce(new) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.gtdPairing")
    }

    private var result: some View {
        VStack(spacing: Spacing.medium) {
            switch pairing {
            case .scanning:
                EmptyView()
            case let .connecting(name):
                ProgressView()
                    .controlSize(.large)
                    .padding(.bottom, Spacing.small)
                Text(GTDText.connecting(name))
                    .font(.dsSectionTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("gtd.connecting")
            case let .connected(name):
                symbol("checkmark.circle.fill", color: .dsAction)
                Text(GTDText.connected(name))
                    .font(.dsSectionTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("gtd.connected")
                Text(GTDText.connectedNote)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    dismiss()
                } label: {
                    Text(GTDText.done)
                        .frame(maxWidth: .infinity)
                }
                .primaryAction()
                .padding(.top, Spacing.small)
                .accessibilityIdentifier("gtd.done")
            case let .failed(failure):
                symbol("exclamationmark.triangle.fill", color: .dsSecondaryText)
                Text(failure.title)
                    .font(.dsSectionTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("gtd.failed")
                Text(failure.message)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    pairing = .scanning
                } label: {
                    Text(GTDText.tryAgain)
                        .frame(maxWidth: .infinity)
                }
                .primaryAction()
                .padding(.top, Spacing.small)
                .accessibilityIdentifier("gtd.tryAgain")
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: 420)
    }

    private func symbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.dsHero)
            .imageScale(.large)
            .foregroundStyle(color)
            .symbolEffect(.bounce, options: .nonRepeating, isActive: !reduceMotion)
            .accessibilityHidden(true)
    }

    private func pair(with text: String) {
        do {
            let code = try GTDPairingCode(scanned: text)
            pairing = .connecting(code.name)
            Task {
                do {
                    try await GetThingsDoneConnector.link(code: code, store: store, name: UIDevice.current.name)
                    pairing = .connected(code.name)
                } catch {
                    pairing = .failed(GTDPairingFailure(error))
                }
            }
        } catch {
            pairing = .failed(.notACode)
        }
    }

    private func announce(_ state: GTDPairing) {
        let text: String? = switch state {
        case .scanning: nil
        case let .connecting(name): GTDText.connecting(name)
        case let .connected(name): GTDText.connected(name)
        case let .failed(failure): failure.title
        }
        if let text {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

/// The system's scanner, set to QR codes. On a device with no camera it says so.
private struct GTDScanner: View {
    let onCode: (String) -> Void

    /// Lets the simulator, which has no camera, run the whole flow with a code from a test.
    private var testCode: String? {
        #if DEBUG
            ProcessInfo.processInfo.environment["GTD_TEST_CODE"]
        #else
            nil
        #endif
    }

    var body: some View {
        if let testCode {
            Color.clear.onAppear { onCode(testCode) }
        } else if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            Scanner(onCode: onCode)
        } else {
            Text(GTDText.cameraUnavailable)
                .font(.dsRowTitle)
                .multilineTextAlignment(.center)
                .padding(Spacing.large)
        }
    }

    private struct Scanner: UIViewControllerRepresentable {
        let onCode: (String) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onCode: onCode)
        }

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true,
            )
            scanner.delegate = context.coordinator
            try? scanner.startScanning()
            return scanner
        }

        func updateUIViewController(_: DataScannerViewController, context _: Context) {}
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var isDone = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _: DataScannerViewController,
            didAdd items: [RecognizedItem],
            allItems _: [RecognizedItem],
        ) {
            for case let .barcode(code) in items {
                if let text = code.payloadStringValue, !isDone {
                    isDone = true
                    onCode(text)
                }
            }
        }
    }
}
