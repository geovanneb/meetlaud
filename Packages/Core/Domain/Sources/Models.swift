import Foundation

public enum ModelRole: String, CaseIterable, Codable, Sendable {
    case transcription, speakerSeparation, voicePrint, chat, search
}

public enum ModelRuntime: String, Codable, Sendable {
    case appleSpeech, appleLanguage, whisperKit, fluidAudio, mlx
}

public struct ModelFile: Hashable, Codable, Sendable {
    /// Where the file goes inside the model's folder.
    public let path: String
    public let url: URL
    public let size: Int64
    public let sha256: String

    public init(path: String, url: URL, size: Int64, sha256: String) {
        self.path = path
        self.url = url
        self.size = size
        self.sha256 = sha256
    }
}

/// Speed measured by maintainers on a known device. Ships in the catalog.
public struct ReferenceSpeed: Hashable, Codable, Sendable {
    public let device: String
    /// Multiples of real time: 10 means an hour of audio takes 6 minutes.
    public let speedX: Double
    public let peakMemoryMB: Int
    public let probeScore: Double

    public init(device: String, speedX: Double, peakMemoryMB: Int, probeScore: Double) {
        self.device = device
        self.speedX = speedX
        self.peakMemoryMB = peakMemoryMB
        self.probeScore = probeScore
    }
}

public struct ModelDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let version: String
    public let displayName: String
    public let roles: [ModelRole]
    public let runtime: ModelRuntime
    public let license: String
    public let sourceHost: String
    public let repo: String
    public let files: [ModelFile]
    /// Language codes, such as "ja".
    public let languages: [String]
    public let minMemoryMB: Int
    public let backgroundCapable: Bool
    /// 1 to 5 per language, from our evaluation. Speed is measured on the device, quality is not.
    public let quality: [String: Int]
    public let qualityIsProvisional: Bool
    public let reference: [ReferenceSpeed]

    public init(
        id: String,
        version: String = "1",
        displayName: String,
        roles: [ModelRole],
        runtime: ModelRuntime,
        license: String = "MIT",
        sourceHost: String = "huggingface.co",
        repo: String = "",
        files: [ModelFile] = [],
        languages: [String],
        minMemoryMB: Int = 0,
        backgroundCapable: Bool = true,
        quality: [String: Int] = [:],
        qualityIsProvisional: Bool = false,
        reference: [ReferenceSpeed] = [],
    ) {
        self.id = id
        self.version = version
        self.displayName = displayName
        self.roles = roles
        self.runtime = runtime
        self.license = license
        self.sourceHost = sourceHost
        self.repo = repo
        self.files = files
        self.languages = languages
        self.minMemoryMB = minMemoryMB
        self.backgroundCapable = backgroundCapable
        self.quality = quality
        self.qualityIsProvisional = qualityIsProvisional
        self.reference = reference
    }

    public var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    /// Models with no language list work on any voice.
    public func supports(language: String) -> Bool {
        languages.isEmpty || languages.contains(language)
    }

    /// Apple's models are installed and removed by iOS.
    public var isSystemManaged: Bool {
        runtime == .appleSpeech || runtime == .appleLanguage
    }
}

public enum Priority: String, CaseIterable, Codable, Sendable {
    case speed, balanced, quality
}

public enum SelectionMode: Hashable, Codable, Sendable {
    case automatic
    case pinned(String)
}

public enum InstallState: Hashable, Sendable {
    case notInstalled
    case queued
    case downloading(received: Int64, total: Int64)
    case paused(received: Int64, total: Int64)
    case waitingForWiFi
    case verifying
    case preparing
    case selfTest
    case ready
    case failed(InstallFailure)
}

public enum InstallFailure: String, Hashable, Sendable {
    case noSpace, damaged, unavailable, prepareFailed
}

public enum ThermalLevel: Int, Comparable, Sendable {
    case nominal, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the device is, which rarely changes.
public struct DeviceProfile: Hashable, Sendable {
    public var name: String
    public var identifier: String
    public var physicalMemoryMB: Int
    public var hasAppleIntelligence: Bool
    /// Result of the quick device probe. Zero until it has run.
    public var probeScore: Double

    public init(
        name: String,
        identifier: String,
        physicalMemoryMB: Int,
        hasAppleIntelligence: Bool = false,
        probeScore: Double = 0,
    ) {
        self.name = name
        self.identifier = identifier
        self.physicalMemoryMB = physicalMemoryMB
        self.hasAppleIntelligence = hasAppleIntelligence
        self.probeScore = probeScore
    }
}

/// How the device is doing now, which changes minute by minute.
public struct DeviceCondition: Hashable, Sendable {
    public var thermal: ThermalLevel
    public var isLowPower: Bool
    public var isCharging: Bool
    /// From 0 to 1.
    public var batteryLevel: Double
    public var availableMemoryMB: Int
    public var freeBytes: Int64

    public init(
        thermal: ThermalLevel = .nominal,
        isLowPower: Bool = false,
        isCharging: Bool = true,
        batteryLevel: Double = 1,
        availableMemoryMB: Int = 4000,
        freeBytes: Int64 = 50_000_000_000,
    ) {
        self.thermal = thermal
        self.isLowPower = isLowPower
        self.isCharging = isCharging
        self.batteryLevel = batteryLevel
        self.availableMemoryMB = availableMemoryMB
        self.freeBytes = freeBytes
    }
}

/// A speed test or a real job, on this device.
public struct ModelRunStat: Hashable, Sendable {
    public enum Outcome: String, Sendable {
        case completed, killed
    }

    public let modelID: String
    public let audioDuration: TimeInterval
    public let wallTime: TimeInterval
    public let outcome: Outcome
    public let date: Date

    public init(
        modelID: String,
        audioDuration: TimeInterval,
        wallTime: TimeInterval,
        outcome: Outcome,
        date: Date,
    ) {
        self.modelID = modelID
        self.audioDuration = audioDuration
        self.wallTime = wallTime
        self.outcome = outcome
        self.date = date
    }

    public var speedX: Double {
        wallTime > 0 ? audioDuration / wallTime : 0
    }
}
