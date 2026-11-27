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
    let embeddedBundleIDs: [String]
    let isSystem: Bool
    let isSIPProtected: Bool
    var size: Int64?
    var icon: NSImage?
    var id: String { url.path }

    static func == (a: AppInfo, b: AppInfo) -> Bool { a.id == b.id && a.size == b.size }
}

@MainActor
final class UninstallerModel: ObservableObject {
    static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    @Published var apps: [AppInfo] = []
    @Published var loading = false
    @Published var search = ""

    /// Sağ panelde incelenen tekil uygulama
    @Published var selectedID: String?
    /// Çoklu seçim kutucuğu işaretlenmiş uygulamalar
    @Published var checkedIDs: Set<String> = []
    /// Her uygulama için bulunan kalıntıların önbelleği
    @Published var leftoversByApp: [String: [LeftoverItem]] = [:]
    @Published var scanningAppIDs: Set<String> = []

    @Published var working = false
    /// Varsayılan olarak kalıcı ve kökten yok etme AÇIK (Çöp Kutusu'nda bekleyen uygulama Oturum Açma Öğeleri'nde iz bırakabildiği için!)
    @Published var permanentDelete = true
    @Published var message: String?

    var filtered: [AppInfo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
        return base.sorted { a, b in
            let sa = a.size ?? -1
            let sb = b.size ?? -1
            if sa != sb { return sa > sb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var selectedApp: AppInfo? { apps.first { $0.id == selectedID } }

    var checkedApps: [AppInfo] {
        apps.filter { checkedIDs.contains($0.id) && !$0.isSIPProtected }
    }

    /// Kaldırılacak hedef uygulamalar: Çoklu seçim varsa işaretliler, yoksa sağda açık olan uygulama.
    var activeTargetApps: [AppInfo] {
        if !checkedApps.isEmpty { return checkedApps }
        if let s = selectedApp, !s.isSIPProtected { return [s] }
        return []
    }

    func leftovers(for appID: String) -> [LeftoverItem] {
        leftoversByApp[appID] ?? []
    }

    func leftoversSelectedSize(for appID: String) -> Int64 {
        leftovers(for: appID).reduce(0) { $0 + ($1.selected ? $1.size : 0) }
    }

    var batchTotalSize: Int64 {
        activeTargetApps.reduce(Int64(0)) { acc, app in
            acc + (app.size ?? 0) + leftoversSelectedSize(for: app.id)
        }
    }

    var batchLeftoverCount: Int {
        activeTargetApps.reduce(0) { $0 + leftovers(for: $1.id).filter(\.selected).count }
    }

    func toggleLeftover(appID: String, index: Int) {
        guard var list = leftoversByApp[appID], list.indices.contains(index) else { return }
        list[index].selected.toggle()
        leftoversByApp[appID] = list
    }

    // MARK: - Uygulama Listeleme ve Seçim

    func load() async {
        loading = true
        SystemMonitor.shared.beginTask("Kaldırıcı: Uygulamalar ve boyutları taranıyor…")
        let found = await Task.detached(priority: .userInitiated) { () -> [AppInfo] in
            let rawApps = Self.findApps()
            return await withTaskGroup(of: (Int, Int64).self) { group in
                for (idx, app) in rawApps.enumerated() {
                    let url = app.url
                    group.addTask(priority: .utility) {
                        (idx, FileUtils.size(of: url))
                    }
                }
                var sized = rawApps
                for await (idx, sz) in group {
                    sized[idx].size = sz
                }
                return sized.sorted { a, b in
                    let sa = a.size ?? 0
                    let sb = b.size ?? 0
                    if sa != sb { return sa > sb }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
        }.value
        apps = found.map { var a = $0; a.icon = NSWorkspace.shared.icon(forFile: a.url.path); return a }
        loading = false
        SystemMonitor.shared.endTask()
    }

    func select(_ app: AppInfo) async {
        selectedID = app.id
        await ensureLeftoversScanned(for: app)
    }

    func toggleCheck(_ app: AppInfo) {
        guard !app.isSIPProtected else { return }
        if checkedIDs.contains(app.id) {
            checkedIDs.remove(app.id)
        } else {
            checkedIDs.insert(app.id)
            if selectedID == nil { selectedID = app.id }
            Task { await ensureLeftoversScanned(for: app) }
        }
    }

    func clearSelection() {
        checkedIDs.removeAll()
    }

    func ensureLeftoversScanned(for app: AppInfo) async {
        if leftoversByApp[app.id] != nil || scanningAppIDs.contains(app.id) { return }
        scanningAppIDs.insert(app.id)
        SystemMonitor.shared.beginTask("\(app.name) tüm sistem kalıntıları taranıyor…")
        let allAppsSnapshot = apps
        let found = await Task.detached(priority: .userInitiated) {
            Self.findLeftovers(app: app, allInstalledApps: allAppsSnapshot)
        }.value
        leftoversByApp[app.id] = found
        scanningAppIDs.remove(app.id)
        SystemMonitor.shared.endTask()
    }

    // MARK: - Tekli veya Çoklu Kökten Yok Etme Motoru

    func uninstallApps(_ targetApps: [AppInfo], permanently: Bool) async {
        let removable = targetApps.filter { !$0.isSIPProtected }
        guard !removable.isEmpty else { return }

        working = true
        let labelText = removable.count == 1 ? removable[0].name : "\(removable.count) uygulama"
        SystemMonitor.shared.beginTask("\(labelText) kökten kaldırılıyor…", gpuAnimated: true)
        defer {
            working = false
            SystemMonitor.shared.endTask("✓ \(labelText) tamamen yok edildi")
        }

        // Kalıntıları henüz taranmamış seçili uygulama varsa önce tara
        for app in removable where leftoversByApp[app.id] == nil {
            let snap = apps
            let found = await Task.detached(priority: .userInitiated) {
                Self.findLeftovers(app: app, allInstalledApps: snap)
            }.value
            leftoversByApp[app.id] = found
        }

        var totalFreed: Int64 = 0
        var totalRemovedLeftovers = 0
        var needAdminDeleteURLs: [URL] = []
        var needAdminBootoutPlists: [URL] = []
        var receiptPkgIDs: Set<String> = []
        let uid = getuid()

        for app in removable {
            let appLeftovers = leftovers(for: app.id).filter(\.selected)
            totalFreed += (app.size ?? 0) + appLeftovers.reduce(0) { $0 + $1.size }
            totalRemovedLeftovers += appLeftovers.count

            // 1. Ana uygulamayı ve paket içinden çalışan tüm yardımcı (Helper/Daemon) süreçleri kapat
            await terminateAppAndHelpers(app)

            // 2. Silmeden ÖNCE ana uygulamayı, gömülü LoginItems paketlerini ve Çöp'teki eski .app kopyalarını LaunchServices'ten düşür!
            let loginItemsDir = app.url.appendingPathComponent("Contents/Library/LoginItems")
            let embeddedLoginApps = FileUtils.children(of: loginItemsDir).filter { $0.pathExtension == "app" }
            let leftoverApps = appLeftovers.map(\.url).filter { $0.pathExtension == "app" || $0.lastPathComponent.contains(".app") }
            let urlsToUnregister = embeddedLoginApps + leftoverApps + [app.url]
            let lsreg = Self.lsregisterPath
            await Task.detached {
                for u in urlsToUnregister {
                    _ = Shell.run(lsreg, ["-u", u.path])
                }
            }.value

            // 3. Tercih önbelleklerini (cfprefsd) hem ana hem gömülü bundle ID'ler için sıfırla
            let allIDs = ([app.bundleID] + app.embeddedBundleIDs).filter { !$0.isEmpty }
            await Task.detached {
                for bid in allIDs {
                    _ = Shell.run("/usr/bin/defaults", ["delete", bid])
                }
            }.value

            // 4. Servis plistleri ve kurulum kayıtlarını ayır
            for item in appLeftovers {
                let p = item.url.path
                if p.hasPrefix("/private/var/db/receipts/") || p.hasPrefix("/var/db/receipts/") {
                    receiptPkgIDs.insert((item.url.lastPathComponent as NSString).deletingPathExtension)
                }
                if p.contains("/LaunchAgents/") || p.contains("/LaunchDaemons/") {
                    if !item.requiresAdmin {
                        _ = await Task.detached {
                            Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", p])
                            return Shell.run("/bin/launchctl", ["unload", "-w", p])
                        }.value
                        do { try FileManager.default.removeItem(at: item.url) }
                        catch {
                            needAdminBootoutPlists.append(item.url)
                            needAdminDeleteURLs.append(item.url)
                        }
                    } else {
                        needAdminBootoutPlists.append(item.url)
                        needAdminDeleteURLs.append(item.url)
                    }
                } else {
                    if permanently {
                        do { try FileManager.default.removeItem(at: item.url) }
                        catch { needAdminDeleteURLs.append(item.url) }
                    } else {
                        let failed = FileUtils.trash([item.url])
                        needAdminDeleteURLs.append(contentsOf: failed)
                    }
                }
            }

            // 5. Ana .app paketini ve Çöp Kutusu'nda varsa eski kopyalarını yok et!
            if permanently {
                do { try FileManager.default.removeItem(at: app.url) }
                catch { needAdminDeleteURLs.append(app.url) }
            } else {
                let failed = FileUtils.trash([app.url])
                needAdminDeleteURLs.append(contentsOf: failed)
            }
        }

        // 6. Yönetici yetkisi gereken tüm dosyaları, servisleri ve Oturum Açma Öğeleri (BTM) yenilemesini TEK SEFERDE çalıştır!
        if !needAdminDeleteURLs.isEmpty || !receiptPkgIDs.isEmpty {
            var cmds: [String] = []
            for p in needAdminBootoutPlists {
                cmds.append("/bin/launchctl bootout system \(Shell.quote(p.path)) 2>/dev/null || /bin/launchctl unload -w \(Shell.quote(p.path)) 2>/dev/null || true")
            }
            let trashDir = FileUtils.home.appendingPathComponent(".Trash").path
            let stamp = Int(Date().timeIntervalSince1970)
            for (idx, u) in needAdminDeleteURLs.enumerated() {
                let isServicePlist = u.path.contains("/LaunchDaemons/") || u.path.contains("/LaunchAgents/")
                if permanently || isServicePlist {
                    cmds.append("/bin/rm -rf \(Shell.quote(u.path))")
                } else {
                    let dest = "\(trashDir)/\(u.lastPathComponent)-\(stamp)-\(idx)"
                    cmds.append("/bin/mv -f \(Shell.quote(u.path)) \(Shell.quote(dest)) && /usr/sbin/chown \(NSUserName()) \(Shell.quote(dest)) || true")
                }
            }
            for pkg in receiptPkgIDs where !pkg.isEmpty {
                cmds.append("/usr/sbin/pkgutil --forget \(Shell.quote(pkg)) 2>/dev/null || true")
            }
            // Kritik adım: LaunchServices ölü paket çöp toplamasını (-gc) çalıştır ve backgroundtaskmanagementd servisini
            // yeniden başlat ki macOS Sistem Ayarları › Oturum Açma Öğeleri silinen geliştirici kaydını anında listeden düşürsün!
            cmds.append("\(Shell.quote(Self.lsregisterPath)) -gc >/dev/null 2>&1 || true")
            cmds.append("/usr/bin/killall backgroundtaskmanagementd 2>/dev/null || true")
            cmds.append("/usr/bin/killall BackgroundTaskManagementAgent 2>/dev/null || true")
            cmds.append("/usr/bin/killall -u \(Shell.quote(NSUserName())) cfprefsd 2>/dev/null || true")

            _ = Shell.runAsAdmin(cmds.joined(separator: "; "))
        } else {
            // Kullanıcı düzeyinde de LaunchServices çöp toplamasını (-gc) ve arka plan görev önbelleğini tazele
            let lsreg = Self.lsregisterPath
            _ = await Task.detached {
                _ = Shell.run(lsreg, ["-gc"])
                _ = Shell.run("/usr/bin/killall", ["BackgroundTaskManagementAgent"])
                _ = Shell.run("/usr/bin/killall", ["cfprefsd"])
            }.value
        }

        // Kaldırılanları listeden düşür
        var removedCount = 0
        for app in removable where !FileUtils.exists(app.url) {
            removedCount += 1
            apps.removeAll { $0.id == app.id }
            checkedIDs.remove(app.id)
            leftoversByApp.removeValue(forKey: app.id)
            if selectedID == app.id { selectedID = nil }
        }

        if removedCount == 0 {
            message = "Kaldırma işlemi tamamlanamadı veya iptal edildi."
        } else {
            let modeWord = permanently ? "kökten yok edildi" : "Çöp Kutusu'na taşındı"
            message = "\(removedCount) uygulama ve \(totalRemovedLeftovers) sistem kalıntısı (\(totalFreed.formattedBytes)) \(modeWord)."
        }
    }

    /// Uygulamayı silmeden yalnızca ilişkili önbellek ve ayar dosyalarını sıfırlar.
    func resetSelectedLeftovers(for app: AppInfo, permanently: Bool) async {
        let targets = leftovers(for: app.id).filter(\.selected)
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
            let cmds = failed.map { "/bin/rm -rf \(Shell.quote($0.path))" }
            _ = Shell.runAsAdmin(cmds.joined(separator: "; "))
            failed = failed.filter { FileUtils.exists($0) }
        }

        let movedBytes = targets.filter { !failed.contains($0.url) }.reduce(Int64(0)) { $0 + $1.size }
        message = "\(app.name) sıfırlandı · \(movedBytes.formattedBytes) veri temizlendi."
        leftoversByApp.removeValue(forKey: app.id)
        await ensureLeftoversScanned(for: app)
    }

    private func terminateAppAndHelpers(_ app: AppInfo) async {
        let allIDs = [app.bundleID] + app.embeddedBundleIDs
        for bid in allIDs where !bid.isEmpty {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: bid) {
                running.terminate()
            }
        }
        let appPathPrefix = app.url.path + "/"
        let helperNames = Set(app.privilegedHelpers)
        await Task.detached {
            let out = Shell.run("/bin/ps", ["-axo", "pid=,comm="]).output
            var pids: [Int32] = []
            for line in out.split(separator: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
                let comm = String(parts[1])
                let base = (comm as NSString).lastPathComponent
                if comm.hasPrefix(appPathPrefix) || helperNames.contains(base) {
                    pids.append(pid)
                    Darwin.kill(pid, SIGTERM)
                }
            }
            if !pids.isEmpty {
                usleep(500_000)
                for pid in pids { Darwin.kill(pid, SIGKILL) }
            }
        }.value
    }

    // MARK: - Uygulama ve 28 Noktalı Derin Kalıntı Tarayıcısı

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

            var helpers = (info["SMPrivilegedExecutables"] as? [String: Any]).map { Array($0.keys) } ?? []
            let launchSvcDir = u.appendingPathComponent("Contents/Library/LaunchServices")
            for h in FileUtils.children(of: launchSvcDir) {
                helpers.append(h.lastPathComponent)
            }

            var embeddedIDs: [String] = []
            let loginItemsDir = u.appendingPathComponent("Contents/Library/LoginItems")
            for li in FileUtils.children(of: loginItemsDir) where li.pathExtension == "app" {
                if let bid = Bundle(url: li)?.bundleIdentifier, !bid.isEmpty {
                    embeddedIDs.append(bid)
                }
            }

            let inSystemPath = u.path.hasPrefix("/System/")
            let isApple = inSystemPath || bundleID.hasPrefix("com.apple.")
            result.append(AppInfo(
                url: u,
                name: rawDisplay,
                bundleID: bundleID,
                version: version,
                privilegedHelpers: Array(Set(helpers)),
                embeddedBundleIDs: embeddedIDs,
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

    nonisolated static func findLeftovers(app: AppInfo, allInstalledApps: [AppInfo] = []) -> [LeftoverItem] {
        let userLib = FileUtils.library
        let sysLib = URL(fileURLWithPath: "/Library")

        let locations: [(url: URL, kind: String, admin: Bool, allowVendorSubscan: Bool)] = [
            // Kullanıcı düzeyi (~/Library)
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
            (userLib.appendingPathComponent("Caches/com.apple.helpd/Generated"), "Yardım Önbelleği", false, false),
            (userLib.appendingPathComponent("LaunchAgents"), "Başlangıç Servisi (Kullanıcı)", false, false),

            // Sistem düzeyi (/Library + Receipts + Shared)
            (sysLib.appendingPathComponent("Application Support"), "Sistem Uygulama Verisi", true, true),
            (sysLib.appendingPathComponent("Caches"), "Sistem Önbelleği", true, true),
            (sysLib.appendingPathComponent("Preferences"), "Sistem Tercihi", true, false),
            (sysLib.appendingPathComponent("Logs"), "Sistem Günlüğü", true, true),
            (sysLib.appendingPathComponent("LaunchAgents"), "Başlangıç Servisi (Tüm Kullanıcılar)", true, false),
            (sysLib.appendingPathComponent("LaunchDaemons"), "Arka Plan Sistem Servisi (Daemon)", true, false),
            (sysLib.appendingPathComponent("PrivilegedHelperTools"), "Yetkili Yardımcı Araç (Helper)", true, false),
            (sysLib.appendingPathComponent("Extensions"), "Çekirdek Uzantısı", true, false),
            (sysLib.appendingPathComponent("StagedExtensions"), "Önbellekli Uzantı", true, false),
            (URL(fileURLWithPath: "/Users/Shared"), "Paylaşılan Klasör Verisi", true, false),
            (URL(fileURLWithPath: "/private/var/db/receipts"), "Kurulum Kaydı (Receipt)", true, false),
            // Çöp Kutusu'nda önceden kalmış aynı uygulamaya ait kopyalar (Oturum Açma Öğeleri'nde hayalet kayıt bırakmaması için!)
            (FileUtils.home.appendingPathComponent(".Trash"), "Çöp Kutusu'ndaki Eski Kopya", false, false),
        ]

        let bid = app.bundleID.lowercased()
        let allKnownBundleIDs = Set(([bid] + app.embeddedBundleIDs.map { $0.lowercased() }).filter { $0.count > 5 })
        let appPathPrefix = app.url.path.lowercased() + "/"
        let bundleName = ((app.url.lastPathComponent as NSString).deletingPathExtension).lowercased()
        let displayName = app.name.lowercased()
        let normDisplay = normalizeToken(displayName)
        let normBundleName = normalizeToken(bundleName)
        let helperIDs = Set(app.privilegedHelpers.map { $0.lowercased() })

        let bidParts = bid.split(separator: ".").map(String.init)
        let vendorToken: String? = bidParts.count >= 2 ? bidParts[1] : nil
        let vendorPrefix: String? = bidParts.count >= 2 ? "\(bidParts[0]).\(bidParts[1])." : nil

        let hasSiblingVendorApp: Bool = {
            guard let vp = vendorPrefix, let v = vendorToken, v != "apple" else { return true }
            return allInstalledApps.contains { other in
                other.id != app.id && other.bundleID.lowercased().hasPrefix(vp)
            }
        }()

        let genericWords: Set<String> = [
            "app", "apps", "mail", "notes", "music", "books", "maps", "news", "home",
            "clock", "chess", "stocks", "tv", "photos", "preview", "messages", "contacts"
        ]

        func plistPointsToApp(_ plistURL: URL) -> Bool {
            guard plistURL.pathExtension.lowercased() == "plist",
                  let dict = NSDictionary(contentsOf: plistURL) as? [String: Any] else { return false }

            var candidateStrings: [String] = []
            if let prog = dict["Program"] as? String { candidateStrings.append(prog) }
            if let args = dict["ProgramArguments"] as? [String] { candidateStrings.append(contentsOf: args) }
            if let assoc = dict["AssociatedBundleIdentifiers"] as? [String] { candidateStrings.append(contentsOf: assoc) }
            if let assocSingle = dict["AssociatedBundleIdentifiers"] as? String { candidateStrings.append(assocSingle) }

            for raw in candidateStrings {
                let low = raw.lowercased()
                if low.hasPrefix(appPathPrefix) || low == app.url.path.lowercased() {
                    return true
                }
                for kbid in allKnownBundleIDs where low == kbid || low.contains(kbid) {
                    return true
                }
                if !hasSiblingVendorApp, let v = vendorToken, v.count >= 4, v != "apple" {
                    if low.contains("/application support/\(v)/") || low.contains("/\(v).app/") {
                        return true
                    }
                }
            }
            return false
        }

        func matchesCandidate(fileName: String, fullURL: URL, isLaunchPlistDir: Bool) -> Bool {
            let lower = fileName.lowercased()
            let stem = (lower as NSString).deletingPathExtension
            let normStem = normalizeToken(stem)

            if isLaunchPlistDir && plistPointsToApp(fullURL) {
                return true
            }

            if helperIDs.contains(lower) || helperIDs.contains(stem) {
                return true
            }

            for kbid in allKnownBundleIDs {
                if stem == kbid || lower == kbid
                    || lower.hasPrefix(kbid + ".")
                    || lower.hasPrefix(kbid + "_")
                    || lower.hasPrefix(kbid + "-")
                    || stem.hasSuffix("." + kbid) {
                    return true
                }
                if kbid.split(separator: ".").count >= 3 && lower.contains("." + kbid) {
                    return true
                }
            }

            if !hasSiblingVendorApp, let vp = vendorPrefix, let v = vendorToken, v.count >= 5, v != "apple" {
                if lower.hasPrefix(vp) {
                    return true
                }
            }

            for candidate in Set([normDisplay, normBundleName]) where candidate.count >= 4 && !genericWords.contains(candidate) {
                if normStem == candidate {
                    return true
                }
                if candidate.count >= 6 && (
                    lower.hasPrefix(displayName + "_") ||
                    lower.hasPrefix(displayName + "-") ||
                    lower.hasPrefix(displayName + " ") ||
                    lower.hasPrefix(bundleName + "_") ||
                    lower.hasPrefix(bundleName + "-") ||
                    lower.hasPrefix(bundleName + ".app-")
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
            let isLaunchDir = loc.url.path.hasSuffix("/LaunchAgents") || loc.url.path.hasSuffix("/LaunchDaemons")
            for child in FileUtils.children(of: loc.url) {
                let name = child.lastPathComponent
                if name == ".DS_Store" || name == ".localized" { continue }

                if matchesCandidate(fileName: name, fullURL: child, isLaunchPlistDir: isLaunchDir) {
                    appendItem(child, kind: loc.kind, admin: loc.admin)
                    continue
                }

                if loc.allowVendorSubscan, let vendor = vendorToken, vendor.count >= 4, vendor != "apple",
                   FileUtils.isDirectory(child) {
                    let normFolder = normalizeToken(name.lowercased().replacingOccurrences(of: ".localized", with: ""))
                    if normFolder == vendor || normFolder == vendor + "software" || normFolder.hasPrefix(vendor) {
                        if !hasSiblingVendorApp && (normFolder == vendor || normDisplay.hasPrefix(vendor)) {
                            appendItem(child, kind: loc.kind, admin: loc.admin)
                            continue
                        }
                        let subChildren = FileUtils.children(of: child).filter {
                            $0.lastPathComponent != ".DS_Store" && $0.lastPathComponent != ".localized"
                        }
                        let matchingSubs = subChildren.filter { sub in
                            let subLow = sub.lastPathComponent.lowercased()
                            let subNorm = normalizeToken((subLow as NSString).deletingPathExtension)
                            if matchesCandidate(fileName: sub.lastPathComponent, fullURL: sub, isLaunchPlistDir: false) { return true }
                            if let prod = bidParts.last, prod.count >= 4 && !genericWords.contains(prod) {
                                if subNorm == normalizeToken(prod) || subNorm == normDisplay { return true }
                            }
                            return false
                        }
                        if !matchingSubs.isEmpty {
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

        // Ev dizinindeki gizli nokta klasörleri (örn. ~/.cloudflare-warp, ~/.cursor, ~/.bluestacks)
        let protectedDotFolders: Set<String> = [
            ".trash", ".ssh", ".gnupg", ".gitconfig", ".zshrc", ".zprofile", ".bashrc",
            ".bash_profile", ".config", ".local", ".cache", ".npm", ".gradle", ".cargo",
            ".rustup", ".pyenv", ".nvm", ".bun", ".gemini", ".claude", ".docker"
        ]
        for child in FileUtils.children(of: FileUtils.home) {
            let n = child.lastPathComponent.lowercased()
            guard n.hasPrefix("."), !protectedDotFolders.contains(n), n.count >= 5 else { continue }
            let normDot = normalizeToken(String(n.dropFirst()))
            if normDisplay.count >= 5 && !genericWords.contains(normDisplay) && normDot == normDisplay {
                appendItem(child, kind: "Gizli Ev Klasörü (~/)", admin: false)
            }
        }

        return found.sorted { $0.size > $1.size }
    }

    nonisolated private static func normalizeToken(_ s: String) -> String {
        s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
