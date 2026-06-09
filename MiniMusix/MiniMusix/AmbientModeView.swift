import SwiftUI

struct AmbientModeView: View {
    @ObservedObject var store: NowPlayingStore
    var lyricsVisible: Bool
    var namespace: Namespace.ID
    var close: () -> Void
    var toggleLyrics: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ambientAnimation: Animation {
        AppMotion.primary(reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack {
            AmbientArtworkBackground(track: store.currentTrack, reduceMotion: reduceMotion)

            if let track = store.currentTrack {
                GeometryReader { proxy in
                    let safeWidth = max(proxy.size.width, 1)
                    let safeHeight = max(proxy.size.height, 1)
                    let horizontalPadding = max(min(safeWidth * 0.055, 104), 46)
                    let artworkSize = min(
                        min(safeHeight * (lyricsVisible ? 0.44 : 0.50), safeWidth * (lyricsVisible ? 0.31 : 0.34)),
                        lyricsVisible ? 500 : 560
                    )
                    let playerWidth = min(max(safeWidth * 0.31, 420), lyricsVisible ? 560 : 620)
                    let lyricsWidth = min(max(safeWidth - playerWidth - horizontalPadding * 2 - 76, 620), 960)

                    HStack(alignment: .center, spacing: lyricsVisible ? 76 : 0) {
                        ambientNowPlaying(track: track, artworkSize: artworkSize, width: playerWidth)
                            .frame(width: lyricsVisible ? playerWidth : min(safeWidth - horizontalPadding * 2, 680))

                        if lyricsVisible {
                            AmbientLyricsColumn(store: store)
                                .frame(width: lyricsWidth, height: min(900, safeHeight * 0.82))
                                .padding(.vertical, 14)
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity
                                            .combined(with: .offset(x: 18))
                                            .combined(with: .scale(scale: 0.99, anchor: .leading)),
                                        removal: .opacity
                                            .combined(with: .offset(x: 10))
                                            .combined(with: .scale(scale: 0.995, anchor: .leading))
                                    )
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, max(min(safeHeight * 0.07, 72), 38))
                    .animation(ambientAnimation, value: lyricsVisible)
                    .animation(AppMotion.content(reduceMotion: reduceMotion), value: track.identity)
                }
            } else {
                AmbientIdleView(refresh: {
                    Task { await store.refreshMetadata() }
                })
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .transition(AppMotion.subtleInsertion)
        .animation(ambientAnimation, value: lyricsVisible)
    }

    private func ambientNowPlaying(track: NowPlayingTrack, artworkSize: CGFloat, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            AlbumArtworkView(track: track, size: artworkSize, glow: true)
                .matchedGeometryEffect(id: "lockscreenArtwork", in: namespace)
                .shadow(color: .black.opacity(0.38), radius: 42, y: 24)
                .shadow(color: track.dominantColor.opacity(0.20), radius: 60, y: 22)

            AmbientPlayerCard(track: track, store: store, compact: lyricsVisible, width: min(width, artworkSize + 34))
        }
        .frame(maxWidth: .infinity, alignment: lyricsVisible ? .leading : .center)
    }
}

struct AmbientControlButton: View {
    var systemName: String
    var label: String
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(isHovered ? 1 : 0.88))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            Circle()
                .fill(Color.black.opacity(isHovered ? 0.58 : 0.46))
        }
        .background {
            Circle()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Circle()
                .stroke(.white.opacity(isHovered ? 0.55 : 0.34), lineWidth: 1.2)
                .allowsHitTesting(false)
        }
        .clipShape(Circle())
        .shadow(color: .black.opacity(isHovered ? 0.36 : 0.28), radius: isHovered ? 18 : 16, y: isHovered ? 8 : 6)
        .scaleEffect(AppMotion.hoverScale(isHovered, amount: 1.035))
        .help(label)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
        .animation(AppMotion.control(reduceMotion: reduceMotion), value: isHovered)
    }
}

