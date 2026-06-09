import Foundation
import Combine
import AppIntents

@MainActor
final class FocusModeMonitor: NSObject, ObservableObject {
    static let shared = FocusModeMonitor()
    
    @Published private(set) var isVisible = false
    @Published private(set) var isFocused: Bool? = nil
    @Published private(set) var activeFocusName: String? = nil
    @Published private(set) var activeFocusIcon: String? = nil

    private var hideTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var focusEventObserver: FocusModeDistributedObserver?
    private var isObservingFocusEvents = false
    private var lastEventTimestamp: TimeInterval?

    private override init() {
        super.init()
    }

    static func diagnosticsReport() async -> String {
        var lines: [String] = [
            "Focus Monitor",
            "- Backend: AppIntents SetFocusFilterIntent",
            "- Required setup: add the MiniMusix Focus Filter inside macOS Focus settings"
        ]

        do {
            let current = try await AppFocusDetectorIntent.current
            lines.append("- Current system focus filter: active")
            lines.append("- Current focus name: \(current.resolvedFocusName)")
            lines.append("- Current focus icon: \(current.resolvedFocusIcon)")
        } catch SetFocusFilterIntentError.notFound {
            lines.append("- Current system focus filter: inactive or not configured")
        } catch {
            lines.append("- Current system focus filter error: \(String(describing: error))")
        }

        if let storedEvent = FocusModeEventStore.currentEvent {
            lines.append("- Stored bridge state: \(storedEvent.diagnosticsDescription)")
        } else {
            lines.append("- Stored bridge state: none")
        }

        return lines.joined(separator: "\n")
    }

    func startMonitoring() {
        guard !isObservingFocusEvents else {
            refreshFromStoredFocusEvent(reveal: false)
            refreshFromSystemFocusFilter(reveal: false)
            return
        }

        isObservingFocusEvents = true
        let observer = FocusModeDistributedObserver { [weak self] notification in
            Task { @MainActor in
                self?.handleFocusEventDidChange(notification)
            }
        }
        focusEventObserver = observer
        DistributedNotificationCenter.default().addObserver(
            observer,
            selector: #selector(FocusModeDistributedObserver.handle(_:)),
            name: FocusModeEventStore.didChangeNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        refreshFromStoredFocusEvent(reveal: false)
        refreshFromSystemFocusFilter(reveal: false)
        startPollingFallback()
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        hideTask?.cancel()
        isVisible = false
        guard isObservingFocusEvents else { return }
        isObservingFocusEvents = false
        if let focusEventObserver {
            DistributedNotificationCenter.default().removeObserver(
                focusEventObserver,
                name: FocusModeEventStore.didChangeNotification,
                object: nil
            )
        }
        focusEventObserver = nil
    }

    func updateFocusState(name: String, icon: String) {
        isFocused = true
        activeFocusName = name
        activeFocusIcon = icon
        revealTemporarily()
    }
    
    func clearFocusState() {
        isFocused = false
        activeFocusName = nil
        activeFocusIcon = nil
        revealTemporarily()
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

    private func handleFocusEventDidChange(_ notification: Notification) {
        if let event = FocusModeEventStore.event(from: notification.userInfo) {
            apply(event: event, reveal: true)
        } else {
            refreshFromStoredFocusEvent(reveal: true)
        }
    }

    private func refreshFromStoredFocusEvent(reveal: Bool) {
        guard let event = FocusModeEventStore.currentEvent else { return }
        apply(event: event, reveal: reveal)
    }

    private func apply(event: FocusModeEvent, reveal: Bool) {
        let stateChanged = event.isFocused != isFocused ||
            event.name != activeFocusName ||
            event.icon != activeFocusIcon
        guard stateChanged || event.timestamp != lastEventTimestamp else { return }
        lastEventTimestamp = event.timestamp

        if event.isFocused {
            isFocused = true
            activeFocusName = event.name
            activeFocusIcon = event.icon
        } else {
            isFocused = false
            activeFocusName = nil
            activeFocusIcon = nil
        }

        if reveal, stateChanged {
            revealTemporarily()
        }
    }

    private func startPollingFallback() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await self?.refreshFromSystemFocusFilter(reveal: true)
            }
        }
    }

    private func refreshFromSystemFocusFilter(reveal: Bool) {
        Task { [weak self] in
            await self?.refreshFromSystemFocusFilter(reveal: reveal)
        }
    }

    private func refreshFromSystemFocusFilter(reveal: Bool) async {
        do {
            let current = try await AppFocusDetectorIntent.current
            let event = FocusModeEvent(
                isFocused: true,
                name: current.resolvedFocusName,
                icon: current.resolvedFocusIcon,
                timestamp: current.systemContext.preciseTimestamp?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
            )
            await MainActor.run {
                apply(event: event, reveal: reveal)
            }
        } catch SetFocusFilterIntentError.notFound {
            let event = FocusModeEvent(
                isFocused: false,
                name: nil,
                icon: nil,
                timestamp: Date().timeIntervalSince1970
            )
            await MainActor.run {
                apply(event: event, reveal: reveal)
            }
        } catch {
            await MainActor.run {
                refreshFromStoredFocusEvent(reveal: false)
            }
        }
    }
}

