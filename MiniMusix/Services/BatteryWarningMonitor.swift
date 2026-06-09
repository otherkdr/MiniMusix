import Foundation
import Combine
import IOKit.ps

@MainActor
final class BatteryWarningMonitor: ObservableObject {
    @Published private(set) var percent: Int = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isVisible = false
    @Published private(set) var isSandboxBlocked = false

    private var thresholdPercent = 20
    private var notificationRunLoopSource: CFRunLoopSource?
    private var pollTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var didWarnForCurrentLowBatteryWindow = false

    func startMonitoring(thresholdPercent: Int) {
        self.thresholdPercent = Self.clampedThreshold(thresholdPercent)
        isSandboxBlocked = false
        refresh(revealingChange: false)
        startPollingFallback()

        guard notificationRunLoopSource == nil else { return }
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryWarningMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.refresh(revealingChange: true)
            }
        }, context)?.takeRetainedValue() else {
            return
        }

        notificationRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        hideTask?.cancel()
        isVisible = false
        if let notificationRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), notificationRunLoopSource, .defaultMode)
        }
        notificationRunLoopSource = nil
        isSandboxBlocked = false
    }

    func updateThreshold(_ thresholdPercent: Int) {
        self.thresholdPercent = Self.clampedThreshold(thresholdPercent)
        refresh(revealingChange: true)
    }

    private func refresh(revealingChange: Bool) {
        guard let state = Self.currentBatteryState() else { return }
        percent = state.percent
        isCharging = state.isCharging

        let shouldWarn = !state.isCharging && state.percent <= thresholdPercent
        if shouldWarn, revealingChange, !didWarnForCurrentLowBatteryWindow {
            didWarnForCurrentLowBatteryWindow = true
            revealTemporarily()
        } else if !shouldWarn {
            didWarnForCurrentLowBatteryWindow = false
        }
    }

    private func startPollingFallback() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await MainActor.run {
                    self?.refresh(revealingChange: true)
                }
            }
        }
    }

    private func revealTemporarily() {
        hideTask?.cancel()
        isVisible = true
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.isVisible = false
            }
        }
    }

    private static func currentBatteryState() -> (percent: Int, isCharging: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let type = description[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else {
                continue
            }

            let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let powerState = description[kIOPSPowerSourceStateKey] as? String
            let isCharging = powerState == kIOPSACPowerValue
            return (Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded()), isCharging)
        }

        return nil
    }

    private static func clampedThreshold(_ percent: Int) -> Int {
        min(max(percent, 5), 50)
    }
}
