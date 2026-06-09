import SwiftUI
import Combine
import AppKit
import ServiceManagement

// MARK: - SettingsManager
// Centralized, persistent settings management.
// All settings save/load via UserDefaults with Codable models.
// Published changes propagate to all observers instantly.

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private enum Keys {
        static let source                = "mm.source"
        static let launchAtLogin         = "mm.launchAtLogin"
        static let alwaysOnTop           = "mm.alwaysOnTop"
        static let hideFromScreenCapture = "mm.hideFromScreenCapture"
        static let hideWhenPlaybackStops = "mm.hideWhenPlaybackStops"
        static let preferredMode         = "mm.preferredMode"
        static let albumTintStrength     = "mm.albumTintStrength"
        static let artworkGlow           = "mm.artworkGlow"
        static let cornerRadius          = "mm.cornerRadius"
        static let positionBehavior      = "mm.positionBehavior"
        static let enableLRCLIB          = "mm.enableLRCLIB"
        static let syncedLyrics          = "mm.syncedLyrics"
        static let plainLyrics           = "mm.plainLyrics"
        static let lyricFontSize         = "mm.lyricFontSize"
        static let missingLyricsMessage  = "mm.missingLyricsMessage"
        static let queueButtonEnabled    = "mm.queueButtonEnabled"
        static let showLyricsButton      = "mm.showLyricsButton"
        static let ambientModeEnabled    = "mm.ambientModeEnabled"
        static let lowBatteryWarningPercent = "mm.lowBatteryWarningPercent"
        static let progressBarGradient   = "mm.progressBarGradient"
        static let glassIntensity        = "mm.glassIntensity"
        static let glassStyle            = "mm.glassStyle"
        static let systemAccent          = "mm.systemAccent"
        static let albumColors           = "mm.albumColors"
        static let reduceMotionSupport   = "mm.reduceMotionSupport"
        static let metadataRefreshRate   = "mm.metadataRefreshRate"
        static let commandRouting        = "mm.commandRouting"
    }

    private let defaults = UserDefaults.standard

    // ── Source

    @Published var source: PlaybackSource {
        didSet { save(source.rawValue, key: Keys.source) }
    }

    // ── App Behavior

    @Published var launchAtLogin: Bool {
        didSet {
            save(launchAtLogin, key: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    @Published var alwaysOnTop: Bool {
        didSet {
            save(alwaysOnTop, key: Keys.alwaysOnTop)
            applyAlwaysOnTop()
        }
    }

    @Published var hideFromScreenCapture: Bool {
        didSet {
            save(hideFromScreenCapture, key: Keys.hideFromScreenCapture)
            applyScreenCaptureHiding()
        }
    }

    @Published var hideWhenPlaybackStops: Bool {
        didSet { save(hideWhenPlaybackStops, key: Keys.hideWhenPlaybackStops) }
    }

    // ── MiniPlayer

    @Published var preferredMode: MiniPlayerMode {
        didSet { save(preferredMode.rawValue, key: Keys.preferredMode) }
    }

    @Published var albumTintStrength: Double {
        didSet { save(albumTintStrength, key: Keys.albumTintStrength) }
    }

    @Published var artworkGlow: Bool {
        didSet { save(artworkGlow, key: Keys.artworkGlow) }
    }

    @Published var cornerRadius: Double {
        didSet { save(cornerRadius, key: Keys.cornerRadius) }
    }

    @Published var positionBehavior: String {
        didSet { save(positionBehavior, key: Keys.positionBehavior) }
    }

    // ── Lyrics

    @Published var enableLRCLIB: Bool {
        didSet { save(enableLRCLIB, key: Keys.enableLRCLIB) }
    }

    @Published var syncedLyrics: Bool {
        didSet { save(syncedLyrics, key: Keys.syncedLyrics) }
    }

    @Published var plainLyrics: Bool {
        didSet { save(plainLyrics, key: Keys.plainLyrics) }
    }

    @Published var lyricFontSize: Double {
        didSet { save(lyricFontSize, key: Keys.lyricFontSize) }
    }

    @Published var missingLyricsMessage: String {
        didSet { save(missingLyricsMessage, key: Keys.missingLyricsMessage) }
    }

    // ── Controls

    @Published var queueButtonEnabled: Bool {
        didSet { save(queueButtonEnabled, key: Keys.queueButtonEnabled) }
    }

    @Published var showLyricsButton: Bool {
        didSet { save(showLyricsButton, key: Keys.showLyricsButton) }
    }

    @Published var ambientModeEnabled: Bool {
        didSet { save(ambientModeEnabled, key: Keys.ambientModeEnabled) }
    }

    @Published var lowBatteryWarningPercent: Double {
        didSet { save(lowBatteryWarningPercent, key: Keys.lowBatteryWarningPercent) }
    }

    @Published var progressBarGradient: Bool {
        didSet { save(progressBarGradient, key: Keys.progressBarGradient) }
    }

    // ── Appearance

    @Published var glassIntensity: Double {
        didSet { save(glassIntensity, key: Keys.glassIntensity) }
    }

    @Published var glassStyle: String {
        didSet { save(glassStyle, key: Keys.glassStyle) }
    }

    @Published var systemAccent: Bool {
        didSet { save(systemAccent, key: Keys.systemAccent) }
    }

    @Published var albumColors: Bool {
        didSet { save(albumColors, key: Keys.albumColors) }
    }

    @Published var reduceMotionSupport: Bool {
        didSet { save(reduceMotionSupport, key: Keys.reduceMotionSupport) }
    }

    // ── Playback

    @Published var metadataRefreshRate: Double {
        didSet { save(metadataRefreshRate, key: Keys.metadataRefreshRate) }
    }

    @Published var commandRouting: String {
        didSet { save(commandRouting, key: Keys.commandRouting) }
    }

    // ── Permissions (read-only state written externally)

    @Published var mediaRemotePermission: BackendPermissionState = .unknown
    @Published var musicAutomationPermission: BackendPermissionState = .unknown
    @Published var spotifyAutomationPermission: BackendPermissionState = .unknown
    @Published var lyricsPermission: BackendPermissionState = .unknown

    // ── Init / Load

    init() {
        source                = PlaybackSource(rawValue: defaults.string(forKey: Keys.source) ?? "") ?? .automatic
        launchAtLogin         = defaults.object(forKey: Keys.launchAtLogin)     as? Bool ?? false
        alwaysOnTop           = defaults.object(forKey: Keys.alwaysOnTop)       as? Bool ?? true
        hideFromScreenCapture = defaults.object(forKey: Keys.hideFromScreenCapture) as? Bool ?? false
        hideWhenPlaybackStops = defaults.object(forKey: Keys.hideWhenPlaybackStops) as? Bool ?? false
        preferredMode         = MiniPlayerMode(rawValue: defaults.string(forKey: Keys.preferredMode) ?? "") ?? .compact
        albumTintStrength     = defaults.object(forKey: Keys.albumTintStrength) as? Double ?? 0.10
        artworkGlow           = defaults.object(forKey: Keys.artworkGlow)       as? Bool ?? true
        cornerRadius          = defaults.object(forKey: Keys.cornerRadius)      as? Double ?? 26
        positionBehavior      = defaults.string(forKey: Keys.positionBehavior)  ?? "Bottom Center"
        enableLRCLIB          = defaults.object(forKey: Keys.enableLRCLIB)      as? Bool ?? true
        syncedLyrics          = defaults.object(forKey: Keys.syncedLyrics)      as? Bool ?? true
        plainLyrics           = defaults.object(forKey: Keys.plainLyrics)       as? Bool ?? true
        lyricFontSize         = defaults.object(forKey: Keys.lyricFontSize)     as? Double ?? 18
        missingLyricsMessage  = defaults.string(forKey: Keys.missingLyricsMessage) ?? "Bummer, someone forgot to add lyrics."
        queueButtonEnabled    = defaults.object(forKey: Keys.queueButtonEnabled) as? Bool ?? true
        showLyricsButton      = defaults.object(forKey: Keys.showLyricsButton) as? Bool ?? true
        ambientModeEnabled    = defaults.object(forKey: Keys.ambientModeEnabled) as? Bool ?? true
        lowBatteryWarningPercent = defaults.object(forKey: Keys.lowBatteryWarningPercent) as? Double ?? 20
        progressBarGradient   = defaults.object(forKey: Keys.progressBarGradient) as? Bool ?? true
        glassIntensity        = defaults.object(forKey: Keys.glassIntensity)    as? Double ?? 0.72
        glassStyle            = defaults.string(forKey: Keys.glassStyle)        ?? "Regular"
        systemAccent          = defaults.object(forKey: Keys.systemAccent)      as? Bool ?? false
        albumColors           = defaults.object(forKey: Keys.albumColors)       as? Bool ?? true
        reduceMotionSupport   = defaults.object(forKey: Keys.reduceMotionSupport) as? Bool ?? true
        metadataRefreshRate   = defaults.object(forKey: Keys.metadataRefreshRate) as? Double ?? 2.0
        commandRouting        = defaults.string(forKey: Keys.commandRouting)    ?? "Fast + MediaRemote"
    }

    // ── Private helpers

    private func save(_ value: Bool, key: String) {
        defaults.set(value, forKey: key)
    }
    private func save(_ value: Double, key: String) {
        defaults.set(value, forKey: key)
    }
    private func save(_ value: String, key: String) {
        defaults.set(value, forKey: key)
    }

    // ── System effects

    private func applyLaunchAtLogin() {
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    private func applyAlwaysOnTop() {
        NotificationCenter.default.post(
            name: .init("MiniMusix.alwaysOnTopChanged"),
            object: alwaysOnTop
        )
    }

    private func applyScreenCaptureHiding() {
        NotificationCenter.default.post(
            name: .init("MiniMusix.screenCaptureChanged"),
            object: hideFromScreenCapture
        )
    }

    func runtimeSettings(preserving current: MiniMusixSettings = MiniMusixSettings()) -> MiniMusixSettings {
        var runtime = current
        runtime.source = source
        runtime.launchAtLogin = launchAtLogin
        runtime.alwaysOnTop = alwaysOnTop
        runtime.hideFromScreenCapture = hideFromScreenCapture
        runtime.hideWhenPlaybackStops = hideWhenPlaybackStops
        runtime.preferredMode = preferredMode
        runtime.albumTintStrength = albumTintStrength
        runtime.artworkGlow = artworkGlow
        runtime.cornerRadius = cornerRadius
        runtime.positionBehavior = positionBehavior
        runtime.enableLRCLIB = enableLRCLIB
        runtime.syncedLyrics = syncedLyrics
        runtime.plainLyrics = plainLyrics
        runtime.lyricFontSize = lyricFontSize
        runtime.missingLyricsMessage = missingLyricsMessage
        runtime.queueButtonEnabled = queueButtonEnabled
        runtime.showLyricsButton = showLyricsButton
        runtime.ambientModeEnabled = ambientModeEnabled
        runtime.lowBatteryWarningPercent = Int(lowBatteryWarningPercent.rounded())
        runtime.progressBarGradient = progressBarGradient
        runtime.glassIntensity = glassIntensity
        runtime.glassStyle = glassStyle
        runtime.systemAccent = systemAccent
        runtime.albumColors = albumColors
        runtime.reduceMotionSupport = reduceMotionSupport
        runtime.metadataRefreshRate = metadataRefreshRate
        runtime.commandRouting = commandRouting
        return runtime
    }

    func apply(onboarding settings: OnboardingSettings) {
        preferredMode = settings.playerMode
        albumTintStrength = settings.albumTint
        artworkGlow = settings.artworkGlow
        glassIntensity = settings.glassIntensity
        progressBarGradient = settings.barGradient
        glassStyle = settings.glassStyle.rawValue
        alwaysOnTop = settings.floatAbove
        hideWhenPlaybackStops = settings.hideOnStop
        launchAtLogin = settings.launchAtLogin
        queueButtonEnabled = settings.showQueueButton
        showLyricsButton = settings.showLyricsButton
        ambientModeEnabled = settings.ambientModeEnabled
        enableLRCLIB = settings.lyricsEnabled
        syncedLyrics = settings.preferSynced
        plainLyrics = settings.plainFallback
    }
}

// MARK: - Settings Sections

enum SettingsSection: String, CaseIterable, Identifiable {
    case general    = "General"
    case miniPlayer = "Player"
    case lyrics     = "Lyrics"
    case appearance = "Appearance"
    case permissions = "Access"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:    "gearshape.fill"
        case .miniPlayer: "music.note.tv.fill"
        case .lyrics:     "quote.bubble.fill"
        case .appearance: "paintpalette.fill"
        case .permissions: "lock.shield.fill"
        }
    }
}

// MARK: - MiniMusixSettingsView

struct MiniMusixSettingsView: View {
    @ObservedObject var store: NowPlayingStore
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var selection: SettingsSection = .general
    @State private var statusExpanded = true

    private let textColor      = SettingsPalette.paleText
    private let secondaryText  = SettingsPalette.paleText.opacity(0.68)

    private var s: SettingsManager { settingsManager }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    settingsHeader
                    nowPlayingHeader
                    settingsContent(for: selection)
                }
                .padding(.horizontal, 44)
                .padding(.top, 44)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 880, height: 880)
        .background(contentBackground)
        .background(BorderlessWindowConfigurator())
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(alignment: .topLeading) {
            LiquidGlassCloseButton(tint: SettingsPalette.paleText.opacity(0.9), size: 36, action: closeWindow)
                .padding(14)
        }
        .onAppear {
            store.applyPersistedSettings()
        }
        .onReceive(settingsManager.objectWillChange) { _ in
            DispatchQueue.main.async {
                store.applyPersistedSettings()
            }
        }
        .animation(AppMotion.panel(), value: selection)
    }

    private func closeWindow() {
        NSApplication.shared.keyWindow?.close()
    }

    // MARK: - Accent

    private var accent: Color {
        SettingsPalette.accent
    }

    // MARK: - Background

    private var contentBackground: some View {
        ZStack {
            SettingsPalette.dark
            MojaveBackdrop(opacity: 1)
                .blur(radius: 7)
                .scaleEffect(1.04)
            LinearGradient(
                stops: [
                    .init(color: SettingsPalette.dark.opacity(0.78), location: 0),
                    .init(color: SettingsPalette.mid.opacity(0.58), location: 0.52),
                    .init(color: SettingsPalette.dark.opacity(0.86), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipped()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSidebarGroup(title: "MiniMusix", sections: [.general, .miniPlayer, .lyrics, .appearance, .permissions], selection: $selection, accent: accent)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .padding(.bottom, 20)
        .frame(width: 250)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(SettingsPalette.dark.opacity(0.62))
        )
    }

    // MARK: - Section Header

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.rawValue)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(textColor)
                    .contentTransition(.identity)
                Text(sectionSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .transition(.opacity.combined(with: .offset(y: 2)))
                    .id(sectionSubtitle)
            }
            Spacer()
        }
        .animation(AppMotion.panel(), value: selection)
    }

    // MARK: - Now Playing Header

    private var nowPlayingHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(AppMotion.panel()) {
                    statusExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusDotColor.opacity(0.6), radius: 4)

                    Text(statusHeadline)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(textColor.opacity(0.88))

                    Spacer()

                    Image(systemName: statusExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(secondaryText.opacity(0.60))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if statusExpanded {
                Divider().opacity(0.20)
                HStack(spacing: 0) {
                    StatusPill(label: "Player", value: s.preferredMode.rawValue, accent: accent)
                    statusSep
                    StatusPill(label: "Lyrics", value: s.enableLRCLIB ? "On" : "Off", accent: accent)
                    statusSep
                    StatusPill(label: "Audio", value: s.queueButtonEnabled ? "On" : "Off", accent: accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .transition(AppMotion.subtleInsertion)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(statusDotColor.opacity(0.22), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    private var statusDotColor: Color {
        store.currentTrack == nil ? SettingsPalette.light.opacity(0.60) : SettingsPalette.light
    }

    private var statusHeadline: String {
        if let track = store.currentTrack {
            return "\(track.identity.title) by \(track.identity.artist)"
        }
        return "MiniMusix is ready"
    }

    private var statusSep: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 12)
    }

    // MARK: - Section Content

    @ViewBuilder
    private func settingsContent(for section: SettingsSection) -> some View {
        Group {
            switch section {
            case .general:    generalSection
            case .miniPlayer: miniPlayerSection
            case .lyrics:     lyricsSection
            case .appearance: appearanceSection
            case .permissions: permissionsSection
            }
        }
        .id(section)
        .transition(AppMotion.subtleInsertion)
        .animation(AppMotion.panel(), value: section)
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: "Music Apps") {
                HStack(spacing: 16) {
                    SourceTile(title: "Music", icon: "music.note", source: .appleMusic,
                               selection: Binding(get: { s.source }, set: { s.source = $0; store.applySourceChange($0) }))
                    SourceTile(title: "Spotify", icon: "music.note.list", source: .spotify,
                               selection: Binding(get: { s.source }, set: { s.source = $0; store.applySourceChange($0) }))
                    SourceTile(title: "Automatic", icon: "sparkles", source: .automatic,
                               selection: Binding(get: { s.source }, set: { s.source = $0; store.applySourceChange($0) }))
                    SourceTile(title: "All Apps", icon: "dot.radiowaves.left.and.right", source: .mediaRemote,
                               selection: Binding(get: { s.source }, set: { s.source = $0; store.applySourceChange($0) }))
                }
                Text(sourceDescription)
                    .font(.caption)
                    .foregroundStyle(secondaryText.opacity(0.72))
                    .padding(.top, 2)
                    .transition(.opacity)
                    .id(s.source)
                    .animation(AppMotion.content(), value: s.source)
            }

            SettingsCard(title: "Window Behavior") {
                SettingsToggleRow(icon: "lock.open.fill", title: "Launch at Login",
                                  subtitle: "Start MiniMusix automatically.",
                                  isOn: Binding(get: { s.launchAtLogin }, set: { s.launchAtLogin = $0 }))
                SettingsToggleRow(icon: "pin.fill", title: "Always on Top",
                                  subtitle: "Keep the miniplayer above other windows.",
                                  isOn: Binding(get: { s.alwaysOnTop }, set: { s.alwaysOnTop = $0 }))
                SettingsToggleRow(icon: "eye.slash.fill", title: "Hide from Screenshots",
                                  subtitle: "Keep MiniMusix out of captures when macOS allows it.",
                                  isOn: Binding(get: { s.hideFromScreenCapture }, set: { s.hideFromScreenCapture = $0 }))
                SettingsToggleRow(icon: "moon.fill", title: "Hide When Playback Stops",
                                  subtitle: "Collapse when nothing is playing.",
                                  isOn: Binding(get: { s.hideWhenPlaybackStops }, set: { s.hideWhenPlaybackStops = $0 }))
            }
        }
    }

    private var sourceDescription: String {
        switch s.source {
        case .appleMusic:  return "MiniMusix will follow and control Apple Music."
        case .spotify:     return "MiniMusix will follow and control Spotify."
        case .automatic:   return "MiniMusix will follow whichever supported app is playing."
        case .mediaRemote: return "MiniMusix will follow audio from any app macOS shares with it."
        case .cached:      return "MiniMusix will keep showing the last song when playback briefly disappears."
        }
    }

    // MARK: - MiniPlayer

    private var miniPlayerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: "Default Mode") {
                HStack(spacing: 16) {
                    ForEach(MiniPlayerMode.allCases) { mode in
                        ModeTile(mode: mode,
                                 selection: Binding(get: { s.preferredMode }, set: { s.preferredMode = $0; store.applyModeChange($0) }),
                                 accent: accent)
                    }
                }
                Text("Choose how the floating player opens by default.")
                    .font(.caption)
                    .foregroundStyle(secondaryText.opacity(0.60))
            }

            SettingsCard(title: "Controls") {
                SettingsToggleRow(icon: "airplayaudio", title: "Audio Output Button",
                                  subtitle: "Show nearby speakers and headphones next to the player.",
                                  isOn: Binding(get: { s.queueButtonEnabled }, set: { s.queueButtonEnabled = $0 }))
                SettingsToggleRow(icon: "quote.bubble", title: "Lyrics Button",
                                  subtitle: "Show the lyrics control next to the player.",
                                  isOn: Binding(get: { s.showLyricsButton }, set: { s.showLyricsButton = $0 }))
                SettingsToggleRow(icon: "square.on.square.dashed", title: "Ambient Mode",
                                  subtitle: "Double-click album artwork to open the immersive full-screen player.",
                                  isOn: Binding(get: { s.ambientModeEnabled }, set: { s.ambientModeEnabled = $0 }))
                SettingsPercentSliderRow(
                    icon: "battery.25",
                    title: "Low Battery Alert",
                    subtitle: "Show a companion alert at \(Int(s.lowBatteryWarningPercent.rounded()))%.",
                    value: Binding(get: { s.lowBatteryWarningPercent }, set: { s.lowBatteryWarningPercent = $0; store.applyLowBatteryWarningPercent($0) }),
                    range: 5...50
                )
            }

            SettingsCard(title: "Shape") {
                SettingsSliderRow(icon: "paintbrush.pointed.fill", title: "Album Tint Strength",
                                  value: Binding(get: { s.albumTintStrength }, set: { s.albumTintStrength = $0 }),
                                  range: 0...0.24)
                SettingsToggleRow(icon: "sparkle", title: "Artwork Glow",
                                  subtitle: "Use a subtle glow based on artwork.",
                                  isOn: Binding(get: { s.artworkGlow }, set: { s.artworkGlow = $0 }))
                SettingsSliderRow(icon: "square.roundedbottom.fill", title: "Corner Radius",
                                  value: Binding(get: { s.cornerRadius }, set: { s.cornerRadius = $0 }),
                                  range: 18...38)
            }

            SettingsCard(title: "Position") {
                Picker("Position Behavior",
                       selection: Binding(get: { s.positionBehavior }, set: { s.positionBehavior = $0; store.applyPositionBehavior($0) })) {
                    Text("Bottom Center").tag("Bottom Center")
                    Text("Remember Last Position").tag("Remember Last Position")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Lyrics

    private var lyricsSection: some View {
        SettingsCard(title: "Lyrics") {
            SettingsToggleRow(icon: "quote.bubble.fill", title: "Online Lyrics",
                              subtitle: "Find lyrics automatically when music changes.",
                              isOn: Binding(get: { s.enableLRCLIB }, set: { s.enableLRCLIB = $0; store.applyPersistedSettings(reloadLyrics: true) }))
            SettingsToggleRow(icon: "text.line.first.and.arrowtriangle.forward", title: "Line-by-Line Lyrics",
                              subtitle: "Highlight lyrics in time with the song when available.",
                              isOn: Binding(get: { s.syncedLyrics }, set: { s.syncedLyrics = $0; store.applyPersistedSettings(reloadLyrics: true) }))
            SettingsToggleRow(icon: "text.alignleft", title: "Regular Lyrics",
                              subtitle: "Show standard lyrics when line-by-line lyrics are not available.",
                              isOn: Binding(get: { s.plainLyrics }, set: { s.plainLyrics = $0; store.applyPersistedSettings(reloadLyrics: true) }))
            SettingsSliderRow(icon: "textformat.size", title: "Font Size",
                              value: Binding(get: { s.lyricFontSize }, set: { s.lyricFontSize = $0 }),
                              range: 15...28)

            HStack(spacing: 14) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SettingsPalette.light)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("When Lyrics Are Missing")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsPalette.paleText)
                    TextField("No lyrics found.", text: Binding(get: { s.missingLyricsMessage }, set: { s.missingLyricsMessage = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsCard(title: "Appearance") {
            SettingsSliderRow(icon: "circle.lefthalf.filled", title: "Glass Intensity",
                              value: Binding(get: { s.glassIntensity }, set: { s.glassIntensity = $0; store.applyGlassIntensity($0) }),
                              range: 0.25...1)
            SettingsToggleRow(icon: "paintpalette.fill", title: "System Accent",
                              subtitle: "Use your macOS accent color.",
                              isOn: Binding(get: { s.systemAccent }, set: { s.systemAccent = $0; store.applyAccentChange() }))
            SettingsToggleRow(icon: "record.circle", title: "Album Colors",
                              subtitle: "Tint UI based on artwork.",
                              isOn: Binding(get: { s.albumColors }, set: { s.albumColors = $0; store.applyAlbumColorChange() }))
            SettingsToggleRow(icon: "chart.bar.fill", title: "Playback Bar Gradient",
                              subtitle: "Blend the progress bar through album colors.",
                              isOn: Binding(get: { s.progressBarGradient }, set: { s.progressBarGradient = $0 }))
            VStack(alignment: .leading, spacing: 6) {
                Text("Glass Style")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsPalette.paleText)
                Picker("", selection: Binding(get: { s.glassStyle }, set: { s.glassStyle = $0 })) {
                    Text("Soft").tag("Soft")
                    Text("Regular").tag("Regular")
                    Text("Dense").tag("Dense")
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            SettingsToggleRow(icon: "figure.walk.motion", title: "Gentle Motion",
                              subtitle: "Use calmer animations when macOS requests less motion.",
                              isOn: Binding(get: { s.reduceMotionSupport }, set: { s.reduceMotionSupport = $0 }))
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: "Connection Status") {
                BackendPermissionRow(icon: "dot.radiowaves.left.and.right", title: "Now Playing", state: store.settings.mediaRemotePermission)
                BackendPermissionRow(icon: "music.note", title: "Apple Music Control", state: store.settings.musicAutomationPermission)
                BackendPermissionRow(icon: "music.note.list", title: "Spotify Control", state: store.settings.spotifyAutomationPermission)
                BackendPermissionRow(icon: "airplayaudio", title: "Wireless Audio", state: store.settings.bluetoothPermission)
                BackendPermissionRow(icon: "quote.bubble.fill", title: "Lyrics Search", state: store.settings.lyricsPermission)
            }

            SettingsCard(title: "Connections") {
                SettingsActionRow(
                    icon: "arrow.clockwise",
                    title: "Check Connections",
                    subtitle: "Re-check music apps, wireless audio, and lyrics search.",
                    label: "Refresh"
                ) { store.refreshPermissions() }

                SettingsActionRow(
                    icon: "hand.raised.fill",
                    title: "Allow Music & Spotify",
                    subtitle: "Lets MiniMusix play, pause, and skip in your music apps.",
                    label: "Allow"
                ) { store.requestAutomationPermission() }

                SettingsActionRow(
                    icon: "airplayaudio",
                    title: "Allow Wireless Audio",
                    subtitle: "Lets MiniMusix find nearby speakers and headphones.",
                    label: "Allow"
                ) { store.requestBluetoothPermission() }

                SettingsActionRow(
                    icon: "slider.horizontal.3",
                    title: "Open App Access",
                    subtitle: "Review MiniMusix access in System Settings.",
                    label: "Open"
                ) { store.openAutomationPrivacySettings() }

                SettingsActionRow(
                    icon: "doc.text.magnifyingglass",
                    title: "Export Diagnostics",
                    subtitle: "Write Focus, brightness, playback, and access status to Documents.",
                    label: "Export"
                ) { store.exportLogs() }
            }

            SettingsCard(title: "Reset") {
                SettingsActionRow(
                    icon: "arrow.counterclockwise",
                    title: "Show Onboarding Again",
                    subtitle: "Runs the setup flow next time MiniMusix opens.",
                    label: "Reset"
                ) { store.resetOnboarding() }
            }
        }
    }

    private var sectionSubtitle: String {
        switch selection {
        case .general:    return "Choose what MiniMusix follows and how it behaves."
        case .miniPlayer: return "Tune the floating player layout and feel."
        case .lyrics:     return "Choose how MiniMusix finds and shows lyrics."
        case .appearance: return "Adjust the look and feel of the player."
        case .permissions: return "Manage music app, speaker, and lyrics access."
        }
    }
}

// MARK: - StatusPill

struct StatusPill: View {
    var label: String
    var value: String
    var accent: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SettingsPalette.paleText.opacity(0.50))
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsPalette.paleText.opacity(0.92))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .animation(AppMotion.content(), value: value)
    }
}

