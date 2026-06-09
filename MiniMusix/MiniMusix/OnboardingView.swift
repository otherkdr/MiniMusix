import SwiftUI
import Combine
import AppKit

// MARK: - Color Palette (derived from existing hex codes)
// Deep navy: #121A2E  →  bg base
// Accent:    #2C3951  →  primary accent / button fill
// Mid:       #4E5A71  →  secondary accent
// Text:      #D6E0F0  →  primary text
// Subtext:   #9EADC7  →  secondary text

// MARK: - Onboarding Settings State

struct OnboardingSettings {
    var playerMode: MiniPlayerMode = .compact

    var albumTint: Double      = 0.10
    var artworkGlow: Bool      = true
    var glassIntensity: Double = 0.72
    var barGradient: Bool      = true

    var floatAbove: Bool       = true
    var hideOnStop: Bool       = false
    var launchAtLogin: Bool    = false
    var showQueueButton: Bool  = true
    var showLyricsButton: Bool = true
    var ambientModeEnabled: Bool = true

    var lyricsEnabled: Bool    = true
    var preferSynced: Bool     = true
    var plainFallback: Bool    = true

    var glassStyle: OnboardingGlassStyle = .regular
}

enum OnboardingPreset: String, CaseIterable, Identifiable {
    case focused = "Focused"
    case full    = "Full"
    case lyrics  = "Lyrics"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .focused: return "Compact, quiet, always available."
        case .full:    return "Expanded controls with audio output."
        case .lyrics:  return "Optimized for synced lyric viewing."
        }
    }

    var icon: String {
        switch self {
        case .focused: return "circle.lefthalf.filled"
        case .full:    return "slider.horizontal.3"
        case .lyrics:  return "quote.bubble.fill"
        }
    }
}

enum OnboardingGlassStyle: String, CaseIterable, Identifiable {
    case clear   = "Clear"
    case regular = "Regular"
    case soft    = "Soft"
    var id: String { rawValue }
    var tintOpacity: Double {
        switch self { case .clear: 0.035; case .regular: 0.075; case .soft: 0.12 }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case style        = 1
    case appearance   = 2
    case behavior     = 3
    case lyrics       = 4
    case permissions  = 5
    case finalPreview = 6

    var title: String {
        switch self {
        case .style:        return "Choose Your Style"
        case .appearance:   return "Appearance"
        case .behavior:     return "Behavior"
        case .lyrics:       return "Lyrics"
        case .permissions:  return "Permissions"
        case .finalPreview: return "You're All Set"
        }
    }

    var subtitle: String {
        switch self {
        case .style:        return "Pick a layout that fits how you listen."
        case .appearance:   return "Tint, glow, and glass — make it yours."
        case .behavior:     return "Decide how MiniMusix fits your workflow."
        case .lyrics:       return "Find lyrics automatically, no account needed."
        case .permissions:  return "A few things may need access to work fully."
        case .finalPreview: return "Here's your configured MiniMusix."
        }
    }

    var icon: String {
        switch self {
        case .style:        return "rectangle.3.group"
        case .appearance:   return "paintpalette"
        case .behavior:     return "gearshape.2"
        case .lyrics:       return "quote.bubble"
        case .permissions:  return "lock.shield"
        case .finalPreview: return "sparkles"
        }
    }
}

// MARK: - Phase

enum OnboardingPhase { case intro, steps }

// MARK: - Root Onboarding View

struct OnboardingView: View {
    @ObservedObject var store: NowPlayingStore
    var continueAction: () -> Void

    static let onboardingSize: CGFloat = 600

    // ── Intro state
    @State private var logoVisible      = false
    @State private var logoBlurRadius: CGFloat = 8
    @State private var typedCount       = 0
    @State private var welcomeVisible   = false
    @State private var taglineVisible   = false
    @State private var buttonVisible    = false
    @State private var continueHovered  = false
    @State private var introGlowPulse   = false
    @State private var introUnlocked    = false
    @State private var logoAnimated     = false  // one-shot logo bar animation

    // ── Get Started button alive animation
    @State private var arrowNudge: CGFloat = 0
    @State private var shimmerOffset: CGFloat = -1

    // ── Background parallax
    @State private var bgPhase: Double = 0

    // ── Phase / steps
    @State private var phase: OnboardingPhase = .intro
    @State private var currentStep: OnboardingStep  = .style
    @State private var stepDirection: Int = 1
    @State private var furthestStep: OnboardingStep = .style

    // ── Morph: button → container
    @State private var morphing = false
    @State private var morphScale: CGFloat = 1.0
    @State private var morphOpacity: Double = 1.0
    @State private var transitionBreathing = false
    @State private var completionGlow = false

    // ── Settings accumulator
    @State private var settings = OnboardingSettings()

    // ── Finish animation
    @State private var finishScale: CGFloat  = 1.0
    @State private var finishOpacity: Double = 1.0

    // ── Ambient orb animation
    @State private var orbOffset: CGFloat = 0
    @State private var orbOpacity: Double = 0

    private let titleText = "MiniMusix"

    // ── Palette
    private let bgBase          = Color(red: 0.07, green: 0.10, blue: 0.18)
    private let accent          = Color(red: 0.17, green: 0.22, blue: 0.32)
    private let secondaryAccent = Color(red: 0.31, green: 0.35, blue: 0.44)
    private let highlight       = Color(red: 0.42, green: 0.56, blue: 0.82)
    private let textColor       = Color(red: 0.84, green: 0.88, blue: 0.94)
    private let secondaryText   = Color(red: 0.62, green: 0.68, blue: 0.78)
    private let stepAccent      = Color(red: 0.31, green: 0.35, blue: 0.44)
    private let stepText        = Color(red: 0.84, green: 0.88, blue: 0.94)
    private let stepSubtext     = Color(red: 0.62, green: 0.68, blue: 0.78)

