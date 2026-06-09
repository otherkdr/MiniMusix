import AppKit
import ApplicationServices
import Carbon
import Foundation

enum MusicAutomationTarget: String, CaseIterable, Identifiable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var id: String { rawValue }

    var applicationName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
}

enum AppleScriptRunOutcome: Equatable {
    case success
    case needsPermission
    case denied(String)
}

enum AppleScriptAutomation {
    static func permissionState(for target: MusicAutomationTarget, promptIfNeeded: Bool = false) -> BackendPermissionState {
        guard var targetAddress = bundleAddressDesc(for: target.rawValue) else {
            return .unavailable("MiniMusix could not find \(target.applicationName).")
        }
        defer { AEDisposeDesc(&targetAddress) }

        let status = AEDeterminePermissionToAutomateTarget(
            &targetAddress,
            typeWildCard,
            typeWildCard,
            promptIfNeeded
        )

        if status == noErr {
            return .ready
        }
        if status == errAEEventWouldRequireUserConsent {
            return .unknown
        }
        if status == errAEEventNotPermitted {
            return .unavailable("Allow MiniMusix to control \(target.applicationName) in System Settings.")
        }
        if status == procNotFound {
            return .unavailable("Open \(target.applicationName) once, then try again.")
        }
        return .unavailable("MiniMusix cannot control \(target.applicationName) right now.")
    }

    /// Runs a harmless script so macOS shows the Automation consent dialog when needed.
    @discardableResult
    static func requestAccess(for target: MusicAutomationTarget) -> BackendPermissionState {
        _ = permissionState(for: target, promptIfNeeded: true)

        let probe = "tell application \"\(target.applicationName)\" to return name"
        switch run(probe) {
        case .success:
            return .ready
        case .needsPermission:
            return .unknown
        case .denied(let message):
            return .unavailable(message)
        }
    }

    static func requestAccessForPlaybackTargets() {
        for target in MusicAutomationTarget.allCases {
            requestAccess(for: target)
        }
    }

    static func refreshPermissionStates() -> (music: BackendPermissionState, spotify: BackendPermissionState) {
        (permissionState(for: .music, promptIfNeeded: false), permissionState(for: .spotify, promptIfNeeded: false))
    }

    private static func bundleAddressDesc(for bundleIdentifier: String) -> AEAddressDesc? {
        var desc = AEAddressDesc()
        let status = bundleIdentifier.withCString { pointer in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                pointer,
                strlen(pointer),
                &desc
            )
        }
        guard status == noErr else { return nil }
        return desc
    }

    @discardableResult
    static func run(_ source: String) -> AppleScriptRunOutcome {
        guard let script = NSAppleScript(source: source) else {
            return .denied("Could not compile AppleScript.")
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)

        guard let errorInfo else {
            return .success
        }

        let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        let message = (errorInfo[NSAppleScript.errorMessage] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch code {
        case Int(errAEEventWouldRequireUserConsent):
            return .needsPermission
        case Int(errAEEventNotPermitted):
            return .denied(message ?? "MiniMusix is not allowed to control this music app yet.")
        default:
            return .denied(message ?? "AppleScript failed (\(code)).")
        }
    }

    static func playPause(target: MusicAutomationTarget) -> AppleScriptRunOutcome {
        run("tell application \"\(target.applicationName)\" to playpause")
    }

    static func nextTrack(target: MusicAutomationTarget) -> AppleScriptRunOutcome {
        run("tell application \"\(target.applicationName)\" to next track")
    }

    static func previousTrack(target: MusicAutomationTarget) -> AppleScriptRunOutcome {
        run("tell application \"\(target.applicationName)\" to previous track")
    }
}
