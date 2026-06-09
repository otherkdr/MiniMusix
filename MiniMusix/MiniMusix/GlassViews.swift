import SwiftUI

struct AlbumArtworkView: View {
    var track: NowPlayingTrack
    var size: CGFloat
    var glow: Bool

    var body: some View {
        let artworkCornerRadius = max(7, size * 0.042)

        ZStack {
            if let artwork = track.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [track.dominantColor, track.secondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: track.artworkSystemName)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: glow ? track.dominantColor.opacity(0.28) : .clear, radius: 16, y: 7)
        .accessibilityLabel("\(track.identity.album) artwork")
    }
}

struct ProgressStrip: View {
    var track: NowPlayingTrack
    var height: CGFloat = 5
    var usesGradient = true
    var solidColor: Color?
    var seek: ((TimeInterval) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.16))
                Capsule()
                    .fill(progressFill)
                    .frame(width: proxy.size.width * track.progress)
                    .animation(AppMotion.progress(), value: track.progress)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard track.identity.duration > 0 else { return }
                        let ratio = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        seek?(track.identity.duration * ratio)
                    }
            )
        }
        .frame(height: height)
    }

    private var progressFill: some ShapeStyle {
        if usesGradient {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [track.dominantColor, track.secondaryColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }

        return AnyShapeStyle(solidColor ?? track.dominantColor)
    }
}

struct TrackTimeRow: View {
    var track: NowPlayingTrack

    var body: some View {
        HStack {
            Text(Self.format(track.elapsed))
            Spacer()
            Text(track.identity.duration > 0 ? Self.format(track.identity.duration) : "--:--")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Elapsed \(Self.format(track.elapsed)) of \(track.identity.duration > 0 ? Self.format(track.identity.duration) : "unknown duration")")
    }

    static func format(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

struct GlassIconButton: View {
    var systemName: String
    var label: String
    var tint: Color
    var size: CGFloat = 40
    var isProminent = false
    var showsChrome = true
    var symbolEffectActive = false
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isProminent ? 18 : 15, weight: isProminent ? .bold : .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: symbolEffectActive)
        }
        .buttonStyle(.plain)

        if showsChrome {
            button
                .background { glassCircleBackground(tint: tint, hovered: isHovered) }
                .clipShape(Circle())
                .transportButtonBehavior(tint: tint, isHovered: isHovered, scale: 1.055) {
                    self.isHovered = $0
                }
                .contentShape(Circle())
                .help(label)
                .accessibilityLabel(label)
        } else {
            button
                .transportButtonBehavior(tint: tint, isHovered: isHovered, scale: 1.12) {
                    self.isHovered = $0
                }
                .contentShape(Rectangle())
                .help(label)
                .accessibilityLabel(label)
        }
    }
}

private extension View {
    func transportButtonBehavior(tint: Color, isHovered: Bool, scale: CGFloat, onHover: @escaping (Bool) -> Void) -> some View {
        self
        .shadow(color: tint.opacity(isHovered ? 0.10 : 0.035), radius: isHovered ? 8 : 3, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered ? min(scale, 1.045) : 1)
        .animation(AppMotion.control(), value: isHovered)
        .onHover(perform: onHover)
    }
}

struct TransportControls: View {
    @ObservedObject var store: NowPlayingStore
    var prominent = false

    var body: some View {
        let isPlaying = store.currentTrack?.playbackState == .playing
        HStack(spacing: prominent ? 11 : 7) {
            GlassIconButton(
                systemName: "backward.fill",
                label: "Previous",
                tint: store.currentTrack?.secondaryColor ?? .secondary,
                size: prominent ? 42 : 34,
                showsChrome: false
            ) {
                store.skipBack()
            }

            GlassIconButton(
                systemName: isPlaying ? "pause.fill" : "play.fill",
                label: isPlaying ? "Pause" : "Play",
                tint: store.currentTrack?.dominantColor ?? .secondary,
                size: prominent ? 50 : 42,
                isProminent: true,
                showsChrome: false,
                symbolEffectActive: isPlaying
            ) {
                store.togglePlayback()
            }

            GlassIconButton(
                systemName: "forward.fill",
                label: "Next",
                tint: store.currentTrack?.secondaryColor ?? .secondary,
                size: prominent ? 42 : 34,
                showsChrome: false
            ) {
                store.skipForward()
            }
        }
    }
}

struct SideGlassButton: View {
    var systemName: String
    var label: String
    var tint: Color
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let shape = Circle()

