import SwiftUI
import Combine
import AppKit

struct ContentView: View {
    @ObservedObject var store: NowPlayingStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var presentation = MiniPlayerPresentationController()
    @StateObject private var lockScreenMonitor = LockScreenMonitor()
    @StateObject private var lockscreenSurface = LockScreenSurfaceController()
    @StateObject private var volumeMonitor = SystemVolumeMonitor()
    @StateObject private var brightnessMonitor = DisplayBrightnessMonitor()
    @StateObject private var batteryMonitor = BatteryWarningMonitor()
    @StateObject private var focusModeMonitor = FocusModeMonitor.shared
    @StateObject private var audioOutputMonitor = AudioOutputDeviceMonitor()
    @State private var didCompleteOnboarding = false
    @State private var compactSurfaceFrame: NSRect = .zero
    @State private var lastLockScreenMetadataRefresh = Date.distantPast
    @State private var lastAmbientMetadataRefresh = Date.distantPast
    @State private var connectedOutputToast: AudioOutputDevice?
    @State private var connectedOutputToastTask: Task<Void, Never>?
    @State private var showingAudioOutputPanel = false
    @State private var measuredMiniPlayerSize: CGSize?
    @Namespace private var namespace

    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var playerSpring: Animation {
        AppMotion.primary(reduceMotion: reduceMotion)
    }

    private var panelMotion: Animation {
        AppMotion.panel(reduceMotion: reduceMotion)
    }

    private var contentMotion: Animation {
        AppMotion.content(reduceMotion: reduceMotion)
    }

    private var isLockScreenActive: Bool {
        didCompleteOnboarding && lockScreenMonitor.isLockSurfaceActive
    }

    var body: some View {
        let targetWindowSize = windowSize

        Group {
            if didCompleteOnboarding {
                if presentation.showingAmbient {
                    AmbientModeView(
                        store: store,
                        lyricsVisible: presentation.showingAmbientLyrics,
                        namespace: namespace,
                        close: {
                            animate {
                                presentation.hideAmbient()
                            }
                        },
                        toggleLyrics: {
                            animate {
                                presentation.toggleAmbientLyrics()
                            }
                        }
                    )
                } else {
                    compactPlayer
                }
            } else {
                OnboardingView(store: store) {
                    didCompleteOnboarding = true
                    presentation.applyPreferredMode(store.settings.preferredMode)
                    lockScreenMonitor.refreshLockState(reason: "onboardingComplete")
                    syncLockScreenSurface()
                }
            }
        }
        .frame(width: targetWindowSize.width, height: targetWindowSize.height)
        .clipped()
        .overlay(alignment: .topLeading) {
            if presentation.showingAmbient {
                VStack(spacing: 12) {
                    AmbientControlButton(systemName: "xmark", label: "Close Ambient Mode") {
                        animate {
                            presentation.hideAmbient()
                        }
                    }

                    AmbientControlButton(
                        systemName: presentation.showingAmbientLyrics ? "quote.bubble.fill" : "quote.bubble",
                        label: presentation.showingAmbientLyrics ? "Hide Lyrics" : "Show Lyrics"
                    ) {
                        animate {
                            presentation.toggleAmbientLyrics()
                        }
                    }
                }
                .padding(.top, 48)
                .padding(.leading, 48)
                .transition(AppMotion.subtleInsertion)
                .zIndex(10_000)
            }
        }
        .background(
            WindowConfigurator(
                alwaysOnTop: store.settings.alwaysOnTop,
                hiddenFromCapture: store.settings.hideFromScreenCapture,
                size: targetWindowSize,
                isOnboarding: !didCompleteOnboarding,
                isAmbient: presentation.showingAmbient,
                hiddenForLockscreen: isLockScreenActive
            ) { frame in
                compactSurfaceFrame = frame
            }
        )
        .environmentObject(store)
        .task {
            volumeMonitor.startMonitoring()
            brightnessMonitor.startMonitoring()
            batteryMonitor.startMonitoring(thresholdPercent: store.settings.lowBatteryWarningPercent)
            focusModeMonitor.startMonitoring()
            audioOutputMonitor.startMonitoring()
            await store.refreshMetadata()
            lockScreenMonitor.refreshLockState(reason: "launch")
            syncLockScreenSurface()
        }
        .onDisappear {
            volumeMonitor.stopMonitoring()
            brightnessMonitor.stopMonitoring()
            batteryMonitor.stopMonitoring()
            focusModeMonitor.stopMonitoring()
            audioOutputMonitor.stopMonitoring()
            connectedOutputToastTask?.cancel()
        }
        .onReceive(tickTimer) { _ in
            if presentation.showingAmbient {
                refreshAmbientMetadataIfNeeded()
            }

            if isLockScreenActive {
                refreshLockScreenMetadataIfNeeded()
                lockscreenSurface.refresh(
                    context: lockScreenMonitor.context,
                    store: store,
                    reduceMotion: reduceMotion
                )
            }
        }
        .onChange(of: lockScreenMonitor.context) { _, _ in
            if lockScreenMonitor.isLockSurfaceActive {
                refreshLockScreenMetadata(force: true)
            }
            syncLockScreenSurface()
        }
        .onChange(of: didCompleteOnboarding) { _, completed in
            guard completed else { return }
            syncLockScreenSurface()
        }
        .onChange(of: presentation.showingAmbient) { _, isShowing in
            guard isShowing else { return }
            refreshAmbientMetadata(force: true)
        }
        .onChange(of: store.currentTrack) { _, _ in
            guard isLockScreenActive else { return }
            lockscreenSurface.refresh(
                context: lockScreenMonitor.context,
                store: store,
                reduceMotion: reduceMotion
            )
        }
        .onChange(of: store.settings.showLyricsButton) { _, enabled in
            guard !enabled else { return }
            presentation.hideRegularLyrics()
        }
        .onChange(of: store.settings.hideFromScreenCapture) { _, _ in
            guard isLockScreenActive else { return }
            lockscreenSurface.refresh(
                context: lockScreenMonitor.context,
                store: store,
                reduceMotion: reduceMotion
            )
        }
        .onChange(of: store.settings.lowBatteryWarningPercent) { _, percent in
            batteryMonitor.updateThreshold(percent)
        }
    }

