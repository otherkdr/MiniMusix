import Foundation
import SwiftUI
import AppKit
import MediaRemoteAdapter
import os

private final class OneShotContinuationGate {
    private let lock = NSLock()
    private var didResume = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else {
            return false
        }

        didResume = true
        return true
    }
}

final class MediaRemotePlaybackProvider: PlaybackProvider {
    let source: PlaybackSource = .mediaRemote

    private let logger = Logger(subsystem: "MiniMusix", category: "PlaybackControls")
    private let controller = MediaController()
    private let artworkAnalyzer = ArtworkAnalyzer()
    private var latestTrack: NowPlayingTrack?

    var onTrackChanged: ((NowPlayingTrack?) -> Void)?
    var onPermissionChanged: ((BackendPermissionState) -> Void)?

    init() {
        controller.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self else { return }
            let track = trackInfo.flatMap(self.makeTrack(from:))
            self.latestTrack = track
            self.onPermissionChanged?(.ready)
            self.onTrackChanged?(track)
        }
        controller.onListenerTerminated = { [weak self] in
            self?.onPermissionChanged?(.unavailable("MiniMusix stopped receiving Now Playing updates. Refresh playback to reconnect."))
        }
        controller.onDecodingError = { [weak self] error, _ in
            self?.onPermissionChanged?(.unavailable("MiniMusix could not read the current song: \(error.localizedDescription)"))
        }
    }

    func startListening() {
        controller.startListening()
        controller.getTrackInfo { [weak self] trackInfo in
            guard let self else { return }
            let track = trackInfo.flatMap(self.makeTrack(from:))
            self.latestTrack = track
            self.onPermissionChanged?(.ready)
            self.onTrackChanged?(track)
        }
    }

    func stopListening() {
        controller.stopListening()
    }

    func currentTrack() async -> NowPlayingTrack? {
        if let latestTrack {
            return latestTrack
        }

        return await fetchCurrentTrack()
    }

    func refreshCurrentTrack() async -> NowPlayingTrack? {
        await fetchCurrentTrack()
    }

    func refreshLiveTrack() async -> (track: NowPlayingTrack, hasLivePosition: Bool)? {
        guard let trackInfo = await fetchTrackInfo() else { return nil }
        guard let track = makeTrack(from: trackInfo) else { return nil }
        latestTrack = track
        return (track, hasLivePositionData(in: trackInfo.payload))
    }

    private func fetchTrackInfo() async -> TrackInfo? {
        await getTrackInfoOnce()
    }

    private func fetchCurrentTrack() async -> NowPlayingTrack? {
        let trackInfo = await getTrackInfoOnce()
        let track = trackInfo.flatMap { makeTrack(from: $0) }
        latestTrack = track
        return track
    }

    private func getTrackInfoOnce() async -> TrackInfo? {
        await withCheckedContinuation { continuation in
            let gate = OneShotContinuationGate()

            controller.getTrackInfo { trackInfo in
                guard gate.tryResume() else {
                    return
                }
                continuation.resume(returning: trackInfo)
            }
        }
    }

    func play() {
        logger.debug("MEDIA_REMOTE_COMMAND_SENT play target=\(self.latestTrack?.bundleIdentifier ?? "unknown", privacy: .public)")
        controller.play()
    }

    func pause() {
        logger.debug("MEDIA_REMOTE_COMMAND_SENT pause target=\(self.latestTrack?.bundleIdentifier ?? "unknown", privacy: .public)")
        controller.pause()
    }

    func togglePlayPause() {
        sendMediaRemote(.playPause)
    }

    func nextTrack() {
        sendMediaRemote(.next)
    }

    func previousTrack() {
        sendMediaRemote(.previous)
    }

    func sendMediaRemote(_ command: PlaybackCommand) {
        logger.debug("MEDIA_REMOTE_COMMAND_SENT command=\(self.logName(for: command), privacy: .public) target=\(self.latestTrack?.bundleIdentifier ?? "unknown", privacy: .public)")
        switch command {
        case .playPause:
            controller.togglePlayPause()
        case .next:
            controller.nextTrack()
        case .previous:
            controller.previousTrack()
        }
    }

    func canUseAppleScriptFallback(for track: NowPlayingTrack?) -> Bool {
        let bundleIdentifier = track?.bundleIdentifier ?? latestTrack?.bundleIdentifier
        return isMusic(bundleIdentifier: bundleIdentifier) || isSpotify(bundleIdentifier: bundleIdentifier)
    }

    @discardableResult
    func sendAppleScriptFallback(_ command: PlaybackCommand, for track: NowPlayingTrack?) -> Bool {
        guard let target = automationTarget(for: track) else { return false }

        logger.debug("APPLE_SCRIPT_FALLBACK_USED command=\(self.logName(for: command), privacy: .public) target=\(target.rawValue, privacy: .public)")

        let outcome: AppleScriptRunOutcome
        switch command {
        case .playPause:
            outcome = AppleScriptAutomation.playPause(target: target)
        case .next:
            outcome = AppleScriptAutomation.nextTrack(target: target)
        case .previous:
            outcome = AppleScriptAutomation.previousTrack(target: target)
        }

        switch outcome {
        case .success:
            return true
        case .needsPermission:
            onPermissionChanged?(.unavailable("Allow MiniMusix to control \(target.applicationName) when macOS asks, or enable it in System Settings."))
            return false
        case .denied(let message):
            onPermissionChanged?(.unavailable(message))
            return false
        }
    }

    func snapshotTrack() -> NowPlayingTrack? {
        latestTrack
    }

    func seek(to seconds: TimeInterval) {
        controller.setTime(seconds: seconds)
    }

    private func logName(for command: PlaybackCommand) -> String {
        switch command {
        case .playPause:
            return "playPause"
        case .next:
            return "next"
        case .previous:
            return "previous"
        }
    }

    func requestAutomationPermission() {
        controller.getTrackInfo { _ in }
        AppleScriptAutomation.requestAccessForPlaybackTargets()
    }

    func automationPermissionStates() -> (music: BackendPermissionState, spotify: BackendPermissionState) {
        AppleScriptAutomation.refreshPermissionStates()
    }

    private func automationTarget(for track: NowPlayingTrack?) -> MusicAutomationTarget? {
        let bundleIdentifier = track?.bundleIdentifier ?? latestTrack?.bundleIdentifier
        if isMusic(bundleIdentifier: bundleIdentifier) {
            return .music
        }
        if isSpotify(bundleIdentifier: bundleIdentifier) {
            return .spotify
        }
        return nil
    }

    @discardableResult
    private func runAppleScript(_ source: String, target: MusicAutomationTarget) -> Bool {
        switch AppleScriptAutomation.run(source) {
        case .success:
            return true
        case .needsPermission, .denied:
            return false
        }
    }

    private func isMusic(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.apple.Music"
    }

    private func isSpotify(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.spotify.client"
    }

    func addToQueueMusic(urlString: String) {
        let escaped = urlString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Music\" to try\nadd POSIX file \"\(escaped)\"\nend try"
        runAppleScript(script, target: .music)
    }

    func addToQueueSpotify(uri: String) {
        let escaped = uri.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let queueScript = "tell application \"Spotify\" to add track \"\(escaped)\" to queue"
        runAppleScript(queueScript, target: .spotify)
    }

    func supportsNativeQueueManagement() -> Bool {
        guard let bundleIdentifier = latestTrack?.bundleIdentifier else { return false }
        return bundleIdentifier == "com.apple.Music" || bundleIdentifier == "com.spotify.client"
    }

    func queueCurrentTrack() {
        guard let track = latestTrack else { return }

        if track.bundleIdentifier == "com.spotify.client" {
            let title = track.identity.title.replacingOccurrences(of: "\"", with: "")
            let artist = track.identity.artist.replacingOccurrences(of: "\"", with: "")
            let script = "tell application \"Spotify\" to search \"\(title) \(artist)\""
            runAppleScript(script, target: .spotify)
            return
        }

        if track.bundleIdentifier == "com.apple.Music" {
            let title = track.identity.title.replacingOccurrences(of: "\"", with: "")
            let script = "tell application \"Music\" to search library playlist 1 for \"\(title)\""
            runAppleScript(script, target: .music)
        }
    }

    private func makeTrack(from info: TrackInfo) -> NowPlayingTrack? {
        let payload = info.payload
        let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let title, !title.isEmpty,
              let artist, !artist.isEmpty else {
            return nil
        }

        let album = payload.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = max((payload.durationMicros ?? 0) / 1_000_000, 0)
        let elapsed = resolvePlaybackPosition(from: payload)
        let playbackRate = resolvedPlaybackRate(from: payload)
        let artwork = payload.artwork
        let colors = artworkAnalyzer.colors(from: artwork)

        return NowPlayingTrack(
            identity: TrackIdentity(
                title: title,
                artist: artist,
                album: album?.isEmpty == false ? album! : "Unknown Album",
                duration: duration
            ),
            artworkSystemName: "music.note",
            artwork: artwork,
            dominantColor: colors.0,
            secondaryColor: colors.1,
            elapsed: duration > 0 ? min(elapsed, duration) : elapsed,
            playbackRate: playbackRate,
            playbackState: payload.isPlaying == true ? .playing : .paused,
            source: source(for: payload.bundleIdentifier),
            applicationName: payload.applicationName,
            bundleIdentifier: payload.bundleIdentifier
        )
    }

    /// Resolves live playback position at this instant using MediaRemote's elapsed snapshot + timestamp.
    private func resolvePlaybackPosition(from payload: TrackInfo.Payload) -> TimeInterval {
        if let live = interpolatedPlaybackPosition(from: payload) {
            return max(0, live)
        }

        if let snapshot = payload.currentElapsedTime, snapshot.isFinite, snapshot >= 0 {
            return max(0, snapshot)
        }

        return max((payload.elapsedTimeMicros ?? 0) / 1_000_000, 0)
    }

    func hasLivePositionData(in payload: TrackInfo.Payload) -> Bool {
        payload.elapsedTimeMicros != nil
            && (payload.isPlaying != true || payload.timestampEpochMicros != nil)
    }

    private func resolvedPlaybackRate(from payload: TrackInfo.Payload) -> Double {
        let rate = payload.playbackRate ?? 0
        if payload.isPlaying == true {
            return rate > 0 ? rate : 1.0
        }
        return rate > 0 ? rate : 0
    }

    private func interpolatedPlaybackPosition(from payload: TrackInfo.Payload) -> TimeInterval? {
        guard let elapsedMicros = payload.elapsedTimeMicros else { return nil }

        let elapsedSeconds = elapsedMicros / 1_000_000

        guard payload.isPlaying == true else {
            return elapsedSeconds
        }

        guard let timestampMicros = payload.timestampEpochMicros else {
            return elapsedSeconds > 0 ? elapsedSeconds : nil
        }

        let timestampSeconds = timestampMicros / 1_000_000
        let effectiveRate = resolvedPlaybackRate(from: payload)
        let now = Date().timeIntervalSince1970

        return elapsedSeconds + max(0, now - timestampSeconds) * effectiveRate
    }

    private func source(for bundleIdentifier: String?) -> PlaybackSource {
        switch bundleIdentifier {
        case "com.apple.Music":
            return .appleMusic
        case "com.spotify.client":
            return .spotify
        default:
            return .mediaRemote
        }
    }
}
