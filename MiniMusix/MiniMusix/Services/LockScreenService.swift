import AppKit
import SwiftUI
import Combine
import CoreGraphics
import os

/// Window levels for appearing on the secure (lock / saver) desktop.
///
/// The lock / screen-saver surface is composited on the screen-saver plane
/// (`NSWindow.Level.screenSaver`, raw value 1000). The lock UI can reorder
/// itself at the same plane after the transition, so the exclusive lockscreen
/// player sits one level above that plane. The regular miniplayer window is
/// intentionally unrelated to this level.
enum LockScreenWindowLevels {
    static var secureSurface: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
    }

    static func level(for context: SecureDisplayContext) -> NSWindow.Level {
        switch context {
        case .inactive:
            return .normal
        case .screenSaver:
            return secureSurface
        case .locked:
            return secureSurface
        }
    }
}

@MainActor
final class LockScreenSurfaceController: ObservableObject {
    private let logger = Logger(subsystem: "MiniMusix", category: "LockScreenSurface")
    private var panel: LockScreenSurfacePanel?
    private var hostingView: NSHostingView<AnyView>?
    private var isPresented = false
    private var hiddenFromCapture = false
    private var currentContext: SecureDisplayContext = .inactive
    private var currentLayout: LockScreenLayout?
    private var postTransitionReassertTask: Task<Void, Never>?

    func sync(
        context: SecureDisplayContext,
        store: NowPlayingStore,
        reduceMotion: Bool
    ) {
        currentContext = context

        if context != .inactive {
            present(context: context, store: store, reduceMotion: reduceMotion)
        } else {
            dismiss()
        }
    }

    func refresh(
        context: SecureDisplayContext,
        store: NowPlayingStore,
        reduceMotion: Bool
    ) {
        currentContext = context
        guard isPresented, context != .inactive else { return }
        updatePanel(context: context, store: store, reduceMotion: reduceMotion, animated: true)
    }

    func dismiss() {
        postTransitionReassertTask?.cancel()
        postTransitionReassertTask = nil
        guard isPresented, let panel else { return }
        isPresented = false
        currentLayout = nil
        logger.debug("LOCK_SURFACE dismissed")
        panel.orderOut(nil)
        self.panel = nil
        hostingView = nil
    }

    private func present(
        context: SecureDisplayContext,
        store: NowPlayingStore,
        reduceMotion: Bool
    ) {
        let panel = panel ?? makePanel(context: context, hiddenFromCapture: store.settings.hideFromScreenCapture)
        self.panel = panel
        self.hiddenFromCapture = store.settings.hideFromScreenCapture

        if panel.sharingType != (hiddenFromCapture ? .none : .readOnly) {
            panel.sharingType = hiddenFromCapture ? .none : .readOnly
        }

        applyWindowLevel(to: panel, context: context)
        updatePanel(context: context, store: store, reduceMotion: reduceMotion, animated: !isPresented)

        if !isPresented {
            isPresented = true
            logger.debug("LOCK_SURFACE presented context=\(String(describing: context), privacy: .public) level=\(panel.level.rawValue, privacy: .public)")
        }

        bringPanelForward(panel, context: context)
        schedulePostTransitionReassert(for: context)
    }

    private func makePanel(context: SecureDisplayContext, hiddenFromCapture: Bool) -> LockScreenSurfacePanel {
        let panel = LockScreenSurfacePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "MiniMusix Lock Surface"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        applyWindowLevel(to: panel, context: context)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.sharingType = hiddenFromCapture ? .none : .readOnly

        return panel
    }

    private func updatePanel(
        context: SecureDisplayContext,
        store: NowPlayingStore,
        reduceMotion: Bool,
        animated: Bool
    ) {
        guard let panel else { return }

        let screenFrame = panel.screen?.frame ?? NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let showsProgress = (store.currentTrack?.identity.duration ?? 0) > 0
        let layout = LockScreenLayout.make(
            screenFrame: screenFrame,
            context: context,
            showsProgress: showsProgress
        )
        currentLayout = layout

        let targetFrame = NSRect(
            x: layout.panelFrame.origin.x,
            y: layout.panelFrame.origin.y,
            width: layout.panelFrame.width,
            height: layout.panelFrame.height
        )
        let rootView = AnyView(
            LockScreenPlayerView(store: store, layout: layout)
                .environment(\.lockScreenLayout, layout)
        )

        if let hostingView {
            hostingView.rootView = rootView
            hostingView.frame = NSRect(origin: .zero, size: layout.contentSize)
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame = NSRect(origin: .zero, size: layout.contentSize)
            hostingView.autoresizingMask = [.width, .height]
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.layer?.isOpaque = false
            panel.contentView = hostingView
            panel.isOpaque = false
            panel.backgroundColor = .clear
            self.hostingView = hostingView
        }

        applyWindowLevel(to: panel, context: context)
        bringPanelForward(panel, context: context)

        logPlacementIfNeeded(layout: layout, screenFrame: screenFrame, context: context)

        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.32
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.alphaValue = 1
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func logPlacementIfNeeded(layout: LockScreenLayout, screenFrame: CGRect, context: SecureDisplayContext) {
        let credentials = LockScreenLayout.loginCredentialsZone(in: screenFrame, context: context)
        let intersects = layout.panelFrame.intersects(credentials.insetBy(dx: -8, dy: -8))
        if intersects {
            logger.warning("LOCK_SURFACE overlaps login credentials zone — frame may need adjustment")
        }
    }

    private func applyWindowLevel(to panel: NSPanel, context: SecureDisplayContext) {
        let target = LockScreenWindowLevels.level(for: context)
        if panel.level != target {
            panel.level = target
        }
    }

    private func bringPanelForward(_ panel: NSPanel, context: SecureDisplayContext) {
        applyWindowLevel(to: panel, context: context)
        panel.orderFrontRegardless()
    }

    /// Loginwindow and the lock surface settle after the lock animation; reassert on the secure surface plane.
    private func schedulePostTransitionReassert(for context: SecureDisplayContext) {
        guard context == .locked else { return }

        postTransitionReassertTask?.cancel()
        postTransitionReassertTask = Task { [weak self] in
            let delays: [Duration] = [
                .milliseconds(120),
                .milliseconds(350),
                .milliseconds(800),
                .seconds(1.5),
                .seconds(3),
                .seconds(5)
            ]
            for delay in delays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, let panel = self.panel else { return }
                guard self.currentContext == .locked, self.isPresented else { return }
                self.bringPanelForward(panel, context: .locked)
                self.logger.debug("LOCK_SURFACE reasserted level=\(panel.level.rawValue, privacy: .public)")
            }
        }
    }
}

final class LockScreenSurfacePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.isOpaque = false
        self.backgroundColor = .clear
    }
}
