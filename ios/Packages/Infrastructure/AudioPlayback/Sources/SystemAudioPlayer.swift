@preconcurrency import AVFAudio
import Domain
import Foundation
import MediaPlayer

/// Plays a recording, keeps playing in the background, and answers Lock Screen controls.
@MainActor
public final class SystemAudioPlayer: AudioPlaying {
    private var player: AVAudioPlayer?
    private var title = ""
    private var commandTargets: [Any] = []

    public var rate: Float = 1 {
        didSet {
            player?.rate = rate
            updateNowPlaying()
        }
    }

    public init() {}

    public var duration: TimeInterval {
        player?.duration ?? 0
    }

    public var currentTime: TimeInterval {
        player?.currentTime ?? 0
    }

    public var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    public func load(_ file: URL, title: String) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: file)
        player.enableRate = true
        player.rate = rate
        player.prepareToPlay()
        self.player = player
        self.title = title
        registerCommands()
    }

    public func play() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        updateNowPlaying()
    }

    public func pause() {
        player?.pause()
        updateNowPlaying()
    }

    public func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(time, 0), player.duration)
        updateNowPlaying()
    }

    public func stop() {
        player?.stop()
        player = nil
        removeCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateNowPlaying() {
        guard let player else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? Double(rate) : 0,
        ]
    }

    private func registerCommands() {
        removeCommands()
        let center = MPRemoteCommandCenter.shared()
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.preferredIntervals = [30]
        commandTargets = [
            center.playCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.play() }
                return .success
            },
            center.pauseCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
                return .success
            },
            center.skipBackwardCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self.map { $0.seek(to: $0.currentTime - 15) } }
                return .success
            },
            center.skipForwardCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self.map { $0.seek(to: $0.currentTime + 30) } }
                return .success
            },
        ]
    }

    private func removeCommands() {
        let center = MPRemoteCommandCenter.shared()
        for command in [
            center.playCommand, center.pauseCommand, center.skipBackwardCommand, center.skipForwardCommand,
        ] {
            command.removeTarget(nil)
        }
        commandTargets = []
    }
}