    var body: some View {
        ZStack {
            onboardingBackground

            // Ambient orbs — always present, drift slowly
            ambientOrbs
                .opacity(phase == .intro ? 0 : 1)

            switch phase {
            case .intro:
                introLayout
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.01)),
                            removal:   .opacity.combined(with: .scale(scale: 0.96))
                        )
                    )
            case .steps:
                stepsLayout
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal:   .opacity.combined(with: .scale(scale: 1.02))
                        )
                    )
            }
        }
        .frame(width: Self.onboardingSize, height: Self.onboardingSize)
        .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
        .shadow(color: .black.opacity(0.32), radius: 48, y: 24)
        .shadow(color: highlight.opacity(0.08), radius: 80, y: 40)
        .tint(accent)
        .scaleEffect(finishScale)
        .opacity(finishOpacity)
        // Morph-transition overlay: "button expands into container"
        .overlay {
            if morphing {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .scaleEffect(morphScale)
                    .opacity(morphOpacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            LiquidGlassCloseButton(tint: textColor.opacity(0.92), size: 36, action: closeWindow)
                .padding(14)
        }
        .animation(AppMotion.primary(), value: phase)
        .task(id: phase) {
            guard phase == .intro else { return }
            await runIntroSequence()
        }
        .onAppear {
            // Slowly drifting orbs — extremely subtle
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                orbOffset = 14
                orbOpacity = 1
            }
            // Background parallax phase
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                bgPhase = 1
            }
            // Start alive button idle loop after intro completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                startButtonIdleLoop()
            }
        }
    }

    private func closeWindow() {
        NSApplication.shared.keyWindow?.close()
    }

    // MARK: – Alive button idle loop

    private func startButtonIdleLoop() {
        guard phase == .intro, introUnlocked else { return }
        // Arrow nudges forward slightly, pauses, returns
        let cycle = 3.6
        withAnimation(AppMotion.panel().delay(0)) {
            arrowNudge = 5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(AppMotion.panel()) {
                arrowNudge = 0
            }
        }
        // Subtle shimmer sweep across button
        shimmerOffset = -1
        withAnimation(AppMotion.content().delay(0.06)) {
            shimmerOffset = 1.4
        }
        // Loop
        DispatchQueue.main.asyncAfter(deadline: .now() + cycle) {
            guard phase == .intro else { return }
            startButtonIdleLoop()
        }
    }

    // MARK: – Ambient orbs

    private var ambientOrbs: some View {
        ZStack {
            // Top-left orb — drifts very slowly
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [highlight.opacity(0.09), .clear],
                        center: .center, startRadius: 0, endRadius: 170
                    )
                )
                .frame(width: 320, height: 260)
                .offset(x: -100, y: -120 + orbOffset * 0.4)
                .blur(radius: 2)

            // Bottom-right orb
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [secondaryAccent.opacity(0.12), .clear],
                        center: .center, startRadius: 0, endRadius: 140
                    )
                )
                .frame(width: 280, height: 220)
                .offset(x: 130, y: 140 - orbOffset * 0.3)
                .blur(radius: 2)
        }
        .opacity(orbOpacity)
        .allowsHitTesting(false)
    }

    // MARK: – Background (slowly drifting — barely noticeable)

    private var onboardingBackground: some View {
        ZStack {
            if phase == .intro {
                MojaveBackdrop(opacity: 1)
                    .scaleEffect(1.04 + bgPhase * 0.012)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.08), location: 0),
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.30), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            } else {
                MojaveBackdrop(opacity: 1)
                    .scaleEffect(1.08)
                    .blur(radius: 6)
                    .saturation(0.96)

                LinearGradient(
                    stops: [
                        .init(color: bgBase.opacity(completionGlow ? 0.42 : 0.56), location: 0),
                        .init(color: accent.opacity(completionGlow ? 0.42 : 0.30), location: 0.50),
                        .init(color: bgBase.opacity(completionGlow ? 0.58 : 0.72), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Extremely subtle diagonal grain
                Canvas { ctx, size in
                    ctx.opacity = 0.014
                    var x: CGFloat = -size.height
                    while x < size.width + size.height {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                        ctx.stroke(path, with: .color(.white), lineWidth: 0.4)
                        x += 22
                    }
                }
                .allowsHitTesting(false)

                // Slowly drifting radial highlight — premium depth
                RadialGradient(
                    colors: [secondaryAccent.opacity(completionGlow ? 0.34 : 0.18), .clear],
                    center: UnitPoint(x: 0.44 + bgPhase * 0.05, y: 0.2 + bgPhase * 0.04),
                    startRadius: 0,
                    endRadius: completionGlow ? 420 : 320
                )
                .allowsHitTesting(false)
            }
        }
        .animation(AppMotion.content(), value: completionGlow)
    }

    // MARK: – Intro Layout

    private var introLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 218)

            // Logo — scale 0.92→1.0, opacity fade, blur reduction, spring settle
            MiniMusixLogo(size: 62, animated: logoAnimated, mode: .introMark)
                .scaleEffect(logoVisible ? 1.0 : 0.92)
                .opacity(logoVisible ? 1 : 0)
                .blur(radius: logoBlurRadius)
                .shadow(
                    color: highlight.opacity(introGlowPulse ? 0.36 : 0.0),
                    radius: introGlowPulse ? 30 : 0
                )
                // Background: 0ms / Logo: immediate
                .animation(AppMotion.primary(), value: logoVisible)
                .animation(.easeOut(duration: 0.60), value: logoBlurRadius)
                .animation(.easeInOut(duration: 0.62), value: introGlowPulse)

            Spacer().frame(height: 18)

            // "Welcome to" — Cards: 80ms depth tier
            Text("Welcome to")
                .font(.system(size: 23, weight: .regular, design: .default))
                .foregroundStyle(.white.opacity(0.78))
                .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
                .opacity(welcomeVisible ? 1 : 0)
                .offset(y: welcomeVisible ? 0 : 8)
                .animation(.easeOut(duration: 0.46).delay(0.08), value: welcomeVisible)

            Spacer().frame(height: 1)

            // Animated brand title — letters rise individually, staggered
            introBrandTitle

            Spacer().frame(height: 106)

            // Continue button — Buttons: 180ms tier, emerges from glass blur
            continueButton

            Spacer().frame(height: 58)

            // Tagline — Text: 120ms tier
            Text("Free & open source  ·  No account required")
                .font(.system(size: 11.5, weight: .regular))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.58))
                .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
                .opacity(taglineVisible ? 1 : 0)
                .offset(y: taglineVisible ? 0 : 6)
                .animation(.easeOut(duration: 0.44).delay(0.12), value: taglineVisible)

            Spacer()
        }
        .frame(width: Self.onboardingSize, height: Self.onboardingSize)
    }

    // MARK: – Brand title: each letter rises, opacity fade, staggered

    private var introBrandTitle: some View {
        HStack(spacing: 0) {
            ForEach(Array(titleText.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.system(size: 35, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.36), radius: 12, y: 5)
                    .opacity(index < typedCount ? 1 : 0)
                    .scaleEffect(index < typedCount ? 1 : 0.80, anchor: .bottom)
                    .offset(y: index < typedCount ? 0 : 10)
                    .blur(radius: index < typedCount ? 0 : 3)
                    .animation(
                        AppMotion.control()
                            .delay(Double(index) * 0.012),
                        value: typedCount
                    )
            }
        }
        .frame(height: 43, alignment: .center)
        .accessibilityLabel(titleText)
    }

    // MARK: – Get Started button (alive, emerges from glass blur)

    private var continueButton: some View {
        Button {
            guard introUnlocked else { return }
            triggerMorphTransition()
        } label: {
            ZStack {
                // Shimmer sweep — glass highlight
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.18), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: geo.size.width * shimmerOffset)
                    .blur(radius: 2)
                    .clipped()
                    .allowsHitTesting(false)
                }
                .clipShape(Capsule())

                HStack(spacing: 7) {
                    Text("Get Started")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        // Arrow slides forward on idle nudge and hover
                        .offset(x: arrowNudge + (continueHovered ? 3 : 0))
                        .animation(
                            AppMotion.control(),
                            value: continueHovered
                        )
                }
                .foregroundStyle(accent)
            }
            .frame(width: 154, height: 42)
            .background(
                ZStack {
                    Capsule().fill(.white.opacity(0.94))
                    Capsule().fill(
                        LinearGradient(
                            colors: [.white.opacity(0.30), .clear],
                            startPoint: .top, endPoint: .center
                        )
                    )
                }
            )
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.36), lineWidth: 0.8)
            }
            .shadow(
                color: .black.opacity(continueHovered ? 0.24 : 0.16),
                radius: continueHovered ? 22 : 14,
                y: continueHovered ? 11 : 7
            )
            .scaleEffect(continueHovered && introUnlocked ? 1.030 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { continueHovered = $0 }
        // Emerges from glass blur: scales into place, settles naturally
        .opacity(buttonVisible ? 1 : 0)
        .offset(y: buttonVisible ? 0 : 14)
        .blur(radius: buttonVisible ? 0 : 6)
        .animation(AppMotion.panel().delay(0.18), value: buttonVisible)
        .animation(AppMotion.control(), value: continueHovered)
        .disabled(!introUnlocked)
    }

    // MARK: – Morph: button expands → becomes onboarding container

    private func triggerMorphTransition() {
        morphing = true
        morphScale = 0.14
        morphOpacity = 0

        // Button expands outward as ripple
        withAnimation(AppMotion.panel()) {
            morphScale = 1.06
            morphOpacity = 0.55
        }
        // Then contract to fill and fade as steps layout fades in
        withAnimation(AppMotion.panel().delay(0.18)) {
            morphScale = 1.0
            morphOpacity = 0
        }
        // Switch phase after morph peaks
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(AppMotion.primary()) {
                phase = .steps
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                morphing = false
            }
        }
    }

    // MARK: – Steps Layout

    private var stepsLayout: some View {
        VStack(spacing: 0) {
            stepsHeader
                .padding(.leading, 82)
                .padding(.trailing, 34)
                .padding(.top, 28)

            Spacer(minLength: currentStep == .finalPreview ? 92 : 42)

            stepContentPanel
                .frame(width: 506)
                .frame(minHeight: currentStep == .finalPreview ? 254 : 320)
                .opacity(transitionBreathing ? 0.82 : 1)
                .scaleEffect(transitionBreathing ? 0.985 : 1)
                .blur(radius: transitionBreathing ? 1.4 : 0)
                .animation(AppMotion.content(), value: transitionBreathing)

            Spacer(minLength: 0)

            navBar
                .padding(.horizontal, 34)
                .padding(.bottom, 28)
        }
        .frame(width: Self.onboardingSize, height: Self.onboardingSize)
    }

    // MARK: – Step Content

    @ViewBuilder
    private var stepContentPanel: some View {
        Group {
            switch currentStep {
            case .style:
                Step1StylePanel(
                    selection: $settings.playerMode,
                    accent: stepAccent, textColor: stepText, secondaryText: stepSubtext
                )
            case .appearance:
                Step2AppearancePanel(
                    settings: $settings,
                    accent: stepAccent, secondaryAccent: stepAccent.opacity(0.78),
                    textColor: stepText, secondaryText: stepSubtext
                )
            case .behavior:
                Step3BehaviorPanel(
                    settings: $settings,
                    accent: stepAccent, textColor: stepText, secondaryText: stepSubtext
                )
            case .lyrics:
                Step4LyricsPanel(
                    settings: $settings,
                    accent: stepAccent, textColor: stepText, secondaryText: stepSubtext
                )
            case .permissions:
                Step5PermissionsPanel(
                    store: store,
                    launchAtLogin: settings.launchAtLogin,
                    accent: stepAccent, textColor: stepText, secondaryText: stepSubtext
                )
            case .finalPreview:
                Step6FinalPanel(
                    settings: settings,
                    accent: stepAccent, textColor: stepText, secondaryText: stepSubtext
                ) {
                    withAnimation(AppMotion.content()) {
                        completionGlow = true
                    }
                }
            }
        }
        .id(currentStep)
        .transition(stepTransition)
    }

    // MARK: – Morphic step transition

    private var stepTransition: AnyTransition {
        return .asymmetric(
            insertion: .offset(x: CGFloat(stepDirection) * 20, y: 8)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985)),
            removal: .offset(x: CGFloat(stepDirection) * -12, y: -6)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.992))
        )
    }

    // MARK: – Steps header

    private var stepsHeader: some View {
        HStack(spacing: 14) {
            MiniMusixLogo(size: 32, animated: logoAnimated, mode: .introMark)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)

            Text("MiniMusix")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(stepText)
                .shadow(color: .black.opacity(0.20), radius: 8, y: 3)

            Spacer()

            OnboardingProgressBar(
                currentStep: currentStep,
                furthestStep: furthestStep,
                accent: stepAccent,
                textColor: stepText,
                secondaryText: stepSubtext
            ) { step in goToStep(step) }
            .frame(width: 168)
        }
    }

    // MARK: – Nav Bar — Buttons tier (180ms delay)

    private var navBar: some View {
        HStack(spacing: 10) {
            Button {
                guard currentStep.rawValue > 1 else {
                    withAnimation(AppMotion.primary()) { phase = .intro }
                    return
                }
                stepDirection = -1
                transition(to: OnboardingStep(rawValue: currentStep.rawValue - 1)!)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Text(currentStep.rawValue == 1 ? "Intro" : "Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(stepSubtext)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Capsule().fill(accent.opacity(0.54)))
                .overlay { Capsule().strokeBorder(secondaryAccent.opacity(0.34), lineWidth: 0.7) }
            }
            .buttonStyle(.plain)

            Spacer()

            if currentStep == .permissions {
                Button { advanceStep() } label: {
                    Text("Skip")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(stepSubtext)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }

            Button {
                if currentStep == .finalPreview { finishOnboarding() }
                else { advanceStep() }
            } label: {
                HStack(spacing: 8) {
                    Text(currentStep == .finalPreview ? "Start Listening" : "Continue")
                        .font(.system(size: 13.5, weight: .semibold))
                        .tracking(0.2)
                    Image(systemName: currentStep == .finalPreview ? "music.note" : "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(stepText)
                .padding(.horizontal, 22)
                .frame(height: 40)
                .background(
                    ZStack {
                        Capsule().fill(secondaryAccent)
                        Capsule().fill(
                            LinearGradient(
                                colors: [.white.opacity(0.16), .clear],
                                startPoint: .top, endPoint: .center
                            )
                        )
                    }
                )
                .overlay { Capsule().strokeBorder(stepText.opacity(0.20), lineWidth: 0.8) }
                .shadow(color: secondaryAccent.opacity(0.24), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: – Actions

    private func advanceStep() {
        stepDirection = 1
        transition(to: OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .finalPreview)
    }

    private func goToStep(_ step: OnboardingStep) {
        guard step.rawValue <= furthestStep.rawValue, step != currentStep else { return }
        stepDirection = step.rawValue > currentStep.rawValue ? 1 : -1
        transition(to: step)
    }

    private func transition(to step: OnboardingStep) {
        completionGlow = false
        withAnimation(AppMotion.content()) {
            transitionBreathing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(AppMotion.primary()) {
                currentStep = step
                if currentStep.rawValue > furthestStep.rawValue { furthestStep = currentStep }
                transitionBreathing = false
            }
        }
    }

    private func finishOnboarding() {
        SettingsManager.shared.apply(onboarding: settings)
        store.applyPersistedSettings(reloadLyrics: true)

        withAnimation(AppMotion.primary().delay(0.06)) {
            finishScale   = 0.14
            finishOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) { continueAction() }
    }

    // MARK: – Intro sequence (depth timing: bg=0ms, cards=80ms, text=120ms, buttons=180ms)

    @MainActor
    private func runIntroSequence() async {
        resetIntroState()

        // Background: 0ms (already visible)

        // Logo appears — spring settle with blur reduction
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled, phase == .intro else { return }
        withAnimation { logoVisible = true }
        withAnimation(.easeOut(duration: 0.72)) { logoBlurRadius = 0 }

        // Trigger one-time logo bar animation
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, phase == .intro else { return }
        logoAnimated = true

        // "Welcome to" label — Cards tier (80ms)
        try? await Task.sleep(for: .milliseconds(340))
        guard !Task.isCancelled, phase == .intro else { return }
        withAnimation(.easeOut(duration: 0.46)) { welcomeVisible = true }

        // Brand letters — staggered, Text tier (120ms each)
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled, phase == .intro else { return }
        for count in 1...titleText.count {
            try? await Task.sleep(for: .milliseconds(68))
            guard !Task.isCancelled, phase == .intro else { return }
            typedCount = count
        }

        // Tagline — fades upward after title completes
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, phase == .intro else { return }
        withAnimation(.easeOut(duration: 0.44)) { taglineVisible = true }

        // Button — emerges from glass blur last (Buttons: 180ms tier)
        try? await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled, phase == .intro else { return }
        withAnimation(AppMotion.panel()) { buttonVisible = true }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, phase == .intro else { return }
        withAnimation(AppMotion.content()) { introGlowPulse = true }

        try? await Task.sleep(for: .milliseconds(680))
        guard !Task.isCancelled, phase == .intro else { return }
        withAnimation(.easeOut(duration: 0.42)) {
            introGlowPulse = false
            introUnlocked  = true
        }

        // Begin idle alive loop
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled, phase == .intro else { return }
        startButtonIdleLoop()
    }

    private func resetIntroState() {
        logoVisible     = false
        logoBlurRadius  = 8
        typedCount      = 0
        welcomeVisible  = false
        taglineVisible  = false
        buttonVisible   = false
        introGlowPulse  = false
        introUnlocked   = false
        continueHovered = false
        arrowNudge      = 0
        shimmerOffset   = -1
    }

    // MARK: – Shared helpers

    private var thinDividerH: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, textColor.opacity(0.06), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(height: 0.5)
    }
}

// MARK: - MojaveBackdrop

struct MojaveBackdrop: View {
    var opacity: Double = 1
    var body: some View {
        GeometryReader { proxy in
            Image("mojave")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .opacity(opacity)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - MiniMusixLogo
// Accepts `animated` flag — equalizer bars animate once then become static.

enum MiniMusixLogoMode {
    case standard
    case introMark
}

struct MiniMusixLogo: View {
    var size: CGFloat
    var animated: Bool = false
    var mode: MiniMusixLogoMode = .standard

    @State private var barHeights: [CGFloat] = [0.45, 0.72, 0.55, 0.82, 0.60]
    @State private var didAnimate = false

    var body: some View {
        // The animated flag triggers a one-shot equalizer bar animation.
        ZStack {
            if mode == .introMark {
                Circle()
                    .fill(.white.opacity(0.96))
                    .frame(width: size, height: size)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.34), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.20), radius: 18, y: 9)

                Image(systemName: "waveform")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.32).opacity(0.92))
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.42, green: 0.56, blue: 0.82).opacity(0.30),
                                Color(red: 0.17, green: 0.22, blue: 0.32).opacity(0.40)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                    }

                // Equalizer bars — animate once on `animated` → true
                HStack(spacing: size * 0.055) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule()
                            .fill(Color(red: 0.84, green: 0.88, blue: 0.94).opacity(0.88))
                            .frame(width: size * 0.06, height: size * barHeights[i] * 0.50)
                    }
                }
            }
        }
        .onChange(of: animated) { _, newVal in
            guard newVal, !didAnimate else { return }
            didAnimate = true
            animateBarsOnce()
        }
    }

    // Bars animate up/down and settle to static state — one time only
    private func animateBarsOnce() {
        let target: [CGFloat] = [0.80, 0.50, 0.95, 0.60, 0.75]
        let settle: [CGFloat] = [0.45, 0.72, 0.55, 0.82, 0.60]

        withAnimation(AppMotion.control()) {
            barHeights = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.44) {
            withAnimation(AppMotion.panel()) {
                barHeights = settle
            }
        }
    }
}

