import Foundation
import Combine
import AppKit
import CoreGraphics
import IOKit.graphics
import IOKit.hid
import IOKit.hidsystem

enum DisplayBrightnessDirection {
    case unchanged
    case up
    case down
}

@MainActor
final class DisplayBrightnessMonitor: NSObject, ObservableObject {
    @Published private(set) var level: Double = 0
    @Published private(set) var direction: DisplayBrightnessDirection = .unchanged
    @Published private(set) var isVisible = false
    @Published private(set) var isSandboxBlocked = false
    @Published private(set) var lastSource = "Starting"

    private var pollTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var hidManager: IOHIDManager?
    private var brightnessNotificationObserver: BrightnessDistributedObserver?
    private var hasBaseline = false

    override init() {
        super.init()
    }

    static func diagnosticsReport() -> String {
        let eventAccessGranted = CGPreflightListenEventAccess()
        let directBrightness = mainDisplayBrightness()
        let notifications = brightnessNotificationNames.map(\.rawValue).joined(separator: ", ")

        return [
            "Brightness Monitor",
            "- Backend: IODisplay brightness, system-defined key events, HID consumer controls, listen-only event tap, distributed brightness notifications",
            "- Listen event access granted: \(eventAccessGranted)",
            "- Direct display brightness read: \(directBrightness.map { String(format: "%.3f", $0) } ?? "unavailable")",
            "- Distributed notifications: \(notifications)",
            "- Fallback behavior: estimates level on brightness key events when the display does not expose an IODisplay brightness value"
        ].joined(separator: "\n")
    }

