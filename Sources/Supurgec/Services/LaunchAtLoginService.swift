import Foundation

enum LaunchAtLoginService {
    static let label = "com.eso.supurgec.menubar"
    static let bundleID = "com.eso.supurgec"

    static var plistURL: URL {
        FileUtils.library
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static var preferredExecutablePath: String {
        let appsCopy = "/Applications/Süpürgeç.app/Contents/MacOS/Supurgec"
        if FileManager.default.isExecutableFile(atPath: appsCopy) {
            return appsCopy
        }
        return Bundle.main.executablePath ?? appsCopy
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if enabled {
            // AssociatedBundleIdentifiers sayesinde macOS "Oturum Açma Öğeleri" listesinde
            // ayrı bir siyah terminal ikonu ("Supurgec") oluşmaz; tek "Süpürgeç" uygulaması altında görünür!
            let dict: [String: Any] = [
                "Label": label,
                "AssociatedBundleIdentifiers": [bundleID],
                "ProgramArguments": [preferredExecutablePath, "--background"],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            guard let data else { return false }
            do {
                try data.write(to: plistURL, options: .atomic)
                return true
            } catch {
                return false
            }
        } else {
            let uid = getuid()
            _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", plistURL.path])
            do {
                if FileManager.default.fileExists(atPath: plistURL.path) {
                    try FileManager.default.removeItem(at: plistURL)
                }
                return true
            } catch {
                return false
            }
        }
    }
}