// MARK: - Progress Bar (alive: glass sweep travels through segment on advance)

struct OnboardingProgressBar: View {
    var currentStep: OnboardingStep
    var furthestStep: OnboardingStep
    var accent: Color
    var textColor: Color
    var secondaryText: Color
    var action: (OnboardingStep) -> Void

    @State private var sweepProgress: [OnboardingStep: CGFloat] = [:]
    @State private var activeFill: CGFloat = 1

    var body: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                let active    = step == currentStep
                let completed = step.rawValue < currentStep.rawValue
                let available = step.rawValue <= furthestStep.rawValue

                Button { action(step) } label: {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: active ? 5.5 : 3.5)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: completed
                                            ? [accent.opacity(0.60), accent.opacity(0.38)]
                                            : [accent.opacity(0.95), accent.opacity(0.76)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geo.size.width * fillAmount(completed: completed, active: active),
                                    height: active ? 5.5 : 3.5
                                )

                            if active, let sweep = sweepProgress[step] {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, .white.opacity(0.38), .clear],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * 0.38)
                                    .offset(x: (geo.size.width + geo.size.width * 0.38) * sweep - geo.size.width * 0.38)
                                    .frame(height: 5.5)
                                    .clipped()
                            }
                        }
                        .frame(height: 8)
                        .scaleEffect(active ? 1.08 : 1, anchor: .center)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!available)
                .accessibilityLabel(step.title)
                .animation(
                    AppMotion.panel(),
                    value: currentStep
                )
            }
        }
        .frame(height: 8)
        .onChange(of: currentStep) { old, new in
            activeFill = 0
            sweepProgress[new] = 0
            withAnimation(AppMotion.primary().delay(0.16)) {
                activeFill = 1
            }
            withAnimation(.easeInOut(duration: 0.92).delay(0.24)) {
                sweepProgress[new] = 1
            }
        }
        .onAppear {
            activeFill = 0
            sweepProgress[currentStep] = 0
            withAnimation(AppMotion.primary().delay(0.28)) {
                activeFill = 1
            }
            withAnimation(.easeInOut(duration: 0.92).delay(0.42)) {
                sweepProgress[currentStep] = 1
            }
        }
    }

    private func fillAmount(completed: Bool, active: Bool) -> CGFloat {
        if completed { return 1 }
        if active { return activeFill }
        return 0
    }
}