        let button = Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)

        if #available(macOS 26.0, *) {
            button
                .glassEffect(.regular.interactive(), in: shape)
                .overlay {
                    shape
                        .fill(tint.opacity(isHovered ? 0.10 : 0.045))
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
                .sideButtonBehavior(shape: shape, tint: tint, isHovered: isHovered) {
                    self.isHovered = $0
                }
                .help(label)
                .accessibilityLabel(label)
        } else {
            button
                .background { glassCircleBackground(tint: tint, hovered: isHovered, prominent: false) }
                .clipShape(shape)
                .sideButtonBehavior(shape: shape, tint: tint, isHovered: isHovered) {
                    self.isHovered = $0
                }
                .help(label)
                .accessibilityLabel(label)
        }
    }
}

private extension View {
    func sideButtonBehavior<S: Shape>(shape: S, tint: Color, isHovered: Bool, onHover: @escaping (Bool) -> Void) -> some View {
        self
        .shadow(color: tint.opacity(isHovered ? 0.14 : 0.05), radius: isHovered ? 10 : 5, y: isHovered ? 5 : 3)
        .scaleEffect(AppMotion.hoverScale(isHovered, amount: 1.035))
        .animation(AppMotion.control(), value: isHovered)
        .onHover(perform: onHover)
        .contentShape(shape)
    }
}

struct AudioOutputPickerButton: View {
    @ObservedObject var monitor: AudioOutputDeviceMonitor
    var tint: Color
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let shape = Circle()

        Button(action: action) {
            Image(systemName: "airplayaudio")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 48, height: 48)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .modifier(AudioOutputButtonChrome(shape: shape, tint: tint, isHovered: isHovered))
        .shadow(color: tint.opacity(isHovered ? 0.14 : 0.05), radius: isHovered ? 10 : 5, y: isHovered ? 5 : 3)
        .scaleEffect(AppMotion.hoverScale(isHovered, amount: 1.035))
        .animation(AppMotion.control(), value: isHovered)
        .onHover { isHovered = $0 }
        .help("Audio Output")
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let defaultDevice = monitor.defaultDevice {
            return "Audio output, \(defaultDevice.name)"
        }

        return "Audio output"
    }
}

private struct AudioOutputButtonChrome<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color
    var isHovered: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
                .overlay {
                    shape
                        .fill(tint.opacity(isHovered ? 0.10 : 0.045))
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
        } else {
            content
                .background { glassCircleBackground(tint: tint, hovered: isHovered, prominent: false) }
                .clipShape(shape)
        }
    }
}

struct TrackTextStack: View {
    var track: NowPlayingTrack
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 5) {
            Text(track.identity.title)
                .font(compact ? .headline : .title3.weight(.semibold))
                .lineLimit(1)
                .contentTransition(.opacity)
            Text(track.identity.artist)
                .font(compact ? .caption : .callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !compact {
                Text("\(track.identity.album) • \(track.source.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .animation(AppMotion.panel(), value: compact)
        .animation(AppMotion.content(), value: track.identity)
    }
}

struct LiquidGlassCloseButton: View {
    var label: String = "Close"
    var tint: Color = Color(red: 1.0, green: 0.35, blue: 0.32)
    var size: CGFloat = 32
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.34, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary.opacity(isHovered ? 0.95 : 0.78))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)

        closeChrome(button)
            .onHover { isHovered = $0 }
            .animation(AppMotion.control(), value: isHovered)
    }

    @ViewBuilder
    private func closeChrome(_ content: some View) -> some View {
        let shape = Circle()

        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
                .overlay {
                    shape
                        .fill(tint.opacity(isHovered ? 0.18 : 0.08))
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
                .shadow(color: tint.opacity(isHovered ? 0.18 : 0.08), radius: isHovered ? 12 : 7, y: isHovered ? 6 : 3)
                .scaleEffect(AppMotion.hoverScale(isHovered, amount: 1.035))
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                }
                .background {
                    shape.fill(tint.opacity(isHovered ? 0.16 : 0.08))
                }
                .clipShape(shape)
                .shadow(color: tint.opacity(isHovered ? 0.16 : 0.07), radius: isHovered ? 12 : 7, y: isHovered ? 6 : 3)
                .scaleEffect(AppMotion.hoverScale(isHovered, amount: 1.035))
        }
    }
}

