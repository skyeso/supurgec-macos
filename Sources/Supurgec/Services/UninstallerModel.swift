import AppKit

struct AppInfo: Identifiable, Equatable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let isSystem: Bool
    let isSIPProtected: Bool
    var size: Int64?
    var icon: NSImage?
    var id: String { url.path }

    static func == (a: AppInfo, b: AppInfo) -> Bool { a.id == b.id && a.size == b.size }
}

@MainActor
final class UninstallerModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var loading = false
    @Published var search = ""
    @Published var selectedID: String?
    @Published var leftovers: [JunkItem] = []
    @Published var findingLeftovers = false
    @Published var working = false
    @Published var message: String?

    var filtered: [AppInfo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }
    var selectedApp: AppInfo? { apps.first { $0.id == selectedID } }
    var leftoversSelectedSize: Int64 { leftovers.reduce(0) { $0 + ($1.selected ? $1.size : 0) } }

    func load() async {
        loading = true
        SystemMonitor.shared.beginTask("Kaldırıcı: Uygulamalar taranıyor…")
        let found = await Task.detached(priority: .userInitiated) { Self.findApps() }.value
        apps = found.map { var a = $0; a.icon = NSWorkspace.shared.icon(forFile: a.url.path); return a }
        loading = false
        SystemMonitor.shared.updateTask("Kaldırıcı: Uygulama boyutları hesaplanıyor…")
        for app in apps {
            let url = app.url
            let s = await Task.detached(priority: .utility) { FileUtils.size(of: url) }.value
            if let i = apps.firstIndex(where: { $0.id == app.id }) { apps[i].size = s }
        }
        SystemMonitor.shared.endTask()
    }

    func select(_ app: AppInfo) async {
        selectedID = app.id
        leftovers = []
        findingLeftovers = true
        SystemMonitor.shared.beginTask("\(app.name) kalıntıları aranıyor…")
        let found = await Task.detached(priority: .userInitiated) { Self.findLeftovers(name: app.name, bundleID: app.bundleID) }.value
        SystemMonitor.shared.endTask()
        guard selectedID == app.id else { return }
        leftovers = found
        findingLeftovers = false
    }

    func uninstall(_ app: AppInfo) async {
        if app.isSIPProtected {
            message = "\(app.name) macOS tarafından korunuyor (SIP). Kaldırmak yerine 'Uygulamayı Sıfırla' modunu kullanarak verilerini temizleyebilirsiniz."
            return
        }
        working = true
        SystemMonitor.shared.beginTask("\(app.name) kaldırılıyor…", gpuAnimated: true)
        defer {
            working = false
            SystemMonitor.shared.endTask("✓ \(app.name) kaldırıldı")
        }
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
            running.terminate()
        }
        try? await Task.sleep(for: .milliseconds(800))

        let targets = [app.url] + leftovers.filter(\.selected).map(\.url)
        var failed = await Task.detached { FileUtils.trash(targets) }.value

        if !failed.isEmpty {
            let trashDir = FileUtils.home.appendingPathComponent(".Trash").path
            let cmd = failed.map { "mv -f \(Shell.quote($0.path)) \(Shell.quote(trashDir + "/" + $0.lastPathComponent + "-" + String(Int(Date().timeIntervalSince1970))))" }
                .joined(separator: "; ")
            if Shell.runAsAdmin(cmd).ok { failed = failed.filter { FileUtils.exists($0) } }
        }

        if failed.contains(app.url) {
            message = "\(app.name) kaldırılamadı."
        } else {
            let freed = (app.size ?? 0) + leftoversSelectedSize
            message = "\(app.name) kaldırıldı · \(freed.formattedBytes) Çöp Kutusu'na taşındı."
            apps.removeAll { $0.id == app.id }
            selectedID = nil
            leftovers = []
        }
    }

    // MARK: - Arka plan işleri

    nonisolated static func findApps() -> [AppInfo] {
        // Hem kullanıcı uygulamaları hem de macOS yerleşik Apple uygulamaları (/System/Applications + Cryptexes/Safari)
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            FileUtils.home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications")
        ]
        var seen = Set<String>()
        var result: [AppInfo] = []

        func add(_ u: URL) {
            let resolved = u.resolvingSymlinksInPath().path
            guard u.pathExtension == "app", seen.insert(resolved).inserted else { return }
            let bundle = Bundle(url: u)
            let info = bundle?.infoDictionary ?? [:]
            let bundleID = bundle?.bundleIdentifier ?? ""
            let name = FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
            let version = info["CFBundleShortVersionString"] as? String ?? ""
            let inSystemPath = u.path.hasPrefix("/System/")
            let isApple = inSystemPath || bundleID.hasPrefix("com.apple.")
            result.append(AppInfo(
                url: u,
                name: name,
                bundleID: bundleID,
                version: version,
                isSystem: isApple,
                isSIPProtected: inSystemPath
            ))
        }

        for d in dirs {
            for u in FileUtils.children(of: d) {
                if u.pathExtension == "app" { add(u) }
                else if FileUtils.isDirectory(u) && u.lastPathComponent != "Utilities" {
                    FileUtils.children(of: u).forEach(add)
                }
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func findLeftovers(name: String, bundleID: String) -> [JunkItem] {
        let lib = FileUtils.library
        let subdirs = ["Application Support", "Caches", "Preferences", "Containers", "Group Containers",
                       "Saved Application State", "Logs", "HTTPStorages", "WebKit", "LaunchAgents",
                       "Cookies", "Application Scripts", "Preferences/ByHost"]
        let bid = bundleID.lowercased()
        let lname = name.lowercased()
        var items: [JunkItem] = []
        for sub in subdirs {
            for child in FileUtils.children(of: lib.appendingPathComponent(sub)) {
                let n = child.lastPathComponent.lowercased()
                let stem = (n as NSString).deletingPathExtension
                let byID = bid.count > 4 && (stem == bid || n.hasPrefix(bid + ".") || stem.hasSuffix("." + bid) || n.hasPrefix(bid + "_"))
                let byName = lname.count > 2 && stem == lname
                if byID || byName {
                    items.append(JunkItem(url: child, size: max(FileUtils.size(of: child), 1), selected: true))
                }
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}
