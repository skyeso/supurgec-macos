import AppKit

struct LeftoverItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let kind: String
    let requiresAdmin: Bool
    var selected: Bool

    var name: String { url.lastPathComponent }
}

struct AppInfo: Identifiable, Equatable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let privilegedHelpers: [String]
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
    @Published var leftovers: [LeftoverItem] = []
    @Published var findingLeftovers = false
    @Published var working = false
    @Published var permanentDelete = false
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
        SystemMonitor.shared.beginTask("\(app.name) tüm sistem kalıntıları aranıyor…")
        let found = await Task.detached(priority: .userInitiated) {
            Self.findLeftovers(app: app)
        }.value
        SystemMonitor.shared.endTask()
        guard selectedID == app.id else { return }
        leftovers = found
        findingLeftovers = false
    }

    /// Derin Kaldırma: Ana uygulama + alt süreçler + arka plan servisleri + tercih önbelleği + kurulum kayıtları + tüm dosyalar!
    func uninstall(_ app: AppInfo, permanently: Bool) async {
        if app.isSIPProtected {
            message = "\(app.name) macOS tarafından korunuyor (SIP). 'Uygulamayı Sıfırla' moduyla verilerini temizleyebilirsiniz."
            return
        }
        working = true
        SystemMonitor.shared.beginTask("\(app.name) ve tüm kalıntıları kaldırılıyor…", gpuAnimated: true)
        defer {
            working = false
            SystemMonitor.shared.endTask("✓ \(app.name) tamamen kaldırıldı")
        }

        // 1. Açık olan ana uygulamayı ve içindeki tüm yardımcı (Helper) süreçleri tamamen kapat
        await terminateAppAndHelpers(app)

        let selectedLeftovers = leftovers.filter(\.selected)

        // 2. Kullanıcı LaunchAgent servislerini çalışırken durdur (tekrar dosya üretmesin)
        for item in selectedLeftovers where !item.requiresAdmin && item.url.path.contains("/LaunchAgents/") {
            _ = await Task.detached { Shell.run("/bin/launchctl", ["unload", "-w", item.url.path]) }.value
        }

        // 3. macOS cfprefsd RAM tercih önbelleğini temizle (silinen plist geri yazılmasın)
        if !app.bundleID.isEmpty {
            let bid = app.bundleID
            _ = await Task.detached { Shell.run("/usr/bin/defaults", ["delete", bid]) }.value
        }

        // 4. Kullanıcı yetkisiyle silinebilen hedefleri işle
        let allTargets = [app.url] + selectedLeftovers.map(\.url)
        var needAdminURLs: [URL] = []

        if permanently {
            needAdminURLs = await Task.detached { () -> [URL] in
                var failed: [URL] = []
                for u in allTargets {
                    do { try FileManager.default.removeItem(at: u) }
                    catch { failed.append(u) }
                }
                return failed
            }.value
        } else {
            needAdminURLs = await Task.detached { FileUtils.trash(allTargets) }.value
        }

        // 5. Sistem (/Library, LaunchDaemons, PrivilegedHelperTools, Receipts) hedefleri veya root sahipli uygulamalar için tek seferde yönetici komutu
        let receiptPkgIDs = selectedLeftovers
            .filter { $0.url.path.hasPrefix("/private/var/db/receipts/") || $0.url.path.hasPrefix("/var/db/receipts/") }
            .map { ($0.url.lastPathComponent as NSString).deletingPathExtension }

        if !needAdminURLs.isEmpty || !receiptPkgIDs.isEmpty {
            var cmds: [String] = []
            // Sistem LaunchDaemon / LaunchAgent servislerini durdur
            for u in needAdminURLs where u.path.contains("/LaunchDaemons/") || u.path.contains("/LaunchAgents/") {
                cmds.append("/bin/launchctl unload -w \(Shell.quote(u.path)) 2>/dev/null || true")
            }
            if permanently {
                for u in needAdminURLs {
                    cmds.append("/bin/rm -rf \(Shell.quote(u.path))")
                }
            } else {
                let trashDir = FileUtils.home.appendingPathComponent(".Trash").path
                let stamp = Int(Date().timeIntervalSince1970)
                for (idx, u) in needAdminURLs.enumerated() {
                    let dest = "\(trashDir)/\(u.lastPathComponent)-\(stamp)-\(idx)"
                    cmds.append("/bin/mv -f \(Shell.quote(u.path)) \(Shell.quote(dest)) && /usr/sbin/chown \(NSUserName()) \(Shell.quote(dest)) || true")
                }
            }
            for pkg in Set(receiptPkgIDs) where !pkg.isEmpty {
                cmds.append("/usr/sbin/pkgutil --forget \(Shell.quote(pkg)) 2>/dev/null || true")
            }

            if !cmds.isEmpty {
                _ = Shell.runAsAdmin(cmds.joined(separator: "; "))
                needAdminURLs = needAdminURLs.filter { FileUtils.exists($0) }
            }
        }

        if FileUtils.exists(app.url) {
            message = "\(app.name) kaldırılamadı (işlem iptal edildi veya dosya kilitli)."
        } else {
            let freed = (app.size ?? 0) + leftoversSelectedSize
            let actionWord = permanently ? "kalıcı olarak silindi" : "Çöp Kutusu'na taşındı"
            message = "\(app.name) ve \(selectedLeftovers.count) kalıntı parçası (\(freed.formattedBytes)) \(actionWord)."
            apps.removeAll { $0.id == app.id }
            selectedID = nil
            leftovers = []
        }
    }

    /// Uygulamayı silmeden yalnızca ilişkili önbellek ve ayar dosyalarını sıfırlar.
    func resetSelectedLeftovers(for app: AppInfo, permanently: Bool) async {
        let targets = leftovers.filter(\.selected)
        guard !targets.isEmpty else { return }
        working = true
        SystemMonitor.shared.beginTask("\(app.name) verileri sıfırlanıyor…", gpuAnimated: true)
        defer {
            working = false
            SystemMonitor.shared.endTask("✓ \(app.name) sıfırlandı")
        }

        await terminateAppAndHelpers(app)
        if !app.bundleID.isEmpty {
            let bid = app.bundleID
            _ = await Task.detached { Shell.run("/usr/bin/defaults", ["delete", bid]) }.value
        }

        let urls = targets.map(\.url)
        var failed: [URL] = []
        if permanently {
            failed = await Task.detached {
                var f: [URL] = []
                for u in urls {
                    do { try FileManager.default.removeItem(at: u) } catch { f.append(u) }
                }
                return f
            }.value
        } else {
            failed = await Task.detached { FileUtils.trash(urls) }.value
        }

        if !failed.isEmpty {
            let cmds = failed.map { permanently ? "/bin/rm -rf \(Shell.quote($0.path))" : "/bin/rm -rf \(Shell.quote($0.path))" }
            _ = Shell.runAsAdmin(cmds.joined(separator: "; "))
            failed = failed.filter { FileUtils.exists($0) }
        }

        let movedBytes = targets.filter { !failed.contains($0.url) }.reduce(Int64(0)) { $0 + $1.size }
        message = "\(app.name) sıfırlandı · \(movedBytes.formattedBytes) veri temizlendi."
        await select(app)
    }

    private func terminateAppAndHelpers(_ app: AppInfo) async {
        if !app.bundleID.isEmpty {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
                running.terminate()
            }
        }
        let appPathPrefix = app.url.path + "/"
        await Task.detached {
            let out = Shell.run("/bin/ps", ["-axo", "pid=,comm="]).output
            var pids: [Int32] = []
            for line in out.split(separator: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2, let pid = Int32(parts[0]), String(parts[1]).hasPrefix(appPathPrefix) {
                    pids.append(pid)
                    Darwin.kill(pid, SIGTERM)
                }
            }
            if !pids.isEmpty {
                usleep(550_000)
                for pid in pids { Darwin.kill(pid, SIGKILL) }
            }
        }.value
    }

    // MARK: - Uygulama ve Derin Kalıntı Tarayıcısı

    nonisolated static func findApps() -> [AppInfo] {
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
            let rawDisplay = FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
            let version = info["CFBundleShortVersionString"] as? String ?? ""
            let helpers = (info["SMPrivilegedExecutables"] as? [String: Any]).map { Array($0.keys) } ?? []
            let inSystemPath = u.path.hasPrefix("/System/")
            let isApple = inSystemPath || bundleID.hasPrefix("com.apple.")
            result.append(AppInfo(
                url: u,
                name: rawDisplay,
                bundleID: bundleID,
                version: version,
                privilegedHelpers: helpers,
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

    nonisolated static func findLeftovers(app: AppInfo) -> [LeftoverItem] {
        let userLib = FileUtils.library
        let sysLib = URL(fileURLWithPath: "/Library")

        // Taranacak tüm Kullanıcı (~/Library) ve Sistem (/Library + Receipts + Shared) konumları
        let locations: [(url: URL, kind: String, admin: Bool, allowVendorSubscan: Bool)] = [
            // Kullanıcı düzeyi
            (userLib.appendingPathComponent("Application Support"), "Uygulama Verisi", false, true),
            (userLib.appendingPathComponent("Caches"), "Önbellek", false, true),
            (userLib.appendingPathComponent("Preferences"), "Tercih Dosyası", false, false),
            (userLib.appendingPathComponent("Preferences/ByHost"), "Tercih Dosyası", false, false),
            (userLib.appendingPathComponent("Containers"), "Uygulama Kapsayıcısı", false, false),
            (userLib.appendingPathComponent("Group Containers"), "Ortak Grup Kapsayıcısı", false, false),
            (userLib.appendingPathComponent("Saved Application State"), "Pencere Durumu", false, false),
            (userLib.appendingPathComponent("Logs"), "Günlük (Log)", false, true),
            (userLib.appendingPathComponent("Logs/DiagnosticReports"), "Çökme Raporu", false, false),
            (userLib.appendingPathComponent("HTTPStorages"), "Web / Ağ Verisi", false, false),
            (userLib.appendingPathComponent("WebKit"), "WebKit Önbelleği", false, false),
            (userLib.appendingPathComponent("Cookies"), "Çerez Dosyası", false, false),
            (userLib.appendingPathComponent("Application Scripts"), "Uygulama Betiği", false, false),
            (userLib.appendingPathComponent("LaunchAgents"), "Başlangıç Servisi (Kullanıcı)", false, false),

            // Sistem düzeyi (/Library) — derin kurulum yapan uygulamalar için!
            (sysLib.appendingPathComponent("Application Support"), "Sistem Uygulama Verisi", true, true),
            (sysLib.appendingPathComponent("Caches"), "Sistem Önbelleği", true, true),
            (sysLib.appendingPathComponent("Preferences"), "Sistem Tercihi", true, false),
            (sysLib.appendingPathComponent("Logs"), "Sistem Günlüğü", true, true),
            (sysLib.appendingPathComponent("LaunchAgents"), "Başlangıç Servisi (Tüm Kullanıcılar)", true, false),
            (sysLib.appendingPathComponent("LaunchDaemons"), "Arka Plan Sistem Servisi (Daemon)", true, false),
            (sysLib.appendingPathComponent("PrivilegedHelperTools"), "Yetkili Yardımcı Araç (Helper)", true, false),
            (sysLib.appendingPathComponent("Extensions"), "Çekirdek Uzantısı", true, false),
            (URL(fileURLWithPath: "/Users/Shared"), "Paylaşılan Klasör Verisi", true, false),
            (URL(fileURLWithPath: "/private/var/db/receipts"), "Kurulum Kaydı (Receipt)", true, false),
        ]

        let bid = app.bundleID.lowercased()
        let bundleName = ((app.url.lastPathComponent as NSString).deletingPathExtension).lowercased()
        let displayName = app.name.lowercased()
        let normDisplay = normalizeToken(displayName)
        let normBundleName = normalizeToken(bundleName)
        let helperIDs = Set(app.privilegedHelpers.map { $0.lowercased() })

        // com.vendor.Product -> vendor ("google", "brave", "cloudflare") ve product ("chrome", "browser")
        let bidParts = bid.split(separator: ".").map(String.init)
        let vendorToken: String? = bidParts.count >= 2 ? bidParts[1] : nil
        let genericWords: Set<String> = [
            "app", "apps", "mail", "notes", "music", "books", "maps", "news", "home",
            "clock", "chess", "stocks", "tv", "photos", "preview", "messages", "contacts"
        ]

        func matchesCandidate(fileName: String) -> Bool {
            let lower = fileName.lowercased()
            let stem = (lower as NSString).deletingPathExtension
            let normStem = normalizeToken(stem)

            // 1. Info.plist içindeki SMPrivilegedExecutables yardımcı servis eşleşmesi
            if helperIDs.contains(lower) || helperIDs.contains(stem) {
                return true
            }

            // 2. Paket Kimliği (Bundle ID) eşleşmesi (TeamID önekli Group Containers dahil!)
            if bid.count > 5 {
                if stem == bid || lower == bid
                    || lower.hasPrefix(bid + ".")
                    || lower.hasPrefix(bid + "_")
                    || lower.hasPrefix(bid + "-")
                    || stem.hasSuffix("." + bid) {
                    return true
                }
                if bidParts.count >= 3 && lower.contains("." + bid) {
                    return true
                }
            }

            // 3. Uygulama Adı eşleşmesi (BlueStacks -> BlueStacks_nxt, Brave Browser -> Brave-Browser dahil)
            for candidate in Set([normDisplay, normBundleName]) where candidate.count >= 4 && !genericWords.contains(candidate) {
                if normStem == candidate {
                    return true
                }
                if candidate.count >= 6 && (
                    lower.hasPrefix(displayName + "_") ||
                    lower.hasPrefix(displayName + "-") ||
                    lower.hasPrefix(displayName + " ") ||
                    lower.hasPrefix(bundleName + "_") ||
                    lower.hasPrefix(bundleName + "-")
                ) {
                    return true
                }
            }

            return false
        }

        var seenPaths = Set<String>()
        var found: [LeftoverItem] = []

        func appendItem(_ u: URL, kind: String, admin: Bool) {
            let p = u.path
            guard seenPaths.insert(p).inserted else { return }
            let writable = FileManager.default.isWritableFile(atPath: u.deletingLastPathComponent().path)
            found.append(LeftoverItem(
                url: u,
                size: max(FileUtils.size(of: u), 1),
                kind: kind,
                requiresAdmin: admin || !writable,
                selected: true
            ))
        }

        for loc in locations {
            for child in FileUtils.children(of: loc.url) {
                let name = child.lastPathComponent
                if name == ".DS_Store" || name == ".localized" { continue }

                if matchesCandidate(fileName: name) {
                    appendItem(child, kind: loc.kind, admin: loc.admin)
                    continue
                }

                // Üretici alt klasörü kontrolü: ör. ~/Library/Application Support/BraveSoftware/Brave-Browser
                // veya ~/Library/Application Support/Google/Chrome
                if loc.allowVendorSubscan, let vendor = vendorToken, vendor.count >= 4, vendor != "apple",
                   FileUtils.isDirectory(child) {
                    let normFolder = normalizeToken(name.lowercased().replacingOccurrences(of: ".localized", with: ""))
                    if normFolder == vendor || normFolder == vendor + "software" || normFolder.hasPrefix(vendor) {
                        let subChildren = FileUtils.children(of: child).filter {
                            $0.lastPathComponent != ".DS_Store" && $0.lastPathComponent != ".localized"
                        }
                        let matchingSubs = subChildren.filter { sub in
                            let subLow = sub.lastPathComponent.lowercased()
                            let subNorm = normalizeToken((subLow as NSString).deletingPathExtension)
                            if matchesCandidate(fileName: sub.lastPathComponent) { return true }
                            if let prod = bidParts.last, prod.count >= 4 && !genericWords.contains(prod) {
                                if subNorm == normalizeToken(prod) || subNorm == normDisplay { return true }
                            }
                            return false
                        }
                        if !matchingSubs.isEmpty {
                            // Üretici klasöründe başka bir uygulama yoksa tüm üretici klasörünü seç;
                            // başka uygulama da varsa (ör. Google/Chrome ve Google/DriveFS) yalnızca bu uygulamanın alt klasörünü seç!
                            if matchingSubs.count == subChildren.count {
                                appendItem(child, kind: loc.kind, admin: loc.admin)
                            } else {
                                for sub in matchingSubs {
                                    appendItem(sub, kind: loc.kind, admin: loc.admin)
                                }
                            }
                        }
                    }
                }
            }
        }

        return found.sorted { $0.size > $1.size }
    }

    nonisolated private static func normalizeToken(_ s: String) -> String {
        s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
