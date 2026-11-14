import Foundation
import ServiceManagement

/// Launch at login through `SMAppService`. The checkbox reads the state the system holds,
/// never a stored preference. Yacht established that this works for an ad-hoc-signed bundle.
enum LaunchAtLogin {
    /// A loose `swift run` executable must not register: macOS would launch it through Terminal.
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool { isSupported && SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