private extension MiniPlayerMode {
    var icon: String {
        switch self {
        case .compact: "rectangle.compress.vertical"
        case .expanded: "rectangle.expand.vertical"
        case .lyricsFocus: "quote.bubble"
        }
    }

    var description: String {
        switch self {
        case .compact: "Small and quiet."
        case .expanded: "Artwork, controls, and rhythm."
        case .lyricsFocus: "Built around synced lyrics."
        }
    }
}

struct MinimalQuestionLayout<Content: View>: View {
    var words: [String]
    var textColor: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 34) {
            AnimatedStackedWords(words: words, color: textColor, fontSize: 34)
                .frame(width: 190, alignment: .leading)

            content
                .frame(width: 278, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AnimatedStackedWords: View {
    var words: [String]
    var color: Color
    var fontSize: CGFloat
    @State private var visibleCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(color)
                    .opacity(index < visibleCount ? 1 : 0)
                    .offset(y: index < visibleCount ? 0 : 12)
                    .blur(radius: index < visibleCount ? 0 : 4)
                    .animation(AppMotion.panel().delay(Double(index) * 0.08), value: visibleCount)
            }
        }
        .task {
            visibleCount = 0
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            visibleCount = words.count
        }
    }
}

struct MinimalOptionButton: View {
    var title: String
    var subtitle: String
    var icon: String
    var selected: Bool
    var accent: Color
    var textColor: Color
    var secondaryText: Color
    var delay: Double
    var action: () -> Void