// MARK: - BackendPermissionRow

struct BackendPermissionRow: View {
    var icon: String
    var title: String
    var state: BackendPermissionState

    private var statusText: String {
        switch state {
        case .unknown:
            return "Not checked"
        case .ready:
            return "Ready"
        case .unavailable(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch state {
        case .unknown:
            return SettingsPalette.paleText.opacity(0.55)
        case .ready:
            return .green.opacity(0.86)
        case .unavailable:
            return .orange.opacity(0.90)
        }
    }

    private var statusIcon: String {
        switch state {
        case .unknown:
            return "questionmark.circle.fill"
        case .ready:
            return "checkmark.circle.fill"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SettingsPalette.light)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsPalette.paleText)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.paleText.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Image(systemName: statusIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 20)
        }
        .padding(.vertical, 6)
        .animation(AppMotion.content(), value: state)
    }
}

// MARK: - SettingsActionRow

struct SettingsActionRow: View {
    var icon: String
    var title: String
    var subtitle: String
    var label: String
    var destructive: Bool = false
    var action: () -> Void

    @State private var hovered = false
    @State private var triggered = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: triggered ? "checkmark" : icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(destructive ? .red.opacity(0.80) : SettingsPalette.light)
                .frame(width: 28)
                .animation(AppMotion.control(), value: triggered)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsPalette.paleText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.paleText.opacity(0.55))
            }

            Spacer()

            Button {
                action()
                triggered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    triggered = false
                }
            } label: {
                Text(triggered ? "Done" : label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(destructive ? .red : SettingsPalette.paleText)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(
                        Capsule()
                            .fill(destructive
                                  ? Color.red.opacity(hovered ? 0.16 : 0.09)
                                  : SettingsPalette.mid.opacity(hovered ? 0.55 : 0.35))
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            destructive ? Color.red.opacity(0.28) : SettingsPalette.light.opacity(0.30),
                            lineWidth: 0.7
                        )
                        .allowsHitTesting(false)
                    }
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .animation(AppMotion.control(), value: hovered)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - SettingsSidebarGroup / Row

struct SettingsSidebarGroup: View {
    let title: String
    let sections: [SettingsSection]
    @Binding var selection: SettingsSection
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsPalette.paleText.opacity(0.48))
                .textCase(.uppercase)
                .padding(.horizontal, 6)

            VStack(spacing: 6) {
                ForEach(sections) { section in
                    SettingsSidebarRow(section: section, isSelected: selection == section, accent: accent) {
                        withAnimation(AppMotion.panel()) {
                            selection = section
                        }
                    }
                }
            }
        }
    }
}

struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? SettingsPalette.paleText : SettingsPalette.paleText.opacity(0.62))
                    .frame(width: 24)

                Text(section.rawValue)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SettingsPalette.paleText : SettingsPalette.paleText.opacity(0.66))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                (isSelected ? SettingsPalette.mid.opacity(0.34) : (hovered ? SettingsPalette.mid.opacity(0.16) : Color.clear)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(AppMotion.control(), value: hovered)
    }
}

// MARK: - SettingsCard

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SettingsPalette.paleText)

            VStack(spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SettingsPalette.dark.opacity(0.24))
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Row Components

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SettingsPalette.light)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsPalette.paleText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.paleText.opacity(0.62))
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(SettingsPalette.light)
        }
        .padding(.vertical, 6)
    }
}

struct SettingsSliderRow<Value: BinaryFloatingPoint>: View {
    let icon: String
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Value>

    private var doubleBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(value) },
            set: { value = Value($0) }
        )
    }

    private var doubleRange: ClosedRange<Double> {
        Double(range.lowerBound)...Double(range.upperBound)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SettingsPalette.light)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SettingsPalette.paleText)
            Slider(value: doubleBinding, in: doubleRange)
                .frame(maxWidth: 220)
                .tint(SettingsPalette.light)
        }
        .padding(.vertical, 6)
    }
}

