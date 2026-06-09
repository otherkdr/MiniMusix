import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    var alwaysOnTop: Bool
    var hiddenFromCapture: Bool
    var size: CGSize
    var isOnboarding: Bool
    var isAmbient: Bool = false
    var hiddenForLockscreen: Bool
    var frameDidChange: (NSRect) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window, coordinator: context.coordinator)
        }
    }

    private func configure(window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.title = "MiniMusix"
        window.isMovableByWindowBackground = !isOnboarding && !isAmbient
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = isAmbient
        window.backgroundColor = isAmbient ? .black : .clear
        window.hasShadow = isOnboarding && !isAmbient
        window.alphaValue = hiddenForLockscreen ? 0 : 1
        window.ignoresMouseEvents = hiddenForLockscreen
        window.level = windowLevel
        window.collectionBehavior.insert([.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .transient, .ignoresCycle])

        if !isOnboarding {
            clearWindowChrome(window)
        }

        if isOnboarding {
            window.styleMask = [.borderless]
            hideStandardWindowButtons(window)
            clearWindowChrome(window)
        } else {
            window.styleMask = [.borderless]
            hideStandardWindowButtons(window)
        }

        if isAmbient {
            makeAmbientWindowOpaque(window)
        }

        if hiddenFromCapture {
            window.sharingType = .none
        } else {
            window.sharingType = .readOnly
        }

        placeWindowIfNeeded(window, coordinator: coordinator)
    }

    private func placeWindowIfNeeded(_ window: NSWindow, coordinator: Coordinator) {
        let onboardingChanged = coordinator.lastIsOnboarding != isOnboarding
        let ambientChanged = coordinator.lastIsAmbient != isAmbient
        let sizeChanged = coordinator.lastSize != size
        let needsInitialPlacement = !coordinator.didPlaceWindow

        guard needsInitialPlacement || onboardingChanged || ambientChanged || sizeChanged else { return }

        guard let screen = window.screen ?? NSScreen.main else { return }
        let frame: NSRect
        if isAmbient {
            frame = screen.frame
        } else {
            let visible = screen.visibleFrame
            let origin = CGPoint(
                x: visible.midX - size.width / 2,
                y: isOnboarding ? visible.midY - size.height / 2 : visible.minY + 28
            )
            frame = NSRect(origin: origin, size: size)
        }

        applyFrame(
            frame,
            to: window,
            animated: shouldAnimateFrameChange(
                needsInitialPlacement: needsInitialPlacement,
                onboardingChanged: onboardingChanged,
                ambientChanged: ambientChanged,
                sizeChanged: sizeChanged
            )
        )
        coordinator.didPlaceWindow = true
        coordinator.lastSize = size
        coordinator.lastIsOnboarding = isOnboarding
        coordinator.lastIsAmbient = isAmbient

        if !hiddenForLockscreen {
            frameDidChange(frame)
        }
    }

    private func shouldAnimateFrameChange(
        needsInitialPlacement: Bool,
        onboardingChanged: Bool,
        ambientChanged: Bool,
        sizeChanged: Bool
    ) -> Bool {
        guard !hiddenForLockscreen else { return false }
        if needsInitialPlacement { return false }
        if onboardingChanged { return true }
        if sizeChanged && !isOnboarding { return true }
        return ambientChanged && !isOnboarding
    }

    private func applyFrame(_ frame: NSRect, to window: NSWindow, animated: Bool) {
        guard !framesAreEquivalent(window.frame, frame) else { return }

        guard animated else {
            window.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.92, 0.22, 1)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
        }
    }

    private func framesAreEquivalent(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
        && abs(lhs.origin.y - rhs.origin.y) < 0.5
        && abs(lhs.size.width - rhs.size.width) < 0.5
        && abs(lhs.size.height - rhs.size.height) < 0.5
    }

    private func clearWindowChrome(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.isOpaque = false

        if let frameView = contentView.superview {
            frameView.wantsLayer = true
            frameView.layer?.backgroundColor = NSColor.clear.cgColor
            frameView.layer?.borderWidth = 0
            frameView.layer?.isOpaque = false
        }
    }

    private func makeAmbientWindowOpaque(_ window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = .black

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        contentView.layer?.isOpaque = true

        if let frameView = contentView.superview {
            frameView.wantsLayer = true
            frameView.layer?.backgroundColor = NSColor.black.cgColor
            frameView.layer?.isOpaque = true
        }
    }

    private func hideStandardWindowButtons(_ window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private var windowLevel: NSWindow.Level {
        if isOnboarding {
            return .normal
        }

        if isAmbient {
            return .normal
        }

        return alwaysOnTop ? .floating : .normal
    }

    final class Coordinator {
        var didPlaceWindow = false
        var lastSize: CGSize?
        var lastIsOnboarding: Bool?
        var lastIsAmbient: Bool?
    }
}

struct HiddenTrafficLightConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

struct BorderlessWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }

        window.styleMask = [.borderless]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.borderWidth = 0
        contentView.layer?.isOpaque = false

        if let frameView = contentView.superview {
            frameView.wantsLayer = true
            frameView.layer?.backgroundColor = NSColor.clear.cgColor
            frameView.layer?.borderWidth = 0
            frameView.layer?.isOpaque = false
        }
    }
}