    private var compactPlayer: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    playerStack
                }
            } else {
                playerStack
            }
        }
        .padding(18)
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(shouldHidePlayerForStoppedPlayback ? 0 : 1)
        .scaleEffect(shouldHidePlayerForStoppedPlayback ? 0.98 : 1, anchor: .bottom)
        .allowsHitTesting(!shouldHidePlayerForStoppedPlayback)
        .animation(playerSpring, value: shouldHidePlayerForStoppedPlayback)
    }

    private var shouldHidePlayerForStoppedPlayback: Bool {
        store.settings.hideWhenPlaybackStops && !store.isPlaybackAvailable
    }

    private var playerStack: some View {
        VStack(spacing: 9) {
            if let connectedOutputToast {
                AudioOutputConnectedToast(
                    deviceName: connectedOutputToast.name,
                    iconName: connectedOutputToast.kind.iconName,
                    tint: store.currentTrack?.dominantColor ?? .secondary
                )
                .transition(companionPopupTransition)
            } else if batteryMonitor.isVisible {
                LowBatteryCompanionPopup(
                    percent: batteryMonitor.percent,
                    thresholdPercent: store.settings.lowBatteryWarningPercent,
                    isSandboxBlocked: batteryMonitor.isSandboxBlocked,
                    tint: store.currentTrack?.dominantColor ?? .secondary
                )
                .transition(companionPopupTransition)
            } else if focusModeMonitor.isVisible {
                FocusCompanionPopup(
                    iconName: focusModeMonitor.activeFocusIcon ?? "moon.fill",
                    title: focusPopupTitle,
                    isFocused: focusModeMonitor.isFocused,
                    tint: store.currentTrack?.dominantColor ?? .secondary,
                    accessibilityMessage: focusPopupMessage
                )
                .transition(companionPopupTransition)
            } else if brightnessMonitor.isVisible {
                SystemBrightnessBar(
                    level: brightnessMonitor.level,
                    direction: brightnessMonitor.direction,
                    isSandboxBlocked: brightnessMonitor.isSandboxBlocked,
                    tint: store.currentTrack?.dominantColor ?? .secondary
                )
                .transition(companionPopupTransition)
            } else if volumeMonitor.isVisible {
                SystemVolumeBar(
                    level: volumeMonitor.level,
                    isMuted: volumeMonitor.isMuted,
                    direction: volumeMonitor.direction,
                    tint: store.currentTrack?.dominantColor ?? .secondary
                )
                .transition(companionPopupTransition)
            }

            playerRow
        }
        .fixedSize(horizontal: true, vertical: true)
        .animation(playerSpring, value: volumeMonitor.isVisible)
        .animation(playerSpring, value: brightnessMonitor.isVisible)
        .animation(playerSpring, value: batteryMonitor.isVisible)
        .animation(playerSpring, value: focusModeMonitor.isVisible)
        .animation(playerSpring, value: connectedOutputToast)
        .animation(AppMotion.progress(reduceMotion: reduceMotion), value: volumeMonitor.level)
        .animation(AppMotion.progress(reduceMotion: reduceMotion), value: brightnessMonitor.level)
        .onChange(of: audioOutputMonitor.connectedDevice) { _, device in
            guard let device else { return }
            showConnectedOutputToast(for: device)
        }
        .accessibilityElement(children: .contain)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: MiniPlayerSizePreferenceKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(MiniPlayerSizePreferenceKey.self) { size in
            guard size.width > 1, size.height > 1 else { return }
            measuredMiniPlayerSize = CGSize(
                width: ceil(size.width),
                height: ceil(size.height)
            )
        }
    }

    private var companionPopupTransition: AnyTransition {
        AppMotion.toastTransition
    }

    private var playerRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if store.settings.queueButtonEnabled {
                if showingAudioOutputPanel {
                    AudioOutputPanel(
                        monitor: audioOutputMonitor,
                        tint: store.currentTrack?.dominantColor ?? .secondary,
                        close: {
                            animate {
                                showingAudioOutputPanel = false
                            }
                        },
                        selectionAction: connectAudioOutput
                    )
                    .matchedGeometryEffect(id: "audioOutput", in: namespace)
                } else {
                    AudioOutputPickerButton(
                        monitor: audioOutputMonitor,
                        tint: store.currentTrack?.dominantColor ?? .secondary
                    ) {
                        animate {
                            presentation.hideRegularLyrics()
                            audioOutputMonitor.loadDevices()
                            showingAudioOutputPanel = true
                        }
                    }
                    .offset(y: sideButtonVerticalOffset)
                    .matchedGeometryEffect(id: "audioOutput", in: namespace)
                    .animation(playerSpring, value: sideButtonVerticalOffset)
                }
            }

            MiniPlayerPill(
                store: store,
                mode: presentation.miniPlayerMode,
                namespace: namespace,
                artworkAction: store.settings.ambientModeEnabled ? {
                    animate {
                        presentation.showAmbient()
                    }
                } : nil
            )
            .onTapGesture(count: 2) {
                animate {
                    presentation.toggleCompactExpanded()
                }
            }
            .contextMenu {
                Button("Compact") { presentation.selectCompact() }
                Button("Expanded") { presentation.selectExpanded() }
                Button("Lyrics Focus") {
                    presentation.showLyricsFocus()
                }
                Divider()
                Button("Settings") {
                    openWindow(id: "settings")
                }
                Button("Refresh Song Info") {
                    Task { await store.refreshMetadata() }
                }
            }

            if store.settings.showLyricsButton {
                if presentation.showingLyrics {
                    LyricsPanel(store: store) {
                        animate {
                            presentation.hideRegularLyrics()
                        }
                    }
                    .matchedGeometryEffect(id: "lyrics", in: namespace)
                } else {
                    SideGlassButton(systemName: "quote.bubble", label: "Lyrics", tint: store.currentTrack?.secondaryColor ?? .secondary) {
                        animate {
                            showingAudioOutputPanel = false
                            presentation.showRegularLyrics()
                        }
                    }
                    .offset(y: sideButtonVerticalOffset)
                    .matchedGeometryEffect(id: "lyrics", in: namespace)
                }
            }
        }
        .animation(playerSpring, value: presentation.showingLyrics)
        .animation(playerSpring, value: showingAudioOutputPanel)
        .animation(playerSpring, value: presentation.miniPlayerMode)
        .animation(playerSpring, value: store.settings.queueButtonEnabled)
        .animation(playerSpring, value: store.settings.showLyricsButton)
    }

    private var sideButtonVerticalOffset: CGFloat {
        presentation.miniPlayerMode == .compact ? -16 : -41
    }

    private var focusPopupTitle: String {
        switch focusModeMonitor.isFocused {
        case true:
            return focusModeMonitor.activeFocusName.map { "\($0) on" } ?? "Focus on"
        case false:
            return "Focus off"
        case nil:
            return "Focus updated"
        }
    }

    private var focusPopupMessage: String {
        switch focusModeMonitor.isFocused {
        case true:
            return "Notifications are quieted."
        case false:
            return "Notifications are back."
        case nil:
            return "MiniMusix noticed the change."
        }
    }

    private var windowSize: CGSize {
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
        guard didCompleteOnboarding, !presentation.showingAmbient else {
            return presentation.windowSize(didCompleteOnboarding: didCompleteOnboarding, screenSize: screenSize)
        }

        guard let measuredMiniPlayerSize else {
            return presentation.windowSize(didCompleteOnboarding: didCompleteOnboarding, screenSize: screenSize)
        }

        return CGSize(
            width: measuredMiniPlayerSize.width + 36,
            height: measuredMiniPlayerSize.height + 36
        )
    }

    private func syncLockScreenSurface() {
        let context: SecureDisplayContext = isLockScreenActive ? lockScreenMonitor.context : .inactive
        lockscreenSurface.sync(
            context: context,
            store: store,
            reduceMotion: reduceMotion
        )
    }

    private func refreshLockScreenMetadataIfNeeded() {
        let interval = max(1, store.settings.metadataRefreshRate)
        guard Date().timeIntervalSince(lastLockScreenMetadataRefresh) >= interval else { return }
        refreshLockScreenMetadata(force: false)
    }

    private func refreshLockScreenMetadata(force: Bool) {
        let interval = max(1, store.settings.metadataRefreshRate)
        guard force || Date().timeIntervalSince(lastLockScreenMetadataRefresh) >= interval else { return }
        lastLockScreenMetadataRefresh = Date()

        Task {
            await store.refreshMetadata()
            await MainActor.run {
                guard isLockScreenActive else { return }
                lockscreenSurface.refresh(
                    context: lockScreenMonitor.context,
                    store: store,
                    reduceMotion: reduceMotion
                )
            }
        }
    }

    private func refreshAmbientMetadataIfNeeded() {
        let interval = max(1, store.settings.metadataRefreshRate)
        guard Date().timeIntervalSince(lastAmbientMetadataRefresh) >= interval else { return }
        refreshAmbientMetadata(force: false)
    }

    private func refreshAmbientMetadata(force: Bool) {
        let interval = max(1, store.settings.metadataRefreshRate)
        guard force || Date().timeIntervalSince(lastAmbientMetadataRefresh) >= interval else { return }
        lastAmbientMetadataRefresh = Date()

        Task {
            await store.refreshMetadata()
        }
    }

    private func animate(_ changes: @escaping () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(playerSpring, changes)
        }
    }

    private func connectAudioOutput(_ device: AudioOutputDevice) {
        guard audioOutputMonitor.select(device) != nil else { return }
        animate {
            showingAudioOutputPanel = false
        }
    }

    private func showConnectedOutputToast(for device: AudioOutputDevice) {
        connectedOutputToastTask?.cancel()
        animate {
            connectedOutputToast = device
        }
        connectedOutputToastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                connectedOutputToast = nil
                audioOutputMonitor.clearConnectedDevice()
            }
        }
    }
}

