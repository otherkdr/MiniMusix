import SwiftUI

struct LyricsPanel: View {
    @ObservedObject var store: NowPlayingStore
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Text("Lyrics")
                    .font(.headline)
                Spacer()
                GlassIconButton(systemName: "xmark", label: "Close Lyrics", tint: store.currentTrack?.secondaryColor ?? .secondary, size: 30, action: close)
            }

            switch store.lyrics {
            case .loading:
                LyricsLoadingView()
                    .transition(AppMotion.subtleInsertion)
            case .synced(let lines):
                SyncedLyricsView(
                    lines: lines,
                    elapsed: store.currentTrack?.elapsed ?? 0,
                    duration: store.currentTrack?.identity.duration ?? 0,
                    fontSize: store.settings.lyricFontSize
                ) { time in
                    store.seek(to: time)
                }
                .transition(AppMotion.subtleInsertion)
            case .plain(let text):
                ScrollView {
                    Text(text)
                        .font(.system(size: store.settings.lyricFontSize, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 184)
                .transition(AppMotion.subtleInsertion)
            case .unavailable:
                UnavailableLyricsView(message: store.settings.missingLyricsMessage) {
                    store.reloadLyrics()
                } importLRC: {
                    store.importCustomLRC()
                }
                .transition(AppMotion.subtleInsertion)
            }
        }
        .padding(14)
        .frame(width: 300)
        .panelSurface(tint: store.currentTrack?.secondaryColor ?? .secondary)
        .shadow(color: (store.currentTrack?.secondaryColor ?? .secondary).opacity(0.08), radius: 16, y: 8)
        .animation(AppMotion.panel(), value: store.lyrics)
    }
}

struct AudioOutputPanel: View {
    @ObservedObject var monitor: AudioOutputDeviceMonitor
    var tint: Color
    var close: () -> Void
    var selectionAction: (AudioOutputDevice) -> Void

    private var wirelessDevices: [AudioOutputDevice] {
        bluetoothDevices + airPlayDevices
    }

    private var bluetoothDevices: [AudioOutputDevice] {
        monitor.devices.filter { $0.kind == .bluetooth }
    }

    private var airPlayDevices: [AudioOutputDevice] {
        monitor.devices.filter { $0.kind == .airPlay }
    }

    private var otherDevices: [AudioOutputDevice] {
        monitor.devices.filter { !$0.isWireless }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Audio Output")
                    .font(.headline)
                Text("\(monitor.devices.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(tint.opacity(0.08))
                    }
                Spacer(minLength: 0)
                GlassIconButton(systemName: "xmark", label: "Close Audio Output", tint: tint, size: 30, action: close)
            }

            Group {
                if monitor.isLoading {
                    AudioOutputLoadingRow(tint: tint)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            if wirelessDevices.isEmpty {
                                AudioOutputEmptyRow(devices: monitor.nearbyWirelessDevices, tint: tint)
                            } else {
                                if !bluetoothDevices.isEmpty {
                                    deviceSection(title: "Bluetooth", devices: bluetoothDevices)
                                }

                                if !airPlayDevices.isEmpty {
                                    deviceSection(title: "AirPlay", devices: airPlayDevices)
                                }
                            }

                            if !otherDevices.isEmpty {
                                deviceSection(title: "Other", devices: otherDevices)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
            }
            .frame(height: 176, alignment: .top)

            Button {
                monitor.loadDevices()
            } label: {
                Label(monitor.isLoading ? "Detecting Devices" : "Refresh Devices", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(monitor.isLoading)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(tint.opacity(0.08))
            }
            .contentShape(Capsule())
            .help("Refresh audio output devices")
        }
        .padding(12)
        .frame(width: 288)
        .panelSurface(tint: tint)
        .shadow(color: tint.opacity(0.08), radius: 16, y: 8)
        .animation(AppMotion.panel(), value: monitor.isLoading)
        .animation(AppMotion.panel(), value: monitor.devices)
        .animation(AppMotion.content(), value: monitor.nearbyWirelessDevices)
    }

    private func deviceSection(title: String, devices: [AudioOutputDevice]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("\(devices.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }

            ForEach(devices) { device in
                AudioOutputDeviceRow(
                    device: device,
                    tint: tint,
                    select: {
                        selectionAction(device)
                    }
                )
            }
        }
    }
}

private struct AudioOutputDeviceRow: View {
    var device: AudioOutputDevice
    var tint: Color
    var select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                Image(systemName: device.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18)