    @State private var visible = false
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? textColor : secondaryText.opacity(0.78))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textColor)
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(secondaryText.opacity(0.70))
                        .lineLimit(1)
                }

                Spacer()

                MinimalCheckmark(selected: selected, accent: accent, textColor: textColor)
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(selected ? accent.opacity(0.28) : Color.white.opacity(hovered ? 0.08 : 0.035), in: Capsule())
            .scaleEffect(hovered ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .offset(x: visible ? 0 : 18)
        .blur(radius: visible ? 0 : 4)
        .onHover { hovered = $0 }
        .animation(AppMotion.control(), value: hovered)
        .animation(AppMotion.panel(), value: selected)
        .task {
            visible = false
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000) + 160))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.panel()) {
                visible = true
            }
        }
    }
}

struct MinimalCheckboxRow: View {
    var title: String
    var icon: String
    @Binding var isOn: Bool
    var accent: Color
    var textColor: Color
    var secondaryText: Color
    var delay: Double

    @State private var visible = false

    var body: some View {
        Button {
            withAnimation(AppMotion.control()) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOn ? textColor : secondaryText.opacity(0.72))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(textColor)

                Spacer()

                MinimalCheckmark(selected: isOn, accent: accent, textColor: textColor)
            }
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 12)
        .task {
            visible = false
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000) + 180))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.panel()) {
                visible = true
            }
        }
    }
}