struct SettingsPercentSliderRow<Value: BinaryFloatingPoint>: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var value: Value
    let range: ClosedRange<Value>

    private var doubleBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(value) },
            set: { value = Value($0.rounded()) }
        )
    }

    private var doubleRange: ClosedRange<Double> {
        Double(range.lowerBound)...Double(range.upperBound)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SettingsPalette.light)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsPalette.paleText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.paleText.opacity(0.62))
            }
            Spacer()
            Slider(value: doubleBinding, in: doubleRange, step: 1)
                .frame(width: 180)
                .tint(SettingsPalette.light)
            Text("\(Int(Double(value).rounded()))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(SettingsPalette.paleText.opacity(0.72))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

struct SettingsStaticRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SettingsPalette.light)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SettingsPalette.paleText)
            Spacer()
            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SettingsPalette.paleText.opacity(0.64))
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Source / Mode Tiles

struct SourceTile: View {
    let title: String
    let icon: String
    let source: PlaybackSource
    @Binding var selection: PlaybackSource

    private var appIcon: NSImage? {
        switch source {
        case .appleMusic:
            return NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")
        case .spotify:
            return NSWorkspace.shared.icon(forFile: "/Applications/Spotify.app")
        default:
            return nil
        }
    }

    var body: some View {
        Button {
            withAnimation(AppMotion.panel()) {
                selection = source
            }
        } label: {
            VStack(spacing: 12) {
                Group {
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(10)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 32, weight: .bold))
                    }
                }
                .frame(width: 54, height: 54)
                .background(SettingsPalette.mid.opacity(0.32), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SettingsPalette.paleText)
            }
            .frame(width: 112, height: 112)
            .background((selection == source ? SettingsPalette.mid.opacity(0.54) : SettingsPalette.dark.opacity(0.30)),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        selection == source ? SettingsPalette.light.opacity(0.70) : SettingsPalette.light.opacity(0.18),
                        lineWidth: selection == source ? 1.6 : 0.8
                    )
                    .allowsHitTesting(false)
            }
            .scaleEffect(selection == source ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(AppMotion.panel(), value: selection)
    }
}