                Text(device.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if device.isDefault {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(isHovered || device.isDefault ? 0.11 : 0.045))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(device.isDefault ? "\(device.name), current audio output" : "Set audio output to \(device.name)")
    }
}

private struct AudioOutputEmptyRow: View {
    var devices: [NearbyWirelessDevice]
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                Text(devices.isEmpty ? "No nearby devices" : "Nearby devices")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }

            if devices.isEmpty {
                Text("MiniMusix did not find nearby Bluetooth devices. Turn on your headphones or speaker, then refresh.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(devices) { device in
                        NearbyWirelessDeviceRow(device: device, tint: tint)
                    }
                }

                Text("Connect a device in macOS Sound settings, then choose it here.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.045))
        }
    }
}

private struct NearbyWirelessDeviceRow: View {
    var device: NearbyWirelessDevice
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(device.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(device.isConnectable ? "Nearby" : "Seen nearby")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(0.035))
        }
        .accessibilityLabel("\(device.name), nearby")
    }
}

private struct AudioOutputLoadingRow: View {
    var tint: Color

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(tint)
            Text("Detecting audio devices")
                .font(.caption.weight(.semibold))
            Text("Looking for available Bluetooth and AirPlay outputs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
    }
}

struct LyricsLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Fetching lyrics")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 184)
    }
}

struct SyncedLyricsView: View {
    var lines: [SyncedLyricLine]
    var elapsed: TimeInterval
    var duration: TimeInterval
    var fontSize: CGFloat
    var seek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAutoScrollPaused = false
    @State private var isProgrammaticScroll = false
    @State private var lastScrollOffset: CGFloat?
    @State private var resumeAutoScrollTask: Task<Void, Never>?
    @State private var programmaticScrollResetTask: Task<Void, Never>?

