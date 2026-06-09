import Foundation
import os

@MainActor
final class PlaybackController {
    private let mediaRemoteProvider: MediaRemotePlaybackProvider
    private let logger = Logger(subsystem: "MiniMusix", category: "PlaybackControls")

    private static let firstValidationDelay: Duration = .milliseconds(45)
    private static let fallbackValidationDelay: Duration = .milliseconds(90)

    init(mediaRemoteProvider: MediaRemotePlaybackProvider) {
        self.mediaRemoteProvider = mediaRemoteProvider
    }

    func perform(
        _ command: PlaybackCommand,
        routing: String,
        currentTrack: NowPlayingTrack?,
        onImmediateFeedback: ((PlaybackCommand, NowPlayingTrack?) -> Void)? = nil,
        refreshMetadata: @escaping () async -> NowPlayingTrack?
    ) {
        logPress(command)
        let before = currentTrack

        onImmediateFeedback?(command, before)

        if routing == "Apple Events Only" {
            _ = mediaRemoteProvider.sendAppleScriptFallback(command, for: before)
            Task {
                _ = await waitForCommandEffect(
                    command,
                    before: before,
                    delay: Self.fallbackValidationDelay,
                    refreshMetadata: refreshMetadata
                )
            }
            return
        }

        mediaRemoteProvider.sendMediaRemote(command)

        Task { [weak self] in
            guard let self else { return }

            if await self.waitForCommandEffect(
                command,
                before: before,
                delay: Self.firstValidationDelay,
                refreshMetadata: refreshMetadata
            ) {
                self.logger.debug("MEDIA_REMOTE_COMMAND_SUCCESS command=\(self.logName(for: command), privacy: .public)")
                return
            }

            self.logger.debug("MEDIA_REMOTE_COMMAND_FAILED command=\(self.logName(for: command), privacy: .public)")

            guard routing != "MediaRemote Only" else { return }

            if self.mediaRemoteProvider.sendAppleScriptFallback(command, for: before) {
                _ = await self.waitForCommandEffect(
                    command,
                    before: before,
                    delay: Self.fallbackValidationDelay,
                    refreshMetadata: refreshMetadata
                )
            }
        }
    }

    private func waitForCommandEffect(
        _ command: PlaybackCommand,
        before: NowPlayingTrack?,
        delay: Duration,
        refreshMetadata: @escaping () async -> NowPlayingTrack?
    ) async -> Bool {
        try? await Task.sleep(for: delay)

        if let snapshot = mediaRemoteProvider.snapshotTrack(),
           Self.commandAppearsSuccessful(command, before: before, after: snapshot) {
            return true
        }

        guard let refreshed = await refreshMetadata() else {
            return false
        }

        return Self.commandAppearsSuccessful(command, before: before, after: refreshed)
    }

    private static func commandAppearsSuccessful(
        _ command: PlaybackCommand,
        before: NowPlayingTrack?,
        after: NowPlayingTrack?
    ) -> Bool {
        guard let after else {
            return false
        }

        switch command {
        case .playPause:
            guard let before else { return true }
            return before.playbackState != after.playbackState
        case .next:
            guard let before else { return true }
            return before.identity != after.identity
        case .previous:
            guard let before else { return true }
            return before.identity != after.identity || after.elapsed < max(before.elapsed - 1, 1)
        }
    }

    private func logPress(_ command: PlaybackCommand) {
        switch command {
        case .playPause:
            logger.debug("PLAY_PAUSE_PRESSED")
        case .next:
            logger.debug("NEXT_PRESSED")
        case .previous:
            logger.debug("PREVIOUS_PRESSED")
        }
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
}