struct ModeTile: View {
    let mode: MiniPlayerMode
    @Binding var selection: MiniPlayerMode
    let accent: Color

    var body: some View {
        Button {
            withAnimation(AppMotion.panel()) {
                selection = mode
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(SettingsPalette.paleText)
                Text(mode.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SettingsPalette.paleText)
            }
            .frame(width: 130, height: 96)
            .background(
                selection == mode ? SettingsPalette.mid.opacity(0.54) : SettingsPalette.dark.opacity(0.30),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        selection == mode ? SettingsPalette.light.opacity(0.70) : SettingsPalette.light.opacity(0.18),
                        lineWidth: selection == mode ? 1.6 : 0.8
                    )
                    .allowsHitTesting(false)
            }
            .scaleEffect(selection == mode ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(AppMotion.panel(), value: selection)
    }

    private var icon: String {
        switch mode {
        case .compact:     "capsule.fill"
        case .expanded:    "rectangle.roundedtop.fill"
        case .lyricsFocus: "quote.bubble.fill"
        }
    }
}

// MARK: - Palette

enum SettingsPalette {
    static let dark            = Color(red: 18 / 255, green: 26 / 255, blue: 47 / 255)
    static let mid             = Color(red: 44 / 255, green: 57 / 255, blue: 81 / 255)
    static let light           = Color(red: 78 / 255, green: 90 / 255, blue: 113 / 255)
    static let accent          = light
    static let secondaryAccent = light
    static let text            = dark
    static let secondaryText   = Color(red: 0.25, green: 0.30, blue: 0.40)
    static let paleText        = Color(red: 0.84, green: 0.88, blue: 0.94)
}

// MARK: - PlaybackSource display helper

extension PlaybackSource {
    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify:    return "Spotify"
        case .automatic:  return "Automatic"
        case .mediaRemote: return "All Apps"
        case .cached:     return "Last Song"
        }
    }
}

