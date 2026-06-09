import Foundation
import Security

enum SandboxEnvironment {
    static var isAppSandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.app-sandbox" as CFString,
                nil
              ) else {
            return false
        }

        return (value as? Bool) == true
    }
}