private struct AmbientPlayerCard: View {
    var track: NowPlayingTrack
    @ObservedObject var store: NowPlayingStore
    var compact: Bool
    var width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(track.identity.title)
                    .font(.system(size: compact ? 28 : 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.98))
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)

                Text(track.identity.album.isEmpty ? track.identity.artist : "\(track.identity.artist) — \(track.identity.album)")
                    .font(.system(size: compact ? 17 : 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }

            VStack(spacing: 20) {
                HStack(spacing: 10) {
                    Text(TrackTimeRow.format(track.elapsed))
                        .frame(width: 48, alignment: .leading)

                    ProgressStrip(track: track, height: 6, usesGradient: false, solidColor: .white.opacity(0.94)) { seconds in
                        store.seek(to: seconds)
                    }

                    Text("-\(TrackTimeRow.format(max(track.identity.duration - track.elapsed, 0)))")
                        .frame(width: 52, alignment: .trailing)
                }
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.54))

                TransportControls(store: store, prominent: true)
                    .font(.system(size: 32, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: width)
        .shadow(color: .black.opacity(0.20), radius: 18, y: 10)
    }
}

private struct AmbientArtworkBackground: View {
    var track: NowPlayingTrack?
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 24, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let primary = track?.dominantColor ?? Color(red: 0.07, green: 0.10, blue: 0.18)
            let secondary = track?.secondaryColor ?? Color(red: 0.30, green: 0.22, blue: 0.32)
            let accent = track?.secondaryColor.opacity(0.9) ?? Color(red: 0.52, green: 0.28, blue: 0.22)

