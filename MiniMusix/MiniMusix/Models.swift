import SwiftUI
import AppKit

enum PlaybackSource: String, CaseIterable, Identifiable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case mediaRemote = "All Apps"
    case cached = "Last Song"
    case automatic = "Automatic"

    var id: String { rawValue }
}

enum PlaybackState: String {
    case playing
    case paused
    case stopped
}

enum MiniPlayerMode: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case expanded = "Expanded"
    case lyricsFocus = "Lyrics Focus"

    var id: String { rawValue }
}

enum MiniPlayerPresentationMode {
    case compact
    case expanded

    init(miniPlayerMode: MiniPlayerMode) {
        switch miniPlayerMode {
        case .compact:
            self = .compact
        case .expanded, .lyricsFocus:
            self = .expanded
        }
    }

    var miniPlayerMode: MiniPlayerMode {
        switch self {
        case .compact:
            return .compact
        case .expanded:
            return .expanded
        }
    }
}

struct TrackIdentity: Hashable, Codable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
}

struct NowPlayingTrack: Identifiable {
    var id: TrackIdentity { identity }
    let identity: TrackIdentity
    var artworkSystemName: String
    var artwork: NSImage?
    var dominantColor: Color
    var secondaryColor: Color
    var elapsed: TimeInterval
    /// Playback rate from the active player (1.0 = normal speed). Used to interpolate live position between updates.
    var playbackRate: Double = 1.0
    var playbackState: PlaybackState
    var source: PlaybackSource
    var applicationName: String?
    var bundleIdentifier: String?

    var progress: Double {
        guard identity.duration > 0 else { return 0 }
        return min(max(elapsed / identity.duration, 0), 1)
    }
}

extension NowPlayingTrack: Hashable {
    static func == (lhs: NowPlayingTrack, rhs: NowPlayingTrack) -> Bool {
        lhs.identity == rhs.identity
        && lhs.elapsed == rhs.elapsed
        && lhs.playbackState == rhs.playbackState
        && lhs.source == rhs.source
        && lhs.applicationName == rhs.applicationName
        && lhs.bundleIdentifier == rhs.bundleIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        hasher.combine(elapsed)
        hasher.combine(playbackState)
        hasher.combine(source)
        hasher.combine(applicationName)
        hasher.combine(bundleIdentifier)
    }
}

struct QueueItem: Identifiable, Hashable {
    let id = UUID()
    var track: NowPlayingTrack
}

struct SyncedLyricLine: Identifiable, Hashable {
    let id = UUID()
    var time: TimeInterval
    var text: String
}

struct DisplayLyricLine: Identifiable, Hashable {
    let id: UUID
    let time: TimeInterval
    let mainText: String
    let backingText: String?

    init(id: UUID = UUID(), time: TimeInterval, mainText: String, backingText: String?) {
        self.id = id
        self.time = time
        self.mainText = mainText
        self.backingText = backingText
    }

    init(syncedLine: SyncedLyricLine) {
        let split = Self.splitTrailingBackingText(from: syncedLine.text)
        self.id = syncedLine.id
        self.time = syncedLine.time
        self.mainText = split.mainText
        self.backingText = split.backingText.map(Self.displayBackingText)
    }

    private static func splitTrailingBackingText(from text: String) -> (mainText: String, backingText: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")") else {
            return (text, nil)
        }

        guard let openIndex = trimmed.lastIndex(of: "(") else {
            return (text, nil)
        }