struct MiniPlayerPill: View {
    @ObservedObject var store: NowPlayingStore
    var mode: MiniPlayerMode
    var namespace: Namespace.ID?
    var artworkAction: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        if let track = store.currentTrack {
            activePill(track)
        } else {
            idlePill
        }
    }

    private func activePill(_ track: NowPlayingTrack) -> some View {
        let primaryTint = store.settings.albumColors ? track.dominantColor : SettingsPalette.light
        let secondaryTint = store.settings.albumColors ? track.secondaryColor : SettingsPalette.mid

        return HStack(spacing: mode == .compact ? 12 : 18) {
            artwork(track)

            VStack(alignment: .leading, spacing: mode == .compact ? 8 : 14) {
                TrackTextStack(track: track, compact: mode == .compact)
                VStack(spacing: mode == .compact ? 4 : 6) {
                    ProgressStrip(track: track, height: mode == .compact ? 3 : 5, usesGradient: store.settings.progressBarGradient && store.settings.albumColors, solidColor: primaryTint) { seconds in
                        store.seek(to: seconds)
                    }
                    TrackTimeRow(track: track)
                }
            }
            .frame(width: mode == .compact ? 178 : 270, alignment: .leading)

            TransportControls(store: store, prominent: mode != .compact)
        }
        .modifier(PillChrome(store: store, tint: primaryTint, secondaryTint: secondaryTint, isHovered: $isHovered, mode: mode))
        .animation(AppMotion.primary(), value: mode)
        .animation(AppMotion.content(), value: track.identity)
    }

    @ViewBuilder
    private func artwork(_ track: NowPlayingTrack) -> some View {
        let artwork = AlbumArtworkView(track: track, size: mode == .compact ? 60 : 98, glow: store.settings.artworkGlow)

        if let artworkAction {
            matchedArtwork(artwork)
            .onTapGesture(count: 2, perform: artworkAction)
            .contentShape(RoundedRectangle(cornerRadius: (mode == .compact ? 60 : 98) * 0.22, style: .continuous))
            .help("Open Ambient Mode")
        } else {
            matchedArtwork(artwork)
        }
    }

    @ViewBuilder
    private func matchedArtwork<Content: View>(_ content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "lockscreenArtwork", in: namespace)
        } else {
            content
        }
    }

    private var idlePill: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white.opacity(0.08))
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("Not Playing")
                    .font(.headline)
                Text("Waiting for media")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 180, alignment: .leading)

            GlassIconButton(systemName: "arrow.clockwise", label: "Refresh Playback", tint: .secondary, size: 40) {
                Task { await store.refreshMetadata() }
            }
        }
        .modifier(PillChrome(store: store, tint: .secondary, secondaryTint: Color(nsColor: .tertiaryLabelColor), isHovered: $isHovered, mode: .compact))
    }
}

private struct PillChrome: ViewModifier {
    @ObservedObject var store: NowPlayingStore
    var tint: Color
    var secondaryTint: Color
    @Binding var isHovered: Bool
    var mode: MiniPlayerMode

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: store.settings.cornerRadius, style: .continuous)
        let glassStyleMultiplier = switch store.settings.glassStyle {
        case "Soft": 0.72
        case "Dense": 1.24
        default: 1.0
        }

        let paddedContent = content
            .padding(mode == .compact ? 10 : 16)

        if #available(macOS 26.0, *) {
            paddedContent
                .glassEffect(.regular.interactive(), in: shape)
                .overlay {
                    shape
                        .fill(tint.opacity(store.settings.albumTintStrength * store.settings.glassIntensity * glassStyleMultiplier * 0.42))
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
                .pillBehavior(tint: tint, isHovered: isHovered) {
                    self.isHovered = $0
                }
                .animation(AppMotion.primary(), value: mode)
        } else {
            paddedContent
                .background { shape.fill(.ultraThinMaterial) }
                .background { shape.fill(tint.opacity(store.settings.albumTintStrength * glassStyleMultiplier * 0.9)) }
                .clipShape(shape)
                .pillBehavior(tint: tint, isHovered: isHovered) {
                    self.isHovered = $0
                }
                .animation(AppMotion.primary(), value: mode)
        }
    }
}

extension View {
    func panelSurface(cornerRadius: CGFloat = 28, tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            return glassEffect(.regular.interactive(), in: shape)
                .overlay {
                    shape
                        .fill(tint.opacity(0.045))
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
        } else {
            return background { shape.fill(.ultraThinMaterial) }
                .background { shape.fill(tint.opacity(0.09)) }
                .clipShape(shape)
        }
    }
}

private extension View {
    func pillBehavior(tint: Color, isHovered: Bool, onHover: @escaping (Bool) -> Void) -> some View {
        self
            .shadow(color: tint.opacity(isHovered ? 0.12 : 0.06), radius: isHovered ? 14 : 10, y: isHovered ? 7 : 5)
            .scaleEffect(AppMotion.hoverScale(isHovered, amount: 1.004))
            .onHover(perform: onHover)
            .animation(AppMotion.control(), value: isHovered)
    }
}

@ViewBuilder
private func glassCircleBackground(tint: Color, hovered: Bool, prominent: Bool = true) -> some View {
    let fillOpacity = prominent
        ? (hovered ? 0.16 : 0.07)
        : (hovered ? 0.13 : 0.055)

    ZStack {
        Circle().fill(.ultraThinMaterial)
        Circle().fill(tint.opacity(fillOpacity))
    }
}