struct MinimalCheckmark: View {
    var selected: Bool
    var accent: Color
    var textColor: Color

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? accent.opacity(0.0) : textColor.opacity(0.24), lineWidth: 1.1)
                .background(Circle().fill(selected ? accent.opacity(0.70) : .clear))
                .frame(width: 22, height: 22)

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(textColor)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
    }
}

struct MinimalSliderRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var accent: Color
    var textColor: Color
    var secondaryText: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryText.opacity(0.78))
                Spacer()
                Text("\(Int(value / range.upperBound * 100))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(textColor.opacity(0.82))
            }

            GeometryReader { proxy in
                let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(textColor.opacity(0.12)).frame(height: 4)
                    Capsule().fill(accent.opacity(0.75)).frame(width: max(6, proxy.size.width * fraction), height: 4)
                    Circle()
                        .fill(textColor)
                        .frame(width: 16, height: 16)
                        .offset(x: max(0, proxy.size.width * fraction - 8))
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    let t = min(max(gesture.location.x / max(proxy.size.width, 1), 0), 1)
                    value = range.lowerBound + t * (range.upperBound - range.lowerBound)
                })
            }
            .frame(height: 18)
        }
    }
}

struct MinimalChip: View {
    var label: String
    var selected: Bool
    var accent: Color
    var textColor: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(selected ? accent.opacity(0.60) : textColor.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct AnimatedLyricQuestion: View {
    var text: String
    var accent: Color
    var textColor: Color
    var secondaryText: Color
    @State private var highlightedCount = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(index < highlightedCount ? textColor : secondaryText.opacity(0.36))
                    .scaleEffect(index == highlightedCount - 1 ? 1.05 : 1)
            }
        }
        .lineLimit(2)
        .task {
            highlightedCount = 0
            for index in 0...text.count {
                try? await Task.sleep(for: .milliseconds(26))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    highlightedCount = index
                }
            }
        }
    }
}

struct PermissionBubble: View {
    var appName: String
    var icon: String
    var appPath: String? = nil
    var reason: String
    var accent: Color
    var textColor: Color
    var secondaryText: Color
    var delay: Double
    var action: () -> Void

    @State private var visible = false
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                permissionIcon
                    .frame(width: 54, height: 54)
                    .background(accent.opacity(0.26), in: Circle())

                Text(appName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(textColor)

                Text(reason)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(secondaryText.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(height: 42)
            }
            .frame(width: 116)
            .scaleEffect(AppMotion.hoverScale(hovered, amount: 1.025))
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 18)
        .blur(radius: visible ? 0 : 4)
        .onHover { hovered = $0 }
        .animation(AppMotion.control(), value: hovered)
        .task {
            visible = false
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000) + 220))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.panel()) {
                visible = true
            }
        }
    }

    @ViewBuilder
    private var permissionIcon: some View {
        if let appPath, FileManager.default.fileExists(atPath: appPath) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
        } else {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(textColor)
        }
    }
}

// MARK: ──────────────────────────────────────────────────────────────────────
// MARK: Step 1 – Style
// MARK: ──────────────────────────────────────────────────────────────────────

struct Step1StylePanel: View {
    @Binding var selection: MiniPlayerMode
    var accent: Color
    var textColor: Color
    var secondaryText: Color