// MARK: - NowPlayingStore settings actions

extension NowPlayingStore {
    var settingsManager: SettingsManager { SettingsManager.shared }

    func applyPersistedSettings(reloadLyrics: Bool = false) {
        let previousSource = settings.source
        let previousLyricsEnabled = settings.enableLRCLIB
        let previousSyncedLyrics = settings.syncedLyrics
        let previousPlainLyrics = settings.plainLyrics

        settings = settingsManager.runtimeSettings(preserving: settings)

        if previousSource != settings.source {
            Task { await refreshMetadata() }
        }

        if reloadLyrics
            || previousLyricsEnabled != settings.enableLRCLIB
            || previousSyncedLyrics != settings.syncedLyrics
            || previousPlainLyrics != settings.plainLyrics {
            self.reloadLyrics()
        }
    }

    func applySourceChange(_ source: PlaybackSource) {
        settingsManager.source = source
        applyPersistedSettings()
    }

    func applyModeChange(_ mode: MiniPlayerMode) {
        settingsManager.preferredMode = mode
        applyPersistedSettings()
        NotificationCenter.default.post(name: .init("MiniMusix.modeChanged"), object: mode)
    }

    func applyPositionBehavior(_ behavior: String) {
        settingsManager.positionBehavior = behavior
        applyPersistedSettings()
    }

