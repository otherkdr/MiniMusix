import Foundation
import Combine
import SwiftUI
import AppKit
import os
import UniformTypeIdentifiers

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published var currentTrack: NowPlayingTrack?
    @Published var queue: [QueueItem]
    @Published var lyrics: LyricsPayload = .unavailable
    @Published var settings = MiniMusixSettings()
    @Published var isPlaybackAvailable = false

    private let providers: [PlaybackProvider]
    private let mediaRemoteProvider: MediaRemotePlaybackProvider
    private let playbackController: PlaybackController
    private let artworkCache = ArtworkCache()
    let lyricsService: LyricsFetchCoordinator
    private let bluetoothPermissionRequester = BluetoothPermissionRequester()
    private var lastValidTrack: NowPlayingTrack?
    private var lyricsTargetIdentity: TrackIdentity?
    private var lyricsTask: Task<Void, Never>?
    private var lyricsFetchGeneration = 0
    private var playbackTickTask: Task<Void, Never>?
    private var playbackPositionAnchor: PlaybackPositionAnchor?
    private var metadataRefreshAccumulator: TimeInterval = 0

    private struct PlaybackPositionAnchor {
        var elapsed: TimeInterval
        var capturedAt: Date
        var playbackRate: Double
        var isPlaying: Bool
    }

    init(
        providers: [PlaybackProvider]? = nil,
        lyricsService: LyricsFetchCoordinator? = nil
    ) {
        let mediaRemoteProvider = MediaRemotePlaybackProvider()
        self.mediaRemoteProvider = mediaRemoteProvider
        self.playbackController = PlaybackController(mediaRemoteProvider: mediaRemoteProvider)
        self.providers = providers ?? [mediaRemoteProvider]
        self.lyricsService = lyricsService ?? LyricsFetchCoordinator()
        self.currentTrack = nil
        self.queue = []
        self.lastValidTrack = nil
        self.settings = SettingsManager.shared.runtimeSettings(preserving: self.settings)

        mediaRemoteProvider.onTrackChanged = { [weak self] track in
            Task { @MainActor in
                self?.apply(track)
            }
        }
        mediaRemoteProvider.onPermissionChanged = { [weak self] state in
            Task { @MainActor in
                self?.settings.mediaRemotePermission = state
            }
        }
        bluetoothPermissionRequester.onPermissionChanged = { [weak self] state in
            self?.settings.bluetoothPermission = state
        }
        bluetoothPermissionRequester.refreshPermissionState()
        mediaRemoteProvider.startListening()
        startPlaybackTicker()
        updateAutomationPermissionStates()
    }

    deinit {
        lyricsTask?.cancel()
        playbackTickTask?.cancel()
        let mediaRemoteProvider = mediaRemoteProvider
        Task { @MainActor in
            mediaRemoteProvider.stopListening()
        }
    }

    private func startPlaybackTicker() {
        playbackTickTask?.cancel()
        playbackTickTask = Task { [weak self] in
            var lastTickDate = Date()

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { break }

                let now = Date()
                let delta = now.timeIntervalSince(lastTickDate)
                lastTickDate = now

                let shouldRefreshMetadata = await MainActor.run {
                    self?.tick(delta: delta)
                    return self?.shouldRefreshMetadata(delta: delta) ?? false
                }

                if shouldRefreshMetadata {
                    _ = await self?.refreshMetadata()
                }
            }
        }
    }

    @discardableResult
    func refreshMetadata() async -> NowPlayingTrack? {
        if let mediaRemoteProvider = providers.compactMap({ $0 as? MediaRemotePlaybackProvider }).first,
           let live = await mediaRemoteProvider.refreshLiveTrack() {
            guard accepts(live.track) else {
                apply(nil)
                return nil
            }
            apply(live.track, preferLivePosition: live.hasLivePosition)
            return live.track
        }

        for provider in providers {
            guard let track = await provider.currentTrack() else { continue }
            guard accepts(track) else {
                apply(nil)
                return nil
            }
            apply(track, preferLivePosition: true)
            return track
        }

        apply(nil)
        return nil
    }

    private func accepts(_ track: NowPlayingTrack) -> Bool {
        settings.source == .automatic || settings.source == track.source || settings.source == .mediaRemote
    }

    private func clampElapsed(_ value: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return max(0, value) }
        return min(max(0, value), duration)
    }

    private func liveElapsed(from anchor: PlaybackPositionAnchor, duration: TimeInterval) -> TimeInterval {
        guard anchor.isPlaying else {
            return clampElapsed(anchor.elapsed, duration: duration)
        }

        let rate = anchor.playbackRate > 0 ? anchor.playbackRate : 1.0
        let secondsSinceCapture = Date().timeIntervalSince(anchor.capturedAt)
        return clampElapsed(anchor.elapsed + secondsSinceCapture * rate, duration: duration)
    }

    private func updatePositionAnchor(for track: NowPlayingTrack) {
        playbackPositionAnchor = PlaybackPositionAnchor(
            elapsed: track.elapsed,
            capturedAt: Date(),
            playbackRate: track.playbackRate,
            isPlaying: track.playbackState == .playing
        )
    }

    private func apply(_ incomingTrack: NowPlayingTrack?, preferLivePosition: Bool = false) {
        guard var track = incomingTrack else {
            currentTrack = nil
            playbackPositionAnchor = nil
            isPlaybackAvailable = false
            lyrics = .unavailable
            lyricsTargetIdentity = nil
            lyricsTask?.cancel()
            return
        }

        guard accepts(track) else {
            currentTrack = nil
            isPlaybackAvailable = false
            lyrics = .unavailable
            lyricsTargetIdentity = nil
            lyricsTask?.cancel()
            return
        }

        isPlaybackAvailable = true
        if track.artwork == nil {
            if let lastValidTrack, lastValidTrack.identity == track.identity {
                track.artwork = lastValidTrack.artwork
                track.dominantColor = lastValidTrack.dominantColor
                track.secondaryColor = lastValidTrack.secondaryColor
            } else {
                let colors = artworkCache.colors(for: track)
                track.dominantColor = colors.0
                track.secondaryColor = colors.1
            }
        }

        if preferLivePosition {
            track.elapsed = clampElapsed(track.elapsed, duration: track.identity.duration)
        } else if let previousTrack = lastValidTrack,
                  previousTrack.identity == track.identity,
                  track.elapsed < 0.5,
                  previousTrack.elapsed > 0 {
            // Listener update without position — keep last known only as a fallback.
            track.elapsed = clampElapsed(previousTrack.elapsed, duration: track.identity.duration)
        } else {
            track.elapsed = clampElapsed(track.elapsed, duration: track.identity.duration)
        }

        updatePositionAnchor(for: track)

        let previousTrack = lastValidTrack
        currentTrack = track
        lastValidTrack = track

        let shouldLoadLyrics = lyricsTargetIdentity.map { !sameLyricsTarget($0, track.identity) } ?? true
        let lyricsUnresolved = lyrics == .unavailable || lyrics == .loading
        let durationBecameAvailable = previousTrack.map {
            sameLyricsTarget($0.identity, track.identity)
                && $0.identity.duration <= 0
                && track.identity.duration > 0
        } ?? false

        if shouldLoadLyrics || (durationBecameAvailable && lyricsUnresolved) {
            lyricsTargetIdentity = track.identity
            loadLyrics(for: track)
        }

    }

    func togglePlayback() {
        performPlaybackCommand(.playPause)
    }

    func skipForward() {
        performPlaybackCommand(.next)
    }

    func skipBack() {
        performPlaybackCommand(.previous)
    }

    private func performPlaybackCommand(_ command: PlaybackCommand) {
        playbackController.perform(
            command,
            routing: settings.commandRouting,
            currentTrack: currentTrack,
            onImmediateFeedback: { [weak self] command, _ in
                self?.applyOptimisticPlaybackChange(command)
            },
            refreshMetadata: { [weak self] in
                await self?.refreshMetadata()
            }
        )
    }

    private func applyOptimisticPlaybackChange(_ command: PlaybackCommand) {
        guard var track = currentTrack else { return }

        switch command {
        case .playPause:
            track.playbackState = track.playbackState == .playing ? .paused : .playing
        case .next:
            return
        case .previous:
            if track.elapsed > 3 {
                track.elapsed = 0
            }
        }

        currentTrack = track
        updatePositionAnchor(for: track)
    }

    func seek(to seconds: TimeInterval) {
        mediaRemoteProvider.seek(to: seconds)
        if var track = currentTrack {
            track.elapsed = clampElapsed(seconds, duration: track.identity.duration)
            currentTrack = track
            updatePositionAnchor(for: track)
        }
    }

    func playQueueItem(_ item: QueueItem) {
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return }
        let selected = queue.remove(at: index)
        if let currentTrack {
            queue.insert(QueueItem(track: currentTrack), at: min(index, queue.count))
        }
        apply(selected.track)
    }

    func addCurrentTrackToQueue() {
        guard let currentTrack else { return }

        if mediaRemoteProvider.supportsNativeQueueManagement() {
            mediaRemoteProvider.queueCurrentTrack()
        }

        guard !queue.contains(where: { $0.track.identity == currentTrack.identity }) else { return }
        queue.append(QueueItem(track: currentTrack))
    }

    func removeFromQueue(_ item: QueueItem) {
        queue.removeAll { $0.id == item.id }
    }

    func moveQueueItems(from source: IndexSet, to destination: Int) {
        guard settings.dragReordering else { return }
        queue.move(fromOffsets: source, toOffset: destination)
    }

    func tick(delta: TimeInterval = 1) {
        guard var track = currentTrack, let anchor = playbackPositionAnchor else { return }

        if anchor.isPlaying {
            track.elapsed = liveElapsed(from: anchor, duration: track.identity.duration)
            track.playbackState = .playing
        } else {
            track.elapsed = clampElapsed(anchor.elapsed, duration: track.identity.duration)
            track.playbackState = .paused
        }

        currentTrack = track
    }

    private func shouldRefreshMetadata(delta: TimeInterval) -> Bool {
        guard settings.metadataRefreshRate > 0 else { return false }
        metadataRefreshAccumulator += delta
        guard metadataRefreshAccumulator >= settings.metadataRefreshRate else { return false }
        metadataRefreshAccumulator = 0
        return true
    }

    func clearArtworkCache() {
        artworkCache.clear()
    }

    func reloadLyrics() {
        guard let currentTrack else { return }
        lyricsTargetIdentity = currentTrack.identity
        loadLyrics(for: currentTrack)
    }

    func importCustomLRC() {
        guard let currentTrack else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose Lyrics File"
        panel.prompt = "Import"
        panel.message = "Choose a timed lyrics file for the current song."
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        let lines = LyricsFetchCoordinator.parseSyncedLyrics(text)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else {
            settings.lyricsPermission = .unavailable("That file does not include timed lyrics.")
            lyrics = .unavailable
            return
        }

        let payload = LyricsPayload.synced(lines)
        lyricsTask?.cancel()
        lyricsFetchGeneration += 1
        lyricsTargetIdentity = currentTrack.identity
        lyricsService.storeCustomLyrics(payload, for: currentTrack.identity)
        settings.lyricsPermission = .ready
        lyrics = payload
    }

    private func sameLyricsTarget(_ lhs: TrackIdentity, _ rhs: TrackIdentity) -> Bool {
        let titleMatches = normalizedLyricsKey(lhs.title) == normalizedLyricsKey(rhs.title)
        let artistMatches = normalizedLyricsKey(lhs.artist) == normalizedLyricsKey(rhs.artist)
        let durationMatches = lyricDurationsMatch(lhs.duration, rhs.duration)

        return titleMatches && artistMatches && durationMatches
    }

    private func normalizedLyricsKey(_ value: String?) -> String {
        let cleaned = value?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ") ?? ""

        if cleaned == "unknown album" {
            return ""
        }

        return cleaned
            .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+(remaster(?:ed)?|radio edit|single version|explicit|clean)\b.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lyricDurationsMatch(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool {
        guard lhs.isFinite, rhs.isFinite, lhs > 0, rhs > 0 else {
            return true
        }

        return abs(lhs - rhs) <= 3
    }

    func requestAutomationPermission() {
        mediaRemoteProvider.requestAutomationPermission()
        updateAutomationPermissionStates()
    }

    /// Prompts for Music first, then Spotify — used when entering onboarding permissions.
    func requestOnboardingPlaybackPermissions() {
        Task { @MainActor in
            _ = AppleScriptAutomation.requestAccess(for: .music)
            try? await Task.sleep(for: .milliseconds(450))
            _ = AppleScriptAutomation.requestAccess(for: .spotify)
            updateAutomationPermissionStates()
        }
    }

    func requestBluetoothPermission() {
        bluetoothPermissionRequester.requestPermission()
    }

    func refreshPermissions() {
        requestAutomationPermission()
        updateAutomationPermissionStates()
        bluetoothPermissionRequester.refreshPermissionState()

        if currentTrack != nil {
            settings.mediaRemotePermission = .ready
        }

        if settings.enableLRCLIB {
            settings.lyricsPermission = .ready
        }
    }

    func updateAutomationPermissionStates() {
        let states = mediaRemoteProvider.automationPermissionStates()
        settings.musicAutomationPermission = states.music
        settings.spotifyAutomationPermission = states.spotify
    }

    func openAutomationPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadLyrics(for track: NowPlayingTrack) {
        lyricsTask?.cancel()
        lyricsFetchGeneration += 1
        let generation = lyricsFetchGeneration
        let identity = track.identity

        guard settings.enableLRCLIB else {
            lyrics = .unavailable
            return
        }

        lyrics = .loading

        lyricsTask = Task { [lyricsService] in
            let currentSettings = await MainActor.run { self.settings }
            let payload = await lyricsService.lyrics(for: track, settings: currentSettings)

            await MainActor.run {
                guard self.lyricsFetchGeneration == generation else { return }
                guard self.currentTrack.map({ self.sameLyricsTarget($0.identity, identity) }) == true else { return }
                self.settings.lyricsPermission = payload == .unavailable
                    ? .unavailable("No lyrics were found for this song.")
                    : .ready
                self.lyrics = payload
            }
        }
    }
}
