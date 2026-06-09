import SwiftUI

/// Lock-screen / screen-saver exclusive player — not shared with the floating mini player.
struct LockScreenPlayerView: View {
    @ObservedObject var store: NowPlayingStore
    var layout: LockScreenLayout

    private var track: NowPlayingTrack? {
        store.currentTrack
    }

    private var tint: Color {
        track?.dominantColor ?? Color(red: 0.43, green: 0.49, blue: 0.39)
    }

    private var showsProgress: Bool {
        layout.showsProgress && (track?.identity.duration ?? 0) > 0
    }

    var body: some View {
        HStack(spacing: layout.contentSpacing) {
            artwork

            VStack(alignment: .leading, spacing: max(6, 8 * layout.scale)) {
                trackInfo

                if showsProgress, let track {
                    lockProgress(for: track)
                }

                transport
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
        .frame(width: layout.contentSize.width, height: layout.contentSize.height)
        .background {
            let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
            shape.fill(.ultraThinMaterial)
        }
        .background {
            let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
            shape.fill(
                LinearGradient(
                    colors: [tint.opacity(0.18), tint.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12 * layout.scale, y: 6 * layout.scale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var artwork: some View {
        let corner = layout.artworkSize * 0.21

        if let track {
            AlbumArtworkView(track: track, size: layout.artworkSize, glow: false)
        } else {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.white.opacity(0.10))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: layout.artworkSize * 0.36, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: layout.artworkSize, height: layout.artworkSize)
        }
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track?.identity.title ?? "Not Playing")
                .font(.system(size: layout.titleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(track?.identity.artist ?? "Waiting for media")
                .font(.system(size: layout.artistFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private func lockProgress(for track: NowPlayingTrack) -> some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: proxy.size.width * track.progress)
                }
            }
            .frame(height: max(2, 3 * layout.scale))

            HStack {
                Text(TrackTimeRow.format(track.elapsed))
                Spacer()
                Text(TrackTimeRow.format(track.identity.duration))
            }
            .font(.system(size: max(10, 11 * layout.scale), weight: .medium).monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }

    private var transport: some View {
        HStack(spacing: max(8, 12 * layout.scale)) {
            LockScreenControlButton(systemName: "backward.fill", size: layout.controlSize) {
                store.skipBack()
            }

            LockScreenControlButton(
                systemName: track?.playbackState == .playing ? "pause.fill" : "play.fill",
                size: layout.prominentControlSize,
                prominent: true,
                iconScale: layout.scale
            ) {
                store.togglePlayback()
            }

            LockScreenControlButton(systemName: "forward.fill", size: layout.controlSize) {
                store.skipForward()
            }
        }
    }

    private var accessibilitySummary: String {
        guard let track else { return "MiniMusix lock screen player, not playing" }
        return "MiniMusix lock screen player, \(track.identity.title) by \(track.identity.artist)"
    }
}

private struct LockScreenControlButton: View {
    var systemName: String
    var size: CGFloat
    var prominent = false
    var iconScale: CGFloat = 1
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: (prominent ? 15 : 12) * iconScale, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(.white.opacity(prominent ? 0.22 : 0.14))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName)
    }
}
