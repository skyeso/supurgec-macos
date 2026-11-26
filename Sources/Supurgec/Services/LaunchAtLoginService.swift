import Foundation
import ServiceManagement

enum LaunchAtLoginService {
    static let legacyPlistURL: URL = FileUtils.library
        .appendingPathComponent("LaunchAgents")
        .appendingPathComponent("com.eso.supurgec.menubar.plist")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Eski ~/Library/LaunchAgents dosyasını (siyah terminal ikonu çıkaran kaydı) temizler.
    static func removeLegacyPlistIfPresent() {
        if FileManager.default.fileExists(atPath: legacyPlistURL.path) {
            let uid = getuid()
            _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", legacyPlistURL.path])
            try? FileManager.default.removeItem(at: legacyPlistURL)
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        removeLegacyPlistIfPresent()
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            return false
        }
    }
}