    func startMonitoring() {
        guard pollTask == nil else { return }
        isSandboxBlocked = false
        refresh(revealingChange: false)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                await MainActor.run {
                    self?.refresh(revealingChange: true)
                }
            }
        }
        addBrightnessKeyMonitors()
        addBrightnessNotifications()
        startBrightnessEventTap()
        startHIDMonitoring()
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        removeBrightnessKeyMonitors()
        removeBrightnessNotifications()
        stopBrightnessEventTap()
        stopHIDMonitoring()
        hideTask?.cancel()
        isVisible = false
    }

    private func refresh(revealingChange: Bool) {
        guard let nextLevel = Self.mainDisplayBrightness() else {
            if !hasBaseline {
                level = 0.5
                lastSource = "Fallback baseline"
            }
            hasBaseline = true
            return
        }
        let previousLevel = level
        level = nextLevel
        lastSource = revealingChange ? "Display polling" : "Initial display read"

        let changed = abs(nextLevel - previousLevel) > 0.012
        guard revealingChange, hasBaseline, changed else {
            hasBaseline = true
            return
        }

        direction = nextLevel > previousLevel ? .up : .down
        revealTemporarily()
    }

    private func addBrightnessKeyMonitors() {
        guard localEventMonitor == nil, globalEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleSystemDefinedEvent(event, source: "Local NSEvent brightness key")
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleSystemDefinedEvent(event, source: "Global NSEvent brightness key")
        }
    }

    private func startHIDMonitoring() {
        guard hidManager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matches: [[String: Int]] = [
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
                kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
                kIOHIDDeviceUsageKey: kHIDUsage_Csmr_DisplayBrightness
            ]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let monitor = Unmanaged<DisplayBrightnessMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.handleHIDValue(value)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            return
        }

        hidManager = manager
    }

    private func startBrightnessEventTap() {
        guard eventTap == nil else { return }
        guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else { return }

        let systemDefinedEventType = CGEventType(rawValue: UInt32(NX_SYSDEFINED))!
        let mask = CGEventMask(1 << systemDefinedEventType.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard type.rawValue == UInt32(NX_SYSDEFINED), let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<DisplayBrightnessMonitor>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    monitor.handleSystemDefinedCGEvent(event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func addBrightnessNotifications() {
        guard brightnessNotificationObserver == nil else { return }
        let observer = BrightnessDistributedObserver { [weak self] notification in
            Task { @MainActor in
                self?.handleBrightnessNotification(notification)
            }
        }
        brightnessNotificationObserver = observer

        for name in Self.brightnessNotificationNames {
            DistributedNotificationCenter.default().addObserver(
                observer,
                selector: #selector(BrightnessDistributedObserver.handle(_:)),
                name: name,
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
    }

    private func removeBrightnessNotifications() {
        guard let observer = brightnessNotificationObserver else { return }
        for name in Self.brightnessNotificationNames {
            DistributedNotificationCenter.default().removeObserver(
                observer,
                name: name,
                object: nil
            )
        }
        brightnessNotificationObserver = nil
    }

    private func stopBrightnessEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil
    }

    private func stopHIDMonitoring() {
        guard let hidManager else { return }
        IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = nil
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        guard IOHIDValueGetIntegerValue(value) != 0 else { return }
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_Consumer) else { return }

        switch IOHIDElementGetUsage(element) {
        case UInt32(kHIDUsage_Csmr_DisplayBrightnessIncrement):
            brightnessKeyDidChange(.up, source: "HID brightness key")
        case UInt32(kHIDUsage_Csmr_DisplayBrightnessDecrement):
            brightnessKeyDidChange(.down, source: "HID brightness key")
        default:
            break
        }
    }

    private func removeBrightnessKeyMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        localEventMonitor = nil
        globalEventMonitor = nil
    }

    private func handleSystemDefinedEvent(_ event: NSEvent, source: String) {
        guard event.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS else { return }

        let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
        let keyState = Int((event.data1 & 0x0000FF00) >> 8)
        let isKeyDown = keyState == 0x0A

        guard isKeyDown else { return }

        switch keyCode {
        case Int(NX_KEYTYPE_BRIGHTNESS_UP):
            brightnessKeyDidChange(.up, source: source)
        case Int(NX_KEYTYPE_BRIGHTNESS_DOWN):
            brightnessKeyDidChange(.down, source: source)
        default:
            break
        }
    }

    private func handleSystemDefinedCGEvent(_ event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event) else { return }
        handleSystemDefinedEvent(nsEvent, source: "CGEvent tap brightness key")
    }

    private func handleBrightnessNotification(_ notification: Notification) {
        let previousLevel = level
        lastSource = "Distributed notification \(notification.name.rawValue)"

        if let notifiedLevel = Self.brightnessLevel(from: notification.userInfo) {
            level = notifiedLevel
            if abs(notifiedLevel - previousLevel) > 0.012 {
                direction = notifiedLevel > previousLevel ? .up : .down
            } else {
                direction = .unchanged
            }
        } else if let nextLevel = Self.mainDisplayBrightness() {
            level = nextLevel
            if abs(nextLevel - previousLevel) > 0.012 {
                direction = nextLevel > previousLevel ? .up : .down
            } else {
                direction = .unchanged
            }
        } else {
            direction = .unchanged
        }

        hasBaseline = true
        revealTemporarily()
    }

    private func brightnessKeyDidChange(_ nextDirection: DisplayBrightnessDirection, source: String) {
        direction = nextDirection
        lastSource = source
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            await MainActor.run {
                guard let self else { return }
                if let nextLevel = Self.mainDisplayBrightness() {
                    self.level = nextLevel
                    self.hasBaseline = true
                    self.lastSource = "\(source) + display read"
                } else {
                    self.level = self.estimatedLevel(after: nextDirection)
                    self.lastSource = "\(source) + estimated level"
                }
                self.revealTemporarily()
            }
        }
    }

    private func estimatedLevel(after nextDirection: DisplayBrightnessDirection) -> Double {
        switch nextDirection {
        case .up:
            return min(level + 0.0625, 1)
        case .down:
            return max(level - 0.0625, 0)
        case .unchanged:
            return level
        }
    }

    private func revealTemporarily() {
        hideTask?.cancel()
        isVisible = true
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.isVisible = false
            }
        }
    }

    private static func mainDisplayBrightness() -> Double? {
        if let mainDisplayBrightness = displayBrightness(for: CGMainDisplayID()) {
            return mainDisplayBrightness
        }

        if let builtInDisplayBrightness = displayBrightness(matching: "AppleBacklightDisplay") {
            return builtInDisplayBrightness
        }

        if let displayConnectBrightness = displayBrightness(matching: "IODisplayConnect") {
            return displayConnectBrightness
        }

        return nil
    }

    private static func displayBrightness(for displayID: CGDirectDisplayID) -> Double? {
        let service = CGDisplayIOServicePort(displayID)
        guard service != 0 else { return nil }

        var brightness: Float = 0
        let status = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        guard status == kIOReturnSuccess else { return nil }
        return min(max(Double(brightness), 0), 1)
    }

    private static func displayBrightness(matching serviceName: String) -> Double? {
        var iterator: io_iterator_t = 0
        let match = IOServiceMatching(serviceName)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            var brightness: Float = 0
            let status = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
            if status == kIOReturnSuccess {
                return min(max(Double(brightness), 0), 1)
            }

            service = IOIteratorNext(iterator)
        }

        return nil
    }

    private static let brightnessNotificationNames: [Notification.Name] = [
        Notification.Name("com.apple.BezelServices.BrightnessChanged"),
        Notification.Name("com.apple.BezelServices.DisplayBrightnessChanged"),
        Notification.Name("com.apple.BezelServices.BMDisplayBrightnessChanged"),
        Notification.Name("com.apple.CoreDisplay.DisplayBrightnessChanged")
    ]

    private static func brightnessLevel(from userInfo: [AnyHashable: Any]?) -> Double? {
        guard let userInfo else { return nil }

        let candidateKeys = [
            "brightness",
            "Brightness",
            "level",
            "Level",
            "value",
            "Value",
            "displayBrightness",
            "DisplayBrightness"
        ]

        for key in candidateKeys {
            if let number = userInfo[key] as? NSNumber {
                return normalizedBrightnessLevel(number.doubleValue)
            }
            if let doubleValue = userInfo[key] as? Double {
                return normalizedBrightnessLevel(doubleValue)
            }
            if let floatValue = userInfo[key] as? Float {
                return normalizedBrightnessLevel(Double(floatValue))
            }
            if let stringValue = userInfo[key] as? String,
               let doubleValue = Double(stringValue) {
                return normalizedBrightnessLevel(doubleValue)
            }
        }

        return nil
    }

    private static func normalizedBrightnessLevel(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        if (0...1).contains(value) {
            return value
        }
        if (0...100).contains(value) {
            return value / 100
        }
        return nil
    }
}

private final class BrightnessDistributedObserver: NSObject {
    private let handler: (Notification) -> Void

    init(handler: @escaping (Notification) -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func handle(_ notification: Notification) {
        handler(notification)
    }
}

@_silgen_name("CGDisplayIOServicePort")
private func CGDisplayIOServicePort(_ displayID: CGDirectDisplayID) -> io_service_t
