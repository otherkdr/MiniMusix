import Foundation

protocol PlaybackProvider {
    var source: PlaybackSource { get }
    func currentTrack() async -> NowPlayingTrack?
}

enum PlaybackCommand {
    case playPause
    case next
    case previous
}
