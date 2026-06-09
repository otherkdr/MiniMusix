import Foundation
import Combine
import AppKit
import ApplicationServices
import os

/// Tracks when the Mac is locked, in screen saver, or display-asleep — contexts where the lock surface may appear.
enum SecureDisplayContext: Equatable {
    case inactive
    case screenSaver
    case locked
}

@MainActor
final class LockScreenMonitor: ObservableObject {
    @Published private(set) var context: SecureDisplayContext = .inactive

    var isLockSurfaceActive: Bool {
        context != .inactive
    }

    private let logger = Logger(subsystem: "MiniMusix", category: "LockScreenMonitor")
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var screenSaverRunning = false
    private var displayAsleep = false
    private var sessionLocked = false

    init() {
        recomputeContext(reason: "initial")
        startObserving()
    }

    deinit {
        pollTimer?.invalidate()
    }

    func refreshLockState(reason: String) {
        sessionLocked = Self.queryScreenLocked()
        recomputeContext(reason: reason)
    }

    private func startObserving() {
        let distributed = DistributedNotificationCenter.default()

        distributed.publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.sessionLocked = true
                self?.recomputeContext(reason: "com.apple.screenIsLocked")
            }
            .store(in: &cancellables)

        distributed.publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.sessionLocked = false
                self?.recomputeContext(reason: "com.apple.screenIsUnlocked")
            }
            .store(in: &cancellables)

        distributed.publisher(for: Notification.Name("com.apple.screensaver.didstart"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.screenSaverRunning = true
                self?.recomputeContext(reason: "screensaver.didstart")
            }
            .store(in: &cancellables)

        distributed.publisher(for: Notification.Name("com.apple.screensaver.didstop"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.screenSaverRunning = false
                self?.recomputeContext(reason: "screensaver.didstop")
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.displayAsleep = true
                self?.recomputeContext(reason: "screensDidSleep")
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.displayAsleep = false
                self?.sessionLocked = Self.queryScreenLocked()
                self?.recomputeContext(reason: "screensDidWake")
            }
            .store(in: &cancellables)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sessionLocked = Self.queryScreenLocked()
                self.recomputeContext(reason: "poll")
            }
        }
    }

    private func recomputeContext(reason: String) {
        let next: SecureDisplayContext
        if sessionLocked {
            next = .locked
        } else if screenSaverRunning || displayAsleep {
            next = .screenSaver
        } else {
            next = .inactive
        }

        guard next != context else { return }
        logger.debug("SECURE_DISPLAY context=\(String(describing: next), privacy: .public) reason=\(reason, privacy: .public)")
        context = next
    }

    private static func queryScreenLocked() -> Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }

        if let locked = dictionary["CGSSessionScreenIsLocked"] as? Bool {
            return locked
        }

        if let locked = dictionary["CGSSessionScreenIsLocked"] as? Int {
            return locked != 0
        }

        return false
    }
}