#Preview {
    ContentView(store: NowPlayingStore())
}

private enum CompanionPopupSize {
    case compact
    case large

    var iconWidth: CGFloat {
        switch self {
        case .compact: 20
        case .large: 24
        }
    }

    var contentWidth: CGFloat {
        switch self {
        case .compact: 154
        case .large: 220
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 13
        case .large: 14
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: 9
        case .large: 12
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: 19
        case .large: 21
        }
    }
}

private struct CompanionPopupChrome<Content: View>: View {
    var tint: Color
    var size: CompanionPopupSize = .compact
    var content: Content

    init(tint: Color, size: CompanionPopupSize = .compact, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.size = size
        self.content = content()
    }

    var body: some View {
        HStack(spacing: size == .compact ? 10 : 12) {
            content
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .panelSurface(cornerRadius: size.cornerRadius, tint: tint)
    }
}

private struct SystemMeterPopup<DirectionGlyph: View>: View {
    var iconName: String
    var level: Double
    var tint: Color
    var fill: AnyShapeStyle
    var contentWidth: CGFloat
    var valueText: String
    var accessibilityLabel: String
    var directionGlyph: DirectionGlyph

    init(
        iconName: String,
        level: Double,
        tint: Color,
        fill: AnyShapeStyle,
        contentWidth: CGFloat = CompanionPopupSize.compact.contentWidth,
        valueText: String? = nil,
        accessibilityLabel: String,
        @ViewBuilder directionGlyph: () -> DirectionGlyph
    ) {
        self.iconName = iconName
        self.level = min(max(level, 0), 1)
        self.tint = tint
        self.fill = fill
        self.contentWidth = contentWidth
        self.valueText = valueText ?? "\(Int((min(max(level, 0), 1) * 100).rounded()))"
        self.accessibilityLabel = accessibilityLabel
        self.directionGlyph = directionGlyph()
    }

