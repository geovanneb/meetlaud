import Domain
import Foundation
import Localization

extension Int64 {
    var fileSize: String {
        formatted(.byteCount(style: .file))
    }
}

extension ModelRole {
    var title: String {
        switch self {
        case .transcription: L10n.Models.roleTranscription
        case .speakerSeparation: L10n.Models.roleSpeakers
        case .voicePrint: L10n.Models.roleVoicePrint
        case .chat: L10n.Models.roleChat
        case .search: L10n.Models.roleSearch
        }
    }

    var purpose: String {
        switch self {
        case .transcription: L10n.Models.purposeTranscription
        case .speakerSeparation: L10n.Models.purposeSpeakers
        case .voicePrint: L10n.Models.purposeVoicePrint
        case .chat: L10n.Models.purposeChat
        case .search: L10n.Models.purposeSearch
        }
    }
}

extension FitLabel {
    var title: String {
        switch self {
        case .best: L10n.Models.fitBest
        case .good: L10n.Models.fitGood
        case .maySlow: L10n.Models.fitSlow
        case .notRecommended: L10n.Models.fitNotRecommended
        case .unsupported: L10n.Models.fitUnsupported
        }
    }
}

extension FitReason {
    var title: String {
        switch self {
        case .bestForDevice: L10n.Models.reasonBest
        case .worksWell: L10n.Models.reasonWorks
        case .belowTargetSpeed: L10n.Models.reasonSlow
        case .notEnoughMemory: L10n.Models.reasonMemory
        case .unstableHere: L10n.Models.reasonUnstable
        case let .languageNotCovered(code): L10n.Models.reasonLanguage(languageName(code))
        }
    }
}

func languageName(_ code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code) ?? code
}

extension SpeedEvidence {
    /// Plain words: nobody thinks in multiples of real time.
    var title: String {
        switch self {
        case let .measured(speed):
            L10n.Models.speedMeasured(Self.minutes(for: speed))
        case let .estimated(low, high):
            L10n.Models.speedEstimated(Self.minutes(for: high), Self.minutes(for: low))
        case .unknown:
            L10n.Models.speedUnknown
        }
    }

    private static func minutes(for speed: Double) -> Int {
        guard speed > 0 else { return 0 }
        return max(1, Int((60 / speed).rounded()))
    }
}

extension AdvisorSuggestion {
    func title(in snapshot: ModelsSnapshot) -> String {
        func name(_ id: String) -> String {
            snapshot.fits.values.joined().first { $0.model.id == id }?.model.displayName ?? id
        }
        switch self {
        case let .betterFit(_, id): return L10n.Models.suggestBetter(name(id))
        case let .languageNotCovered(code, _): return L10n.Models.suggestLanguage(languageName(code))
        case let .unstable(id, _): return L10n.Models.suggestUnstable(name(id))
        case let .tooSlow(id): return L10n.Models.suggestSlow(name(id))
        case let .unusedModel(id, bytes): return L10n.Models.suggestUnused(name(id), bytes.fileSize)
        }
    }
}

extension Priority {
    var title: String {
        switch self {
        case .speed: L10n.Models.prioritySpeed
        case .balanced: L10n.Models.priorityBalanced
        case .quality: L10n.Models.priorityQuality
        }
    }
}