    private var currentIndex: Int {
        activeLyricIndex ?? 0
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(displayItems) { item in
                        switch item {
                        case .lyric(let line):
                            let isCurrent = item.id == activeItemID

                            lyricRow(line, isCurrent: isCurrent)
                                .id(item.id)
                                .onTapGesture {
                                    isAutoScrollPaused = false
                                    resumeAutoScrollTask?.cancel()
                                    seek(max(0, line.time - lyricSeekLeadTime))
                                    scroll(to: item.id, proxy: proxy, animated: true)
                                }
                        case .instrumental(_, let progress):
                            InstrumentalDotsLyricRow(
                                progress: progress,
                                fontSize: instrumentalFontSize,
                                reduceMotion: reduceMotion
                            )
                            .id(item.id)
                            .allowsHitTesting(false)
                        case .outro:
                            OutroInstrumentalLyricRow(fontSize: instrumentalFontSize)
                                .id(item.id)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .padding(.vertical, 70)
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: LyricScrollOffsetKey.self,
                                value: geometry.frame(in: .named(lyricScrollSpaceName)).minY
                            )
                    }
                }
            }
            .coordinateSpace(name: lyricScrollSpaceName)
            .frame(height: 184, alignment: .center)
            .clipped()
            .mask {
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in pauseAutoScroll(proxy) }
            )
            .onPreferenceChange(LyricScrollOffsetKey.self) { offset in
                handleScrollOffsetChange(offset, proxy: proxy)
            }
            .onAppear {
                scrollToCurrent(proxy, animated: false)
            }
            .onChange(of: activeItemID) { _, _ in
                guard !isAutoScrollPaused else { return }
                scrollToCurrent(proxy, animated: true)
            }
        }
        .animation(AppMotion.lyricScroll(reduceMotion: reduceMotion), value: activeItemID)
        .onDisappear {
            resumeAutoScrollTask?.cancel()
            programmaticScrollResetTask?.cancel()
        }
    }

    private func lyricRow(_ item: DisplayLyricLine, isCurrent: Bool) -> some View {
        SyncedLyricRow(
            line: item,
            isCurrent: isCurrent,
            currentFontSize: currentLineFontSize,
            supportingFontSize: supportingLineFontSize,
            backingFontSize: backingFontSize(isCurrent: isCurrent)
        )
    }

    private var lyricLeadTime: TimeInterval {
        0.18
    }

    private var lyricSeekLeadTime: TimeInterval {
        0.15
    }

    private var lyricScrollSpaceName: String {
        "SyncedLyricsScrollSpace"
    }

    private var currentLineFontSize: CGFloat {
        min(max(fontSize + 5, 23), 31)
    }

    private var supportingLineFontSize: CGFloat {
        min(max(fontSize - 2, 16), 20)
    }

    private var instrumentalFontSize: CGFloat {
        currentLineFontSize * 0.9
    }

    private func backingFontSize(isCurrent: Bool) -> CGFloat {
        max((isCurrent ? currentLineFontSize : supportingLineFontSize) * 0.52, 10.5)
    }

    private var displayLyricLines: [DisplayLyricLine] {
        lines.map { DisplayLyricLine(syncedLine: $0) }
    }

    private var activeLyricIndex: Int? {
        let adjustedElapsed = elapsed + lyricLeadTime
        return lines.lastIndex(where: { $0.time <= adjustedElapsed })
    }

    private var placeholder: InstrumentalPlaceholder? {
        guard !lines.isEmpty else { return nil }

        if activeLyricIndex == nil,
           let first = lines.first,
           first.time >= instrumentalGapThreshold,
           elapsed < first.time - instrumentalHoldDuration {
            return InstrumentalPlaceholder(
                id: "instrumental-intro-\(first.id.uuidString)",
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
                return InstrumentalPlaceholder(
                    id: "instrumental-\(current.id.uuidString)-\(next.id.uuidString)",
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
                return InstrumentalPlaceholder(
                    id: "instrumental-outro-\(last.id.uuidString)",
                    kind: .outro,
                    start: start,
                    fillEnd: duration,
                    end: duration
                )
            }
        }

        return nil
    }

    private var displayItems: [SyncedLyricDisplayItem] {
        var items = displayLyricLines.map { SyncedLyricDisplayItem.lyric($0) }
        guard let placeholder else { return items }

        switch placeholder.kind {
        case .dots:
            let item = SyncedLyricDisplayItem.instrumental(id: placeholder.id, progress: placeholder.progress(at: elapsed))
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

    private var activeItemID: String? {
        if let placeholder {
            return placeholder.id
        }

        guard displayLyricLines.indices.contains(currentIndex) else { return nil }
        return displayLyricLines[currentIndex].id.uuidString
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let activeItemID else { return }
        scroll(to: activeItemID, proxy: proxy, animated: animated)
    }

    private func scroll(to id: String, proxy: ScrollViewProxy, animated: Bool) {
        markProgrammaticScroll()
        if animated {
            withAnimation(AppMotion.lyricScroll(reduceMotion: reduceMotion)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func pauseAutoScroll(_ proxy: ScrollViewProxy) {
        guard !isProgrammaticScroll else { return }
        isAutoScrollPaused = true
        resumeAutoScrollTask?.cancel()
        resumeAutoScrollTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isAutoScrollPaused = false
                scrollToCurrent(proxy, animated: true)
            }
        }
    }

    private func handleScrollOffsetChange(_ offset: CGFloat, proxy: ScrollViewProxy) {
        defer { lastScrollOffset = offset }
        guard let lastScrollOffset else { return }
        guard abs(offset - lastScrollOffset) > 1.25 else { return }
        pauseAutoScroll(proxy)
    }

    private func markProgrammaticScroll() {
        isProgrammaticScroll = true
        programmaticScrollResetTask?.cancel()
        programmaticScrollResetTask = Task {
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isProgrammaticScroll = false
            }
        }
    }

    private var instrumentalGapThreshold: TimeInterval {
        10.0
    }

    private var outroRemainingThreshold: TimeInterval {
        8.0
    }

    private var outroVisibleDuration: TimeInterval {
        3.2
    }

    private var instrumentalHoldDuration: TimeInterval {
        0.5
    }
}

private enum SyncedLyricDisplayItem: Identifiable {
    case lyric(DisplayLyricLine)
    case instrumental(id: String, progress: Double)
    case outro(id: String)

    var id: String {
        switch self {
        case .lyric(let line):
            line.id.uuidString
        case .instrumental(let id, _), .outro(let id):
            id
        }
    }
}

private struct InstrumentalPlaceholder {
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

private struct SyncedLyricRow: View {
    var line: DisplayLyricLine
    var isCurrent: Bool
    var currentFontSize: CGFloat
    var supportingFontSize: CGFloat
    var backingFontSize: CGFloat

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: isCurrent ? 4 : 3) {
                Text(line.mainText)
                    .font(.system(size: isCurrent ? currentFontSize : supportingFontSize, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .lineLimit(isCurrent ? 3 : 2)
                    .minimumScaleFactor(isCurrent ? 0.65 : 0.74)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsTightening(true)

                if isCurrent, let backingText = line.backingText {
                    Text(backingText)
                        .font(.system(size: backingFontSize, weight: .regular, design: .default))
                        .foregroundStyle(.secondary.opacity(0.68))
                        .lineLimit(2)
                        .minimumScaleFactor(0.70)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsTightening(true)
                }
            }
            .multilineTextAlignment(.leading)
            .layoutPriority(1)

            Spacer(minLength: 6)

            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary.opacity(isCurrent || isHovered ? 0.62 : 0))
                .scaleEffect(AppMotion.hoverScale(isHovered, amount: 1.025))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCurrent ? 8 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(isCurrent ? 0.045 : (isHovered ? 0.028 : 0)))
        }
        .contentShape(Rectangle())
        .opacity(isCurrent ? 1 : 0.58)
        .scaleEffect(isCurrent ? 1.0 : 0.965, anchor: .leading)
        .blur(radius: isCurrent ? 0 : 0.06)
        .contentTransition(.opacity)
        .onHover { isHovered = $0 }
        .help("Seek to \(TrackTimeRow.format(line.time))")
        .animation(AppMotion.control(), value: isHovered)
        .animation(AppMotion.panel(), value: isCurrent)
    }
}