    var body: some View {
        CompanionPopupChrome(tint: tint) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: CompanionPopupSize.compact.iconWidth)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.16))

                    Capsule()
                        .fill(fill)
                        .frame(width: max(7, proxy.size.width * level))
                }
            }
            .frame(width: contentWidth, height: 7)

            Text(valueText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 26, alignment: .trailing)
        }
        .overlay(alignment: .trailing) {
            directionGlyph
                .padding(.trailing, 9)
                .offset(x: 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct StatusMeterPopup<DirectionGlyph: View>: View {
    var iconName: String
    var title: String
    var level: Double
    var valueText: String
    var tint: Color
    var fill: AnyShapeStyle
    var iconTint: Color? = nil
    var accessibilityLabel: String
    var directionGlyph: DirectionGlyph

    init(
        iconName: String,
        title: String,
        level: Double,
        valueText: String,
        tint: Color,
        fill: AnyShapeStyle,
        iconTint: Color? = nil,
        accessibilityLabel: String,
        @ViewBuilder directionGlyph: () -> DirectionGlyph
    ) {
        self.iconName = iconName
        self.title = title
        self.level = min(max(level, 0), 1)
        self.valueText = valueText
        self.tint = tint
        self.fill = fill
        self.iconTint = iconTint
        self.accessibilityLabel = accessibilityLabel
        self.directionGlyph = directionGlyph()
    }

    var body: some View {
        CompanionPopupChrome(tint: tint) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconTint ?? .primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: CompanionPopupSize.compact.iconWidth)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: contentWidth, alignment: .leading)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.16))

                        Capsule()
                            .fill(fill)
                            .frame(width: max(7, proxy.size.width * level))
                    }
                }
                .frame(width: contentWidth, height: 7)
            }

            Text(valueText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 26, alignment: .trailing)
        }
        .overlay(alignment: .trailing) {
            directionGlyph
                .padding(.trailing, 9)
                .offset(x: 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var contentWidth: CGFloat {
        min(max(CGFloat(title.count) * 7.2 + 32, 154), 260)
    }
}

private struct SystemVolumeBar: View {
    var level: Double
    var isMuted: Bool
    var direction: SystemVolumeDirection
    var tint: Color

    private var displayedLevel: Double {
        isMuted ? 0 : min(max(level, 0), 1)
    }

    private var iconName: String {
        if isMuted || displayedLevel <= 0.001 {
            return "speaker.slash.fill"
        }

        if displayedLevel < 0.34 {
            return "speaker.fill"
        }

        if displayedLevel < 0.68 {
            return "speaker.wave.1.fill"
        }

        return "speaker.wave.2.fill"
    }

    var body: some View {
        SystemMeterPopup(
            iconName: iconName,
            level: displayedLevel,
            tint: tint,
            fill: AnyShapeStyle(
                LinearGradient(
                    colors: [tint.opacity(0.86), tint.opacity(0.58)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            ),
            accessibilityLabel: isMuted ? "System volume muted" : "System volume \(Int((displayedLevel * 100).rounded())) percent"
        ) {
            directionGlyph
        }
    }

    @ViewBuilder
    private var directionGlyph: some View {
        switch direction {
        case .up:
            DirectionChevron(systemName: "chevron.up")
        case .down:
            DirectionChevron(systemName: "chevron.down")
        case .unchanged:
            EmptyView()
        }
    }
}

private struct SystemBrightnessBar: View {
    var level: Double
    var direction: DisplayBrightnessDirection
    var isSandboxBlocked: Bool
    var tint: Color

    private var displayedLevel: Double {
        min(max(level, 0), 1)
    }

    var body: some View {
        if isSandboxBlocked {
            CompanionMessagePopup(
                iconName: "lock.shield.fill",
                title: "Brightness not available",
                message: "This build cannot read display brightness.",
                tint: tint
            )
        } else {
            SystemMeterPopup(
                iconName: "sun.max.fill",
                level: displayedLevel,
                tint: tint,
                fill: AnyShapeStyle(.white.opacity(0.92)),
                accessibilityLabel: "Display brightness \(Int((displayedLevel * 100).rounded())) percent"
            ) {
                directionGlyph
            }
        }
    }

    @ViewBuilder
    private var directionGlyph: some View {
        switch direction {
        case .up:
            DirectionChevron(systemName: "chevron.up")
        case .down:
            DirectionChevron(systemName: "chevron.down")
        case .unchanged:
            EmptyView()
        }
    }
}

private struct DirectionChevron: View {
    var systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
    }
}

private struct FocusCompanionPopup: View {
    var iconName: String
    var title: String
    var isFocused: Bool?
    var tint: Color
    var accessibilityMessage: String

    private var level: Double {
        isFocused == false ? 0 : 1
    }

    private var valueText: String {
        switch isFocused {
        case true: "On"
        case false: "Off"
        case nil: "New"
        }
    }

    var body: some View {
        StatusMeterPopup(
            iconName: iconName,
            title: title,
            level: level,
            valueText: valueText,
            tint: tint,
            fill: AnyShapeStyle(
                LinearGradient(
                    colors: [tint.opacity(0.86), tint.opacity(0.58)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            ),
            accessibilityLabel: "\(title). \(accessibilityMessage)"
        ) {
            EmptyView()
        }
    }
}

private struct AudioOutputConnectedToast: View {
    var deviceName: String
    var iconName: String
    var tint: Color

    var body: some View {
        CompanionPopupChrome(tint: tint) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: CompanionPopupSize.compact.iconWidth)

            Text("\(deviceName) connected")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 190, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(deviceName) connected")
    }
}

private struct LowBatteryCompanionPopup: View {
    var percent: Int
    var thresholdPercent: Int
    var isSandboxBlocked: Bool
    var tint: Color

    private var title: String {
        isSandboxBlocked ? "Battery unavailable" : "\(percent)% battery remaining"
    }

    private var message: String {
        if isSandboxBlocked {
            return "This build cannot read battery level."
        }

        return "\(percent)% remaining. Alert set at \(thresholdPercent)%."
    }

    var body: some View {
        StatusMeterPopup(
            iconName: isSandboxBlocked ? "lock.shield.fill" : batteryIconName,
            title: title,
            level: isSandboxBlocked ? 0 : Double(percent) / 100,
            valueText: isSandboxBlocked ? "--" : "\(percent)",
            tint: tint,
            fill: AnyShapeStyle(.red.opacity(0.88)),
            iconTint: isSandboxBlocked ? nil : .red.opacity(0.90),
            accessibilityLabel: message
        ) {
            EmptyView()
        }
        .accessibilityLabel(isSandboxBlocked ? "Battery monitoring unavailable" : "Low battery, \(percent) percent remaining")
    }

    private var batteryIconName: String {
        percent <= 10 ? "battery.0percent" : "battery.25percent"
    }
}

private struct CompanionMessagePopup: View {
    var iconName: String
    var title: String
    var message: String
    var tint: Color
    var size: CompanionPopupSize = .compact
    var iconTint: Color? = nil

    var body: some View {
        CompanionPopupChrome(tint: tint, size: size) {
            Image(systemName: iconName)
                .font(.system(size: size == .compact ? 15 : 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconTint ?? .primary)
                .frame(width: size.iconWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(size == .compact ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: size == .compact ? 190 : size.contentWidth, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

private struct MiniPlayerSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        guard next.width > 0, next.height > 0 else { return }
        value = next
    }
}
