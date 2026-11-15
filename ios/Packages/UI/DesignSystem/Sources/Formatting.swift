import Foundation

public extension TimeInterval {
    /// `12:04`, or `1:12:04` past an hour. Used wherever a time position appears.
    var clock: String {
        let duration = Duration.seconds(max(self, 0).rounded(.down))
        let pattern: Duration.TimeFormatStyle.Pattern = self >= 3600 ? .hourMinuteSecond : .minuteSecond
        return duration.formatted(.time(pattern: pattern))
    }
}

public extension Int64 {
    /// `1.2 GB`. Used wherever a size on disk appears, so every screen counts bytes the same way.
    var fileSize: String {
        formatted(.byteCount(style: .file))
    }
}