    var body: some View {
        MinimalQuestionLayout(words: ["Choose,", "your", "view."], textColor: textColor) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(MiniPlayerMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    MinimalOptionButton(
                        title: mode.rawValue,
                        subtitle: mode.description,
                        icon: mode.icon,
                        selected: selection == mode,
                        accent: accent,
                        textColor: textColor,
                        secondaryText: secondaryText,
                        delay: Double(index) * 0.08
                    ) {
                        withAnimation(AppMotion.panel()) {
                            selection = mode
                        }
                    }
                }
            }
        }
    }
}

// MARK: ──────────────────────────────────────────────────────────────────────
// MARK: Step 2 – Appearance
// MARK: ──────────────────────────────────────────────────────────────────────

struct Step2AppearancePanel: View {
    @Binding var settings: OnboardingSettings
    var accent: Color
    var secondaryAccent: Color
    var textColor: Color
    var secondaryText: Color

    var body: some View {
        MinimalQuestionLayout(words: ["Tune", "the", "surface."], textColor: textColor) {
            VStack(alignment: .leading, spacing: 14) {
                MinimalCheckboxRow(
                    title: "Album tint",
                    icon: "paintpalette.fill",
                    isOn: Binding(get: { settings.albumTint > 0.01 }, set: { settings.albumTint = $0 ? 0.10 : 0 }),
                    accent: accent,
                    textColor: textColor,
                    secondaryText: secondaryText,
                    delay: 0
                )
                if settings.albumTint > 0.01 {
                    MinimalSliderRow(
                        title: "Tint strength",
                        value: $settings.albumTint,
                        range: 0.02...0.20,
                        accent: accent,
                        textColor: textColor,
                        secondaryText: secondaryText
                    )
                    .transition(AppMotion.subtleInsertion)
                }

                MinimalCheckboxRow(title: "Artwork glow", icon: "sun.max.fill", isOn: $settings.artworkGlow, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.08)
                MinimalCheckboxRow(title: "Gradient bar", icon: "sparkle", isOn: $settings.barGradient, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.16)
                MinimalSliderRow(title: "Glass intensity", value: $settings.glassIntensity, range: 0.25...1.0, accent: accent, textColor: textColor, secondaryText: secondaryText)
                HStack(spacing: 8) {
                    ForEach(OnboardingGlassStyle.allCases) { style in
                        MinimalChip(label: style.rawValue, selected: settings.glassStyle == style, accent: accent, textColor: textColor) {
                            withAnimation(AppMotion.control()) {
                                settings.glassStyle = style
                            }
                        }
                    }
                }
            }
        }
        .animation(AppMotion.panel(), value: settings.albumTint > 0.01)
    }
}

// MARK: ──────────────────────────────────────────────────────────────────────
// MARK: Step 3 – Behavior
// MARK: ──────────────────────────────────────────────────────────────────────

struct Step3BehaviorPanel: View {
    @Binding var settings: OnboardingSettings
    var accent: Color
    var textColor: Color
    var secondaryText: Color

    var body: some View {
        MinimalQuestionLayout(words: ["How", "should", "it", "behave?"], textColor: textColor) {
            VStack(alignment: .leading, spacing: 14) {
                MinimalCheckboxRow(title: "Float above apps", icon: "pin.fill", isOn: $settings.floatAbove, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0)
                MinimalCheckboxRow(title: "Hide when idle", icon: "eye.slash", isOn: $settings.hideOnStop, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.07)
                MinimalCheckboxRow(title: "Show audio output", icon: "airplayaudio", isOn: $settings.showQueueButton, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.14)
                MinimalCheckboxRow(title: "Show lyrics", icon: "quote.bubble", isOn: $settings.showLyricsButton, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.21)
                MinimalCheckboxRow(title: "Ambient Mode", icon: "square.on.square.dashed", isOn: $settings.ambientModeEnabled, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.28)
                MinimalCheckboxRow(title: "Launch at login", icon: "sunrise", isOn: $settings.launchAtLogin, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.35)
            }
        }
    }
}

// MARK: ──────────────────────────────────────────────────────────────────────
// MARK: Step 4 – Lyrics
// MARK: ──────────────────────────────────────────────────────────────────────

struct Step4LyricsPanel: View {
    @Binding var settings: OnboardingSettings
    var accent: Color
    var textColor: Color
    var secondaryText: Color

    var body: some View {
        MinimalQuestionLayout(words: ["Want", "the", "words?"], textColor: textColor) {
            VStack(alignment: .leading, spacing: 20) {
                AnimatedLyricQuestion(text: "Lyrics that move with the music.", accent: accent, textColor: textColor, secondaryText: secondaryText)

                VStack(alignment: .leading, spacing: 14) {
                    MinimalCheckboxRow(title: "Find lyrics online", icon: "quote.bubble.fill", isOn: $settings.lyricsEnabled, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.18)
                    if settings.lyricsEnabled {
                        MinimalCheckboxRow(title: "Line-by-line lyrics", icon: "text.line.first.and.arrowtriangle.forward", isOn: $settings.preferSynced, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.26)
                        MinimalCheckboxRow(title: "Regular lyrics fallback", icon: "text.alignleft", isOn: $settings.plainFallback, accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.34)
                            .transition(AppMotion.subtleInsertion)
                    }
                }
            }
        }
        .animation(AppMotion.panel(), value: settings.lyricsEnabled)
    }
}

// MARK: ──────────────────────────────────────────────────────────────────────
// MARK: Step 5 – Permissions
// MARK: ──────────────────────────────────────────────────────────────────────