    func applyGlassIntensity(_ value: Double) {
        settingsManager.glassIntensity = value
        applyPersistedSettings()
        NotificationCenter.default.post(name: .init("MiniMusix.glassChanged"), object: value)
    }

    func applyAccentChange() {
        applyPersistedSettings()
        NotificationCenter.default.post(name: .init("MiniMusix.accentChanged"), object: nil)
    }

    func applyAlbumColorChange() {
        applyPersistedSettings()
        NotificationCenter.default.post(name: .init("MiniMusix.albumColorChanged"), object: nil)
    }

    func applyMetadataRefreshRate(_ rate: Double) {
        settingsManager.metadataRefreshRate = rate
        applyPersistedSettings()
    }

    func applyCommandRouting(_ routing: String) {
        settingsManager.commandRouting = routing
        applyPersistedSettings()
    }

    func applyLowBatteryWarningPercent(_ percent: Double) {
        settingsManager.lowBatteryWarningPercent = percent.rounded()
        applyPersistedSettings()
    }

    func clearLyricCache() {
        lyricsService.clearCache()
        reloadLyrics()
    }

    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "mm.onboardingComplete")
    }

    func restoreDefaultSettings() {
        let domain = Bundle.main.bundleIdentifier ?? "com.minimusix"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        settingsManager.source = .automatic
        settingsManager.launchAtLogin = false
        settingsManager.alwaysOnTop = true
        settingsManager.hideFromScreenCapture = false
        settingsManager.hideWhenPlaybackStops = false
        settingsManager.preferredMode = .compact
        settingsManager.albumTintStrength = 0.10
        settingsManager.artworkGlow = true
        settingsManager.cornerRadius = 26
        settingsManager.positionBehavior = "Bottom Center"
        settingsManager.enableLRCLIB = true
        settingsManager.syncedLyrics = true
        settingsManager.plainLyrics = true
        settingsManager.lyricFontSize = 18
        settingsManager.missingLyricsMessage = "Bummer, someone forgot to add lyrics."
        settingsManager.queueButtonEnabled = true
        settingsManager.showLyricsButton = true
        settingsManager.ambientModeEnabled = true
        settingsManager.lowBatteryWarningPercent = 20
        settingsManager.progressBarGradient = true
        settingsManager.glassIntensity = 0.72
        settingsManager.glassStyle = "Regular"
        settingsManager.systemAccent = false
        settingsManager.albumColors = true
        settingsManager.reduceMotionSupport = true
        settingsManager.metadataRefreshRate = 2.0
        settingsManager.commandRouting = "Fast + MediaRemote"
        applyPersistedSettings(reloadLyrics: true)
    }

    func exportLogs() {
        Task {
            let content = await diagnosticsReport()
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let url = directory.appendingPathComponent("MiniMusix-diagnostics.log")
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("MiniMusix-diagnostics.log")
                let fallbackContent = "\(content)\n\nExport write error: \(error)"
                try? fallbackContent.write(to: fallbackURL, atomically: true, encoding: .utf8)
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([fallbackURL])
                }
                return
            }
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    func runDiagnostics() {
        // Check MediaRemote, network, Automation, post results
        Task {
            await refreshMetadata()
        }
    }

    private func diagnosticsReport() async -> String {
        let permissionLines = [
            "- Now Playing: \(settings.mediaRemotePermission.diagnosticsDescription)",
            "- Apple Music Control: \(settings.musicAutomationPermission.diagnosticsDescription)",
            "- Spotify Control: \(settings.spotifyAutomationPermission.diagnosticsDescription)",
            "- Wireless Audio: \(settings.bluetoothPermission.diagnosticsDescription)",
            "- Lyrics Search: \(settings.lyricsPermission.diagnosticsDescription)"
        ].joined(separator: "\n")

        let playbackLines = [
            "Playback",
            "- Source: \(settings.source.rawValue)",
            "- Preferred mode: \(settings.preferredMode.rawValue)",
            "- Metadata refresh rate: \(settings.metadataRefreshRate)s",
            "- Command routing: \(settings.commandRouting)",
            "- Current track: \(currentTrack.map { "\($0.identity.title) by \($0.identity.artist)" } ?? "none")"
        ].joined(separator: "\n")

        return [
            "MiniMusix diagnostics export - \(Date())",
            "",
            playbackLines,
            "",
            "Access",
            permissionLines,
            "",
            await FocusModeMonitor.diagnosticsReport(),
            "",
            DisplayBrightnessMonitor.diagnosticsReport()
        ].joined(separator: "\n")
    }
}

private extension BackendPermissionState {
    var diagnosticsDescription: String {
        switch self {
        case .unknown:
            return "unknown"
        case .ready:
            return "ready"
        case .unavailable(let reason):
            return "unavailable - \(reason)"
        }
    }
}

// MARK: - DiagonalSettingsTexture (preserved)

struct DiagonalSettingsTexture: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let lineColor = Color.white.opacity(0.38)
            var path = Path()

            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }

            context.stroke(path, with: .color(lineColor), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }
}