private final class FocusModeDistributedObserver: NSObject {
    private let handler: (Notification) -> Void

    init(handler: @escaping (Notification) -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func handle(_ notification: Notification) {
        handler(notification)
    }
}

nonisolated private enum FocusModeEventStore {
    static let didChangeNotification = Notification.Name("MiniMusixFocusModeDidChange")

    private static let focusedKey = "MiniMusix.FocusMode.isFocused"
    private static let nameKey = "MiniMusix.FocusMode.name"
    private static let iconKey = "MiniMusix.FocusMode.icon"
    private static let timestampKey = "MiniMusix.FocusMode.timestamp"

    static var currentEvent: FocusModeEvent? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: timestampKey) != nil else { return nil }
        return FocusModeEvent(
            isFocused: defaults.bool(forKey: focusedKey),
            name: defaults.string(forKey: nameKey),
            icon: defaults.string(forKey: iconKey),
            timestamp: defaults.double(forKey: timestampKey)
        )
    }

    static func storeActive(name: String, icon: String) {
        let event = FocusModeEvent(isFocused: true, name: name, icon: icon, timestamp: Date().timeIntervalSince1970)
        let defaults = UserDefaults.standard
        defaults.set(event.isFocused, forKey: focusedKey)
        defaults.set(event.name, forKey: nameKey)
        defaults.set(event.icon, forKey: iconKey)
        defaults.set(event.timestamp, forKey: timestampKey)
        notifyChange(event)
    }

    static func storeInactive() {
        let event = FocusModeEvent(isFocused: false, name: nil, icon: nil, timestamp: Date().timeIntervalSince1970)
        let defaults = UserDefaults.standard
        defaults.set(event.isFocused, forKey: focusedKey)
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: iconKey)
        defaults.set(event.timestamp, forKey: timestampKey)
        notifyChange(event)
    }

    static func event(from userInfo: [AnyHashable: Any]?) -> FocusModeEvent? {
        guard let userInfo,
              let isFocused = userInfo[focusedKey] as? Bool,
              let timestamp = userInfo[timestampKey] as? TimeInterval else {
            return nil
        }

        return FocusModeEvent(
            isFocused: isFocused,
            name: userInfo[nameKey] as? String,
            icon: userInfo[iconKey] as? String,
            timestamp: timestamp
        )
    }

    private static func notifyChange(_ event: FocusModeEvent) {
        UserDefaults.standard.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            didChangeNotification,
            object: nil,
            userInfo: event.userInfo,
            deliverImmediately: true
        )
    }
}

private struct FocusModeEvent {
    let isFocused: Bool
    let name: String?
    let icon: String?
    let timestamp: TimeInterval

    nonisolated var userInfo: [String: Any] {
        var userInfo: [String: Any] = [
            "MiniMusix.FocusMode.isFocused": isFocused,
            "MiniMusix.FocusMode.timestamp": timestamp
        ]
        if let name {
            userInfo["MiniMusix.FocusMode.name"] = name
        }
        if let icon {
            userInfo["MiniMusix.FocusMode.icon"] = icon
        }
        return userInfo
    }

    nonisolated var diagnosticsDescription: String {
        if isFocused {
            return "active name=\(name ?? "Focus") icon=\(icon ?? "moon.fill") timestamp=\(Date(timeIntervalSince1970: timestamp))"
        }
        return "inactive timestamp=\(Date(timeIntervalSince1970: timestamp))"
    }
}

struct AppFocusDetectorIntent: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Update MiniMusix Focus State"
    static let description = IntentDescription("Updates MiniMusix when a Focus filter turns on or off.")

    @Parameter(title: "Focus Mode Name")
    var focusName: String?

    @Parameter(title: "SF Symbol Icon Name")
    var focusIcon: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(resolvedFocusName) Focus")
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [AppFocusDetectorIntent] {
        var intent = AppFocusDetectorIntent()
        intent.focusName = "Focus"
        intent.focusIcon = "moon.fill"
        return [intent]
    }

    func perform() async throws -> some IntentResult {
        FocusModeEventStore.storeActive(name: resolvedFocusName, icon: resolvedFocusIcon)
        await FocusModeMonitor.shared.updateFocusState(name: resolvedFocusName, icon: resolvedFocusIcon)
        return .result()
    }

    var resolvedFocusName: String {
        guard let focusName, !focusName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Focus"
        }
        return focusName
    }

    var resolvedFocusIcon: String {
        guard let focusIcon, !focusIcon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "moon.fill"
        }
        return focusIcon
    }
}

struct MiniMusixAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AppFocusDetectorIntent(),
            phrases: [
                "Update \(.applicationName) Focus",
                "Set \(.applicationName) Focus"
            ],
            shortTitle: "Focus Filter",
            systemImageName: "moon.fill"
        )
    }
}