private struct InstrumentalDotsLyricRow: View {
    var progress: Double
    var fontSize: CGFloat
    var reduceMotion: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: max(8, fontSize * 0.34)) {
                ForEach(0..<3, id: \.self) { index in
                    let fill = reduceMotion ? 0.72 : dotFill(for: index)
                    InstrumentalDot(
                        fill: fill,
                        size: max(13, fontSize * 0.54),
                        lift: reduceMotion ? 0 : dotLift(for: fill)
                    )
                }
            }
            .padding(.vertical, 8)
            .opacity(0.98)
            .transition(AppMotion.subtleInsertion)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(AppMotion.content(reduceMotion: reduceMotion), value: progress)
    }

    private func dotFill(for index: Int) -> Double {
        min(max(progress * 3 - Double(index), 0), 1)
    }

    private func dotLift(for fill: Double) -> CGFloat {
        -5 * min(max(fill, 0), 1)
    }
}

private struct InstrumentalDot: View {
    var fill: Double
    var size: CGFloat
    var lift: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Circle()
                .fill(.white.opacity(0.24))

            GeometryReader { proxy in
                Circle()
                    .fill(.white)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(x: -proxy.size.width * (1 - fill))
            }
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .offset(y: lift)
        .scaleEffect(1 + 0.025 * fill)
        .shadow(color: .white.opacity(fill > 0 ? 0.16 : 0), radius: 4 + 3 * fill, y: 2 * fill)
        .animation(AppMotion.control(), value: lift)
        .animation(AppMotion.content(), value: fill)
    }
}

private struct OutroInstrumentalLyricRow: View {
    var fontSize: CGFloat

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Image(systemName: "music.note")
                .font(.system(size: max(16, fontSize * 0.92), weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary.opacity(0.74))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.primary.opacity(0.04))
                }
                .transition(.opacity)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LyricScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct UnavailableLyricsView: View {
    var message: String
    var retry: () -> Void
    var importLRC: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button(action: retry) {
                Text("Try again?")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(.secondary.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.secondary.opacity(0.18), lineWidth: 0.7)
            }
            .help("Retry fetching lyrics")

            Button(action: importLRC) {
                Label("Import Lyrics", systemImage: "doc.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(.secondary.opacity(0.08), in: Capsule())
            .help("Use a local timed lyrics file for this song")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 184)
    }
}