            ZStack {
                Color.black

                LinearGradient(
                    colors: [
                        primary.opacity(0.92),
                        secondary.opacity(0.70),
                        accent.opacity(0.38),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: UnitPoint(x: 0.08 + 0.18 * sin(time * 0.034), y: 0.02 + 0.10 * cos(time * 0.023)),
                    endPoint: UnitPoint(x: 0.92 + 0.08 * cos(time * 0.027), y: 0.94 + 0.10 * sin(time * 0.021))
                )
                .blendMode(.overlay)

                RadialGradient(
                    colors: [primary.opacity(0.92), secondary.opacity(0.34), .clear],
                    center: UnitPoint(x: 0.16 + 0.22 * sin(time * 0.025), y: 0.31 + 0.18 * cos(time * 0.020)),
                    startRadius: 40,
                    endRadius: 820
                )
                .blendMode(.screen)

                RadialGradient(
                    colors: [secondary.opacity(0.84), primary.opacity(0.25), .clear],
                    center: UnitPoint(x: 0.80 + 0.18 * cos(time * 0.022), y: 0.46 + 0.16 * sin(time * 0.026)),
                    startRadius: 60,
                    endRadius: 920
                )
                .blendMode(.screen)

                RadialGradient(
                    colors: [accent.opacity(0.46), primary.opacity(0.12), .clear],
                    center: UnitPoint(x: 0.48 + 0.12 * sin(time * 0.019), y: 0.18 + 0.08 * cos(time * 0.024)),
                    startRadius: 10,
                    endRadius: 560
                )
                .blendMode(.screen)

                RadialGradient(
                    colors: [secondary.opacity(0.26), .clear],
                    center: UnitPoint(x: 0.52 + 0.20 * cos(time * 0.014), y: 0.82 + 0.08 * sin(time * 0.018)),
                    startRadius: 140,
                    endRadius: 760
                )
                .blendMode(.plusLighter)

                Rectangle()
                    .fill(.ultraThinMaterial.opacity(0.22))
                    .blendMode(.softLight)

                Color.black.opacity(0.18)

                LinearGradient(
                    colors: [.black.opacity(0.38), .clear, .black.opacity(0.74)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [.black.opacity(0.16), .clear, .black.opacity(0.26)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct AmbientLyricsColumn: View {
    @ObservedObject var store: NowPlayingStore

    var body: some View {
        Group {
            switch store.lyrics {
            case .synced(let lines):
                AmbientSyncedLyricsView(
                    lines: lines,
                    elapsed: store.currentTrack?.elapsed ?? 0,
                    duration: store.currentTrack?.identity.duration ?? 0,
                    fontSize: store.settings.lyricFontSize
                ) { time in
                    store.seek(to: time)
                }
            case .plain(let text):
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 34, weight: .semibold))
                        .lineSpacing(10)
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .mask(AmbientLyricsFadeMask())
            case .loading:
                AmbientLyricsLoadingView()
            case .unavailable:
                UnavailableLyricsView(message: store.settings.missingLyricsMessage) {
                    store.reloadLyrics()
                } importLRC: {
                    store.importCustomLRC()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

private struct AmbientLyricsLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.86))

            VStack(spacing: 5) {
                Text("Fetching Lyrics")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))

                Text("Matching this song")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.16))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct AmbientSyncedLyricsView: View {
    private enum AmbientLyricItem: Identifiable {
        case lyric(DisplayLyricLine, index: Int)
        case dots(id: String, progress: Double, anchorIndex: Int?)
        case outro(id: String)

        var id: String {
            switch self {
            case .lyric(let line, _):
                line.id.uuidString
            case .dots(let id, _, _), .outro(let id):
                id
            }
        }
    }

    var lines: [SyncedLyricLine]
    var elapsed: TimeInterval
    var duration: TimeInterval
    var fontSize: CGFloat
    var seek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeLyricIndex: Int? {
        lines.lastIndex(where: { $0.time <= elapsed + lyricLeadTime })
    }

    private var currentIndex: Int {
        activeLyricIndex ?? 0
    }

    private var activeItemID: String? {
        if let placeholder {
            return placeholder.id
        }
        guard displayLines.indices.contains(currentIndex) else { return nil }
        return displayLines[currentIndex].id.uuidString
    }

    private var displayLines: [DisplayLyricLine] {
        lines.map { DisplayLyricLine(syncedLine: $0) }
    }

    private var visibleItems: [(item: AmbientLyricItem, distance: Int)] {
        guard !lines.isEmpty else { return [] }
        let items = allItems
        let activeIndex = items.firstIndex { $0.id == activeItemID } ?? min(currentIndex, max(items.count - 1, 0))
        let lower = max(activeIndex - 2, 0)
        let upper = min(activeIndex + 3, items.count - 1)
        guard lower <= upper else { return [] }
        return (lower...upper).map { index in
            (items[index], index - activeIndex)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(visibleItems, id: \.item.id) { entry in
                Group {
                    switch entry.item {
                    case .lyric(let line, _):
                        AmbientLyricTextBlock(line: line, distance: entry.distance, mainSize: mainSize(for: entry.distance))
                            .onTapGesture {
                                seek(max(0, line.time - lyricSeekLeadTime))
                            }
                    case .dots(_, let progress, _):
                        AmbientInstrumentalDots(progress: progress, fontSize: mainSize(for: entry.distance), isCurrent: entry.distance == 0)
                            .allowsHitTesting(false)
                    case .outro:
                        Image(systemName: "music.note")
                            .font(.system(size: mainSize(for: entry.distance), weight: .bold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(entry.distance == 0 ? 0.88 : 0.32))
                            .allowsHitTesting(false)
                    }
                }
                .opacity(opacity(for: entry.distance))
                .blur(radius: blur(for: entry.distance))
                .scaleEffect(scale(for: entry.distance), anchor: .leading)
                .offset(y: offset(for: entry.distance))
                .animation(AppMotion.lyricScroll(reduceMotion: reduceMotion), value: activeItemID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .mask(AmbientLyricsFadeMask())
    }

    private var allItems: [AmbientLyricItem] {
        var items = displayLines.enumerated().map { AmbientLyricItem.lyric($0.element, index: $0.offset) }
        guard let placeholder else { return items }

        switch placeholder.kind {
        case .dots:
            let item = AmbientLyricItem.dots(id: placeholder.id, progress: placeholder.progress(at: elapsed), anchorIndex: activeLyricIndex)
            if let activeLyricIndex {
                items.insert(item, at: min(activeLyricIndex + 1, items.count))
            } else {
                items.insert(item, at: 0)
            }
        case .outro:
            items.append(.outro(id: placeholder.id))
        }

        return items
    }

    private var placeholder: AmbientInstrumentalPlaceholder? {
        guard !lines.isEmpty else { return nil }

        if activeLyricIndex == nil,
           let first = lines.first,
           first.time >= instrumentalGapThreshold,
           elapsed < first.time - instrumentalHoldDuration {
            return AmbientInstrumentalPlaceholder(
                id: "ambient-instrumental-intro-\(first.id.uuidString)",
                kind: .dots,
                start: 0,
                fillEnd: max(first.time - instrumentalHoldDuration, 0.01),
                end: first.time
            )
        }

        guard let activeLyricIndex else { return nil }

        if activeLyricIndex < lines.count - 1 {
            let current = lines[activeLyricIndex]
            let next = lines[activeLyricIndex + 1]
            let gap = next.time - current.time
            let start = current.time + lyricLeadTime
            let fillEnd = next.time - instrumentalHoldDuration

            if gap >= instrumentalGapThreshold,
               elapsed >= start,
               elapsed < next.time {
                return AmbientInstrumentalPlaceholder(
                    id: "ambient-instrumental-\(current.id.uuidString)-\(next.id.uuidString)",
                    kind: .dots,
                    start: start,
                    fillEnd: max(fillEnd, start + 0.01),
                    end: next.time
                )
            }
        } else if let last = lines.last {
            let start = last.time + outroVisibleDuration
            let remaining = duration > 0 ? duration - elapsed : 0

            if elapsed >= start,
               remaining >= outroRemainingThreshold {
                return AmbientInstrumentalPlaceholder(
                    id: "ambient-outro-\(last.id.uuidString)",
                    kind: .outro,
                    start: start,
                    fillEnd: duration,
                    end: duration
                )
            }
        }

        return nil
    }

    private var lyricLeadTime: TimeInterval { 0.18 }
    private var lyricSeekLeadTime: TimeInterval { 0.15 }
    private var instrumentalGapThreshold: TimeInterval { 10.0 }
    private var outroRemainingThreshold: TimeInterval { 8.0 }
    private var outroVisibleDuration: TimeInterval { 3.2 }
    private var instrumentalHoldDuration: TimeInterval { 0.5 }

    private func mainSize(for distance: Int) -> CGFloat {
        if distance == 0 {
            return min(max(fontSize + 26, 48), 62)
        }

        if abs(distance) == 1 {
            return min(max(fontSize + 20, 41), 54)
        }

        return min(max(fontSize + 16, 35), 48)
    }

    private func opacity(for distance: Int) -> Double {
        switch abs(distance) {
        case 0: 1
        case 1: 0.50
        case 2: 0.28
        default: 0.15
        }
    }

    private func blur(for distance: Int) -> CGFloat {
        switch abs(distance) {
        case 0: 0
        case 1: 4.2
        case 2: 8.0
        default: 12.0
        }
    }

    private func scale(for distance: Int) -> CGFloat {
        switch abs(distance) {
        case 0: 1.0
        case 1: 0.985
        default: 0.955
        }
    }

    private func offset(for distance: Int) -> CGFloat {
        let base: CGFloat = 174
        if distance == 0 { return 0 }
        return CGFloat(distance) * base
    }
}

private struct AmbientLyricTextBlock: View {
    var line: DisplayLyricLine
    var distance: Int
    var mainSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: distance == 0 ? 12 : 8) {
            Text(line.mainText)
                .font(.system(size: mainSize, weight: .bold))
                .lineLimit(distance == 0 ? 3 : 2)
                .minimumScaleFactor(distance == 0 ? 0.62 : 0.70)
                .fixedSize(horizontal: false, vertical: true)
                .allowsTightening(true)

            if distance == 0, let backing = line.backingText {
                Text(backing)
                    .font(.system(size: max(mainSize * 0.44, 18), weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.70)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white.opacity(0.36))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(distance == 0 ? 0.22 : 0), radius: 10, y: 5)
    }
}

private struct AmbientInstrumentalDots: View {
    var progress: Double
    var fontSize: CGFloat
    var isCurrent: Bool

    var body: some View {
        HStack(spacing: max(12, fontSize * 0.30)) {
            ForEach(0..<3, id: \.self) { index in
                let fill = min(max(progress * 3 - Double(index), 0), 1)
                ZStack(alignment: .leading) {
                    Circle()
                        .fill(.white.opacity(isCurrent ? 0.28 : 0.14))
                    GeometryReader { proxy in
                        Circle()
                            .fill(.white)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .offset(x: -proxy.size.width * (1 - fill))
                    }
                    .clipShape(Circle())
                }
                .frame(width: max(17, fontSize * 0.42), height: max(17, fontSize * 0.42))
                .offset(y: -5 * fill)
                .scaleEffect(1 + 0.025 * fill)
                .shadow(color: .white.opacity(fill > 0 ? 0.18 : 0), radius: 5 + 3 * fill, y: 2 * fill)
            }
        }
        .animation(AppMotion.content(), value: progress)
    }
}

private struct AmbientInstrumentalPlaceholder {
    enum Kind {
        case dots
        case outro
    }

    var id: String
    var kind: Kind
    var start: TimeInterval
    var fillEnd: TimeInterval
    var end: TimeInterval

    func progress(at elapsed: TimeInterval) -> Double {
        let span = max(fillEnd - start, 0.01)
        return min(max((elapsed - start) / span, 0), 1)
    }
}

private struct AmbientLyricsFadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct AmbientIdleView: View {
    var refresh: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note")
                .font(.system(size: 58, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text("Not Playing")
                .font(.system(size: 34, weight: .bold))
            Button("Refresh", action: refresh)
                .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
    }
}