        let backingStart = trimmed.index(after: openIndex)
        let backingEnd = trimmed.index(before: trimmed.endIndex)
        let backing = String(trimmed[backingStart..<backingEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let main = String(trimmed[..<openIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !main.isEmpty, !backing.isEmpty else {
            return (text, nil)
        }

        return (main, backing)
    }

    nonisolated private static func displayBackingText(_ text: String) -> String {
        let lowercased = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\bi\b"#, with: "I", options: .regularExpression)

        guard let firstLetter = lowercased.firstIndex(where: { $0.isLetter }) else {
            return lowercased
        }

        let nextIndex = lowercased.index(after: firstLetter)
        return lowercased[..<firstLetter]
            + lowercased[firstLetter].uppercased()
            + lowercased[nextIndex...]
    }
}

enum LyricsPayload: Equatable {
    case loading
    case synced([SyncedLyricLine])
    case plain(String)
    case unavailable
}

enum BackendPermissionState: Equatable {
    case unknown
    case ready
    case unavailable(String)
}

struct MiniMusixSettings: Equatable {
    var source: PlaybackSource = .automatic
    var launchAtLogin = false
    var alwaysOnTop = true
    var hideFromScreenCapture = false
    var hideWhenPlaybackStops = false
    var preferredMode: MiniPlayerMode = .compact
    var albumTintStrength = 0.12
    var artworkGlow = true
    var cornerRadius = 28.0
    var positionBehavior = "Bottom Center"
    var enableLRCLIB = true
    var syncedLyrics = true
    var plainLyrics = true
    var lyricFontSize = 20.0
    var missingLyricsMessage = "Bummer, someone forgot to add lyrics."
    var queueButtonEnabled = true
    var showLyricsButton = true
    var ambientModeEnabled = true
    var lowBatteryWarningPercent = 20
    var progressBarGradient = true
    var dragReordering = true
    var compactRows = false
    var glassIntensity = 0.72
    var glassStyle = "Regular"
    var systemAccent = true
    var albumColors = true
    var reduceMotionSupport = true
    var metadataRefreshRate = 2.0
    var commandRouting = "Fast + MediaRemote"
    var mediaRemotePermission = BackendPermissionState.unknown
    var musicAutomationPermission = BackendPermissionState.unknown
    var spotifyAutomationPermission = BackendPermissionState.unknown
    var bluetoothPermission = BackendPermissionState.unknown
    var lyricsPermission = BackendPermissionState.unknown
}

extension NowPlayingTrack {
    static let sample = NowPlayingTrack(
        identity: TrackIdentity(
            title: "Silver Lining",
            artist: "The Local Forecast",
            album: "Tahoe Sessions",
            duration: 214
        ),
        artworkSystemName: "music.note",
        artwork: nil,
        dominantColor: Color(red: 0.43, green: 0.49, blue: 0.39),
        secondaryColor: Color(red: 0.70, green: 0.55, blue: 0.35),
        elapsed: 82,
        playbackState: .playing,
        source: .appleMusic,
        applicationName: "Music",
        bundleIdentifier: "com.apple.Music"
    )

    static let samples: [NowPlayingTrack] = [
        .sample,
        NowPlayingTrack(
            identity: TrackIdentity(title: "Low Sun", artist: "Mira Vale", album: "Window Seat", duration: 188),
            artworkSystemName: "sparkles",
            artwork: nil,
            dominantColor: Color(red: 0.68, green: 0.48, blue: 0.32),
            secondaryColor: Color(red: 0.52, green: 0.50, blue: 0.43),
            elapsed: 0,
            playbackState: .paused,
            source: .spotify,
            applicationName: "Spotify",
            bundleIdentifier: "com.spotify.client"
        ),
        NowPlayingTrack(
            identity: TrackIdentity(title: "Quiet Current", artist: "North Pier", album: "Glasswater", duration: 241),
            artworkSystemName: "water.waves",
            artwork: nil,
            dominantColor: Color(red: 0.36, green: 0.46, blue: 0.45),
            secondaryColor: Color(red: 0.58, green: 0.63, blue: 0.52),
            elapsed: 0,
            playbackState: .paused,
            source: .mediaRemote,
            applicationName: "MediaRemote",
            bundleIdentifier: nil
        ),
        NowPlayingTrack(
            identity: TrackIdentity(title: "Afterimage", artist: "Lane & Harbor", album: "Night Rooms", duration: 202),
            artworkSystemName: "moon.stars",
            artwork: nil,
            dominantColor: Color(red: 0.43, green: 0.41, blue: 0.37),
            secondaryColor: Color(red: 0.64, green: 0.55, blue: 0.44),
            elapsed: 0,
            playbackState: .paused,
            source: .cached,
            applicationName: nil,
            bundleIdentifier: nil
        )
    ]
}
