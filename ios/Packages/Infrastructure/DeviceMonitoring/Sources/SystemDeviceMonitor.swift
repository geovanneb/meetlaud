import Domain
import Foundation
import os
import UIKit

/// Watches the device through system notifications. There is no timer here, so that it costs nothing when idle.
public final class SystemDeviceMonitor: DeviceMonitor, @unchecked Sendable {
    public let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let storage: URL
    private var observers: [any NSObjectProtocol] = []

    public init(storage: URL) {
        self.storage = storage
        (changes, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        let center = NotificationCenter.default
        let notify: @Sendable (Notification) -> Void = { [continuation] _ in continuation.yield() }
        for name in [
            ProcessInfo.thermalStateDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
            UIDevice.batteryStateDidChangeNotification,
            UIDevice.batteryLevelDidChangeNotification,
            UIApplication.didBecomeActiveNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil, using: notify))
        }
        Task { @MainActor in UIDevice.current.isBatteryMonitoringEnabled = true }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    @MainActor
    private static var currentName: String {
        UIDevice.current.localizedModel
    }

    public func profile() async -> DeviceProfile {
        await DeviceProfile(
            name: Self.currentName,
            identifier: Self.hardwareIdentifier,
            physicalMemoryMB: Int(ProcessInfo.processInfo.physicalMemory / 1_000_000),
        )
    }

    public func condition() async -> DeviceCondition {
        let (level, state) = await MainActor.run {
            (UIDevice.current.batteryLevel, UIDevice.current.batteryState)
        }
        let values = try? storage.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return DeviceCondition(
            thermal: Self.thermal(ProcessInfo.processInfo.thermalState),
            isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isCharging: state == .charging || state == .full,
            batteryLevel: level < 0 ? 1 : Double(level),
            availableMemoryMB: os_proc_available_memory() / 1_000_000,
            freeBytes: values?.volumeAvailableCapacityForImportantUsage ?? 0,
        )
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }

    private static var hardwareIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
    }
}