struct Step5PermissionsPanel: View {
    @ObservedObject var store: NowPlayingStore
    var launchAtLogin: Bool
    var accent: Color
    var textColor: Color
    var secondaryText: Color
    @State private var didAutoRequest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("And one more thing...")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .offset(y: 8)))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], alignment: .leading, spacing: 16) {
                PermissionBubble(appName: "Music", icon: "music.note", appPath: "/System/Applications/Music.app", reason: "Automation for playback controls.", accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0) {
                    store.requestAutomationPermission()
                }
                PermissionBubble(appName: "Spotify", icon: "music.note.list", appPath: "/Applications/Spotify.app", reason: "Automation when Spotify is active.", accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.08) {
                    store.requestAutomationPermission()
                }
                PermissionBubble(appName: "Automation", icon: "gearshape", appPath: "/System/Applications/System Settings.app", reason: "Manage app control access.", accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.16) {
                    store.openAutomationPrivacySettings()
                }
                PermissionBubble(appName: "Bluetooth", icon: "airplayaudio", appPath: "/System/Applications/System Settings.app", reason: "Discover nearby audio outputs.", accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.24) {
                    store.requestBluetoothPermission()
                }
                PermissionBubble(appName: "LRCLIB", icon: "text.quote", reason: "Network access for lyric lookup.", accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.32) { }
                PermissionBubble(appName: "Login Items", icon: "sunrise", appPath: "/System/Applications/System Settings.app", reason: "Start MiniMusix at login.", accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.40) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                PermissionBubble(appName: "Accessibility", icon: "accessibility", appPath: "/System/Applications/System Settings.app", reason: "Optional global shortcuts.", accent: accent, textColor: textColor, secondaryText: secondaryText, delay: 0.48) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .task {
            guard !didAutoRequest else { return }
            didAutoRequest = true
            store.requestOnboardingPlaybackPermissions()
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled else { return }
            store.requestBluetoothPermission()
        }
    }
}

// MARK: ──────────────────────────────────────────────────────────────────────
// MARK: Step 6 – Completion
// MARK: ──────────────────────────────────────────────────────────────────────

struct Step6FinalPanel: View {
    var settings: OnboardingSettings
    var accent: Color
    var textColor: Color
    var secondaryText: Color
    var completionDidStart: () -> Void = { }

    @State private var checkVisible = false
    @State private var checkComplete = false
    @State private var messageVisible = false
    @State private var glowPulse = false

    var body: some View {
        VStack(spacing: 18) {
            completionCheck
                .offset(y: messageVisible ? 0 : 18)

            if messageVisible {
                Text("You're all set")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(textColor)
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.92))
                            .combined(with: .offset(y: 10))
                    )
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 222)
        .task {
            checkVisible = false
            checkComplete = false
            messageVisible = false
            glowPulse = false

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.panel()) {
                checkVisible = true
            }

            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.control()) {
                checkComplete = true
            }
            completionDidStart()
            withAnimation(.easeInOut(duration: 0.92).repeatCount(2, autoreverses: true)) {
                glowPulse = true
            }

            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.panel()) {
                messageVisible = true
            }
        }
    }

    private var completionCheck: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.20))
                .frame(width: 86, height: 86)
                .background(.ultraThinMaterial, in: Circle())
                .scaleEffect(checkVisible ? 1 : 0.70)
                .shadow(color: textColor.opacity(glowPulse ? 0.24 : 0.08), radius: glowPulse ? 28 : 10)

            Circle()
                .trim(from: 0, to: checkVisible ? 1 : 0)
                .stroke(
                    textColor.opacity(0.34),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 86, height: 86)

            Path { path in
                path.move(to: CGPoint(x: 29, y: 45))
                path.addLine(to: CGPoint(x: 39, y: 55))
                path.addLine(to: CGPoint(x: 59, y: 33))
            }
            .trim(from: 0, to: checkComplete ? 1 : 0)
            .stroke(
                textColor,
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 86, height: 86)
            .shadow(color: textColor.opacity(checkComplete ? 0.18 : 0), radius: 12)
        }
        .scaleEffect(checkComplete ? 1 : 0.94)
    }
}

// MARK: ──────────────────────────────────────────────────────────────────────
// MARK: Shared Atoms
// MARK: ──────────────────────────────────────────────────────────────────────

struct ModeChip: View {
    var label: String
    var selected: Bool
    var accent: Color
    var textColor: Color
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(selected ? .white : textColor.opacity(0.68))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    Capsule().fill(selected
                                   ? LinearGradient(colors: [accent, accent.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                   : LinearGradient(colors: [Color.white.opacity(hovered ? 0.10 : 0.06), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                )
                .overlay {
                    Capsule().strokeBorder(
                        selected ? .white.opacity(0.20) : Color.white.opacity(hovered ? 0.14 : 0.08),
                        lineWidth: 0.7
                    )
                }
                .shadow(color: selected ? accent.opacity(0.22) : .clear, radius: 6, y: 3)
                .scaleEffect(AppMotion.hoverScale(hovered, amount: 1.025))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(AppMotion.control(), value: hovered)
        .animation(AppMotion.panel(), value: selected)
    }
}

struct OnboardingSegmentedControl<Option: Hashable>: View {
    var title: String
    @Binding var selection: Option
    var options: [Option]
    var label: (Option) -> String
    var accent: Color
    var textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(textColor)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let sel = option == selection
                    Button {
                        withAnimation(AppMotion.panel()) { selection = option }
                    } label: {
                        Text(label(option))
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(sel ? .white : textColor.opacity(0.72))
                    .background(
                        sel ? AnyShapeStyle(accent.opacity(0.80)) : AnyShapeStyle(Color.white.opacity(0.06)),
                        in: Capsule()
                    )
                    .overlay { Capsule().strokeBorder(Color.white.opacity(sel ? 0.20 : 0.08), lineWidth: 0.7) }
                }
            }
        }
    }
}
