import AppKit

enum ServiceRecommendation {
    case orphaned
    case safeToDisable
    case keepIfUsed
    case optional

    var badgeTitle: String {
        switch self {
        case .orphaned: return "Silinmiş Uygulama Kalıntısı!"
        case .safeToDisable: return "Güvenle Kapatılabilir"
        case .keepIfUsed: return "Kullanıyorsanız Kalsın"
        case .optional: return "İsteğe Bağlı"
        }
    }
}

struct LaunchItem: Identifiable {
    enum Scope: String { case user = "Kullanıcı", global = "Tüm kullanıcılar", daemon = "Sistem servisi" }
    let url: URL
    let label: String
    let program: String
    let scope: Scope

    let friendlyTitle: String
    let plainExplanation: String
    let impactNote: String
    let recommendation: ServiceRecommendation
    var icon: NSImage?

    var id: String { url.path }
}

struct ProcessItem: Identifiable {
    let pid: Int32
    let allPIDs: [Int32]
    let name: String
    let subtitle: String
    let cpu: Double          // Tüm Mac kapasitesine göre gerçek %0..%100 CPU payı
    let memoryMB: Double
    let helperCount: Int
    let isSystemDaemon: Bool
    let isSystemCritical: Bool
    var icon: NSImage?
    var id: String { name }
}

enum ProcessSortOrder: String, CaseIterable, Identifiable {
    case cpu = "CPU (Çoktan Aza)"
    case memory = "Bellek (Çoktan Aza)"

    var id: String { rawValue }
}

/// Gerçek zaman aralıklı (delta cputime) süreç CPU ölçer — ps'nin hatalı anlık %cpu zıplamalarını ortadan kaldırır.
actor ProcessSampler {
    static let shared = ProcessSampler()

    struct RawProc {
        let pid: Int32
        let ppid: Int32
        let rssKB: Double
        let cpuSeconds: Double
        let fullPath: String
    }

    private var prevSnapshot: (byPID: [Int32: Double], at: Date)?
    private var smoothedAppCPU: [String: Double] = [:]

    func sampleGrouped(runningApps: [OptimizationModel.RunningAppMeta], forceFreshWindow: Bool) async -> [ProcessItem] {
        let now1 = Date()
        let snap1 = Self.readProcessTable()

        let baseMap: [Int32: Double]
        let elapsed: Double
        let endSnap: [RawProc]

        if !forceFreshWindow,
           let prev = prevSnapshot,
           now1.timeIntervalSince(prev.at) >= 0.45,
           now1.timeIntervalSince(prev.at) <= 8.0 {
            baseMap = prev.byPID
            elapsed = now1.timeIntervalSince(prev.at)
            endSnap = snap1
            prevSnapshot = (Dictionary(uniqueKeysWithValues: snap1.map { ($0.pid, $0.cpuSeconds) }), now1)
        } else {
            // İlk ölçüm veya elle "Yenile": gerçek 550ms zaman farkı üzerinden net CPU tüketimi ölç!
            let dict1 = Dictionary(uniqueKeysWithValues: snap1.map { ($0.pid, $0.cpuSeconds) })
            try? await Task.sleep(for: .milliseconds(550))
            let now2 = Date()
            let snap2 = Self.readProcessTable()
            baseMap = dict1
            elapsed = max(0.25, now2.timeIntervalSince(now1))
            endSnap = snap2
            prevSnapshot = (Dictionary(uniqueKeysWithValues: snap2.map { ($0.pid, $0.cpuSeconds) }), now2)
        }

        let coreCount = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
        let pidToMeta = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.pid, $0) })
        let bundleApps = runningApps.compactMap { meta -> (path: String, name: String, pid: Int32, isSys: Bool)? in
            guard let bp = meta.bundlePath else { return nil }
            let sys = bp.hasPrefix("/System/Library/CoreServices") || bp.hasPrefix("/usr/libexec")
            return (bp + "/", meta.name, meta.pid, sys)
        }

        struct Bucket {
            var rootPID: Int32
            var pids: [Int32]
            var name: String
            var appBundlePath: String?
            var deltaCPUSec: Double
            var rssKB: Double
            var isSystemDaemon: Bool
            var isCritical: Bool
        }

        let criticalNames: Set<String> = [
            "WindowServer", "kernel_task", "launchd", "loginwindow", "Finder", "Dock", "SystemUIServer"
        ]
        let noisyBackgroundAgents: Set<String> = [
            "talagentd", "launchservicesd", "logd", "UniversalControl", "Evrensel Denetim",
            "NotificationCenter", "Bildirim Merkezi", "ControlCenter", "Denetim Merkezi",
            "System Events", "Sistem Olayları", "WindowManager", "MenuBarAgent", "airportd", "runningboardd"
        ]
        let friendlySystemNames: [String: (title: String, desc: String)] = [
            "WindowServer": ("WindowServer (Ekran Çizim Sistemi)", "macOS pencere ve ekran birleştirme motoru"),
            "mds_stores": ("Spotlight İndeksleme", "Dosya aramaları için diski indeksleyen sistem servisi"),
            "mds": ("Spotlight Arama Motoru", "macOS Spotlight arka plan servisi"),
            "coreaudiod": ("CoreAudio (Ses Sistemi)", "Hoparlör ve mikrofon ses akışı servisi"),
            "backupd": ("Time Machine Yedekleme", "macOS yedekleme servisi"),
        ]

        let myPID = ProcessInfo.processInfo.processIdentifier
        var buckets: [String: Bucket] = [:]

        for proc in endSnap where proc.pid != myPID {
            let baseName = (proc.fullPath as NSString).lastPathComponent
            if baseName == "ps" { continue }

            // Yalnızca önceki örnekte de var olan PID'nin gerçek harcadığı CPU saniyesini al
            let dSec: Double
            if let oldSec = baseMap[proc.pid] {
                dSec = max(0, proc.cpuSeconds - oldSec)
            } else {
                dSec = min(proc.cpuSeconds, elapsed)
            }

            var groupKey = baseName
            var displayTitle = baseName
            var bundlePath: String? = nil
            var leaderPID = proc.pid
            var isSysDaemon = proc.fullPath.hasPrefix("/System/") || proc.fullPath.hasPrefix("/usr/libexec/") || proc.fullPath.hasPrefix("/usr/sbin/")

            if let matchedApp = bundleApps.first(where: { proc.fullPath.hasPrefix($0.path) }) {
                groupKey = "app:" + matchedApp.path
                displayTitle = matchedApp.name
                bundlePath = String(matchedApp.path.dropLast())
                leaderPID = matchedApp.pid
                isSysDaemon = matchedApp.isSys || noisyBackgroundAgents.contains(matchedApp.name)
            } else if let direct = pidToMeta[proc.pid] {
                groupKey = "pid:\(direct.pid)"
                displayTitle = direct.name
                bundlePath = direct.bundlePath
                leaderPID = direct.pid
                if let bp = direct.bundlePath {
                    isSysDaemon = bp.hasPrefix("/System/Library/CoreServices") || noisyBackgroundAgents.contains(direct.name)
                }
            } else if let parent = pidToMeta[proc.ppid], proc.ppid > 1 {
                groupKey = "pid:\(parent.pid)"
                displayTitle = parent.name
                bundlePath = parent.bundlePath
                leaderPID = parent.pid
                if let bp = parent.bundlePath {
                    isSysDaemon = bp.hasPrefix("/System/Library/CoreServices") || noisyBackgroundAgents.contains(parent.name)
                }
            } else if let firstAppRange = proc.fullPath.range(of: ".app/") {
                let bp = String(proc.fullPath[..<firstAppRange.upperBound].dropLast())
                groupKey = "app:" + bp
                displayTitle = ((bp as NSString).lastPathComponent as NSString).deletingPathExtension
                bundlePath = bp
                isSysDaemon = bp.hasPrefix("/System/Library/") || noisyBackgroundAgents.contains(displayTitle)
            }

            if noisyBackgroundAgents.contains(baseName) || noisyBackgroundAgents.contains(displayTitle) {
                isSysDaemon = true
            }
            if displayTitle == "Finder" {
                isSysDaemon = false
            }

            let isCrit = criticalNames.contains(baseName) || criticalNames.contains(displayTitle)
            if let sysInfo = friendlySystemNames[baseName] {
                displayTitle = sysInfo.title
                isSysDaemon = true
            }

            if var existing = buckets[groupKey] {
                existing.pids.append(proc.pid)
                existing.deltaCPUSec += dSec
                existing.rssKB += proc.rssKB
                if existing.appBundlePath == nil { existing.appBundlePath = bundlePath }
                buckets[groupKey] = existing
            } else {
                buckets[groupKey] = Bucket(
                    rootPID: leaderPID,
                    pids: [proc.pid],
                    name: displayTitle,
                    appBundlePath: bundlePath,
                    deltaCPUSec: dSec,
                    rssKB: proc.rssKB,
                    isSystemDaemon: isSysDaemon,
                    isCritical: isCrit
                )
            }
        }

        var nextSmoothed: [String: Double] = [:]
        var result: [ProcessItem] = []

        for (_, b) in buckets {
            // Tüm çekirdeklerin toplam kapasitesine (%0 - %100) oranla gerçek CPU yüzdesi!
            let rawMacPercent = min(100.0, (b.deltaCPUSec / (elapsed * coreCount)) * 100.0)
            let finalCPU: Double
            if let prev = smoothedAppCPU[b.name] {
                finalCPU = rawMacPercent * 0.70 + prev * 0.30
            } else {
                finalCPU = rawMacPercent
            }
            nextSmoothed[b.name] = finalCPU

            let memMB = b.rssKB / 1024.0
            if finalCPU < 0.05 && memMB < 20 { continue }

            let subtitle: String
            if let sysMatch = friendlySystemNames.first(where: { b.name == $0.value.title }) {
                subtitle = sysMatch.value.desc
            } else if b.pids.count > 1 {
                subtitle = "Ana uygulama + \(b.pids.count - 1) alt süreç toplamı"
            } else if b.isSystemDaemon {
                subtitle = "macOS arka plan servisi"
            } else {
                subtitle = "Çalışan uygulama"
            }

            let icon: NSImage? = await MainActor.run {
                b.appBundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            }

            result.append(ProcessItem(
                pid: b.rootPID,
                allPIDs: b.pids,
                name: b.name,
                subtitle: subtitle,
                cpu: finalCPU,
                memoryMB: memMB,
                helperCount: b.pids.count,
                isSystemDaemon: b.isSystemDaemon,
                isSystemCritical: b.isCritical,
                icon: icon
            ))
        }

        smoothedAppCPU = nextSmoothed
        return result
    }

    private static func readProcessTable() -> [RawProc] {
        let out = Shell.run("/bin/ps", ["-axo", "pid=,ppid=,rss=,time=,comm="]).output
        var list: [RawProc] = []
        list.reserveCapacity(256)

        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5,
                  let pid = Int32(parts[0]), pid > 0,
                  let ppid = Int32(parts[1]) else { continue }
            let rss = Double(parts[2]) ?? 0
            let cpuSec = parseCPUTime(parts[3])
            let path = String(parts[4])
            list.append(RawProc(pid: pid, ppid: ppid, rssKB: rss, cpuSeconds: cpuSec, fullPath: path))
        }
        return list
    }

    /// BSD ps 'time=' biçimini (MM:SS.cc veya HH:MM:SS.cc) saniyeye çevirir.
    private static func parseCPUTime(_ s: Substring) -> Double {
        let clean = s.replacingOccurrences(of: ",", with: ".")
        let colonParts = clean.split(separator: ":")
        if colonParts.count == 2 {
            let mins = Double(colonParts[0]) ?? 0
            let secs = Double(colonParts[1]) ?? 0
            return mins * 60.0 + secs
        } else if colonParts.count == 3 {
            let hours = Double(colonParts[0]) ?? 0
            let mins = Double(colonParts[1]) ?? 0
            let secs = Double(colonParts[2]) ?? 0
            return hours * 3600.0 + mins * 60.0 + secs
        }
        return Double(clean) ?? 0
    }
}

@MainActor
final class OptimizationModel: ObservableObject {
    @Published var loginItems: [String] = []
    @Published var loginItemsError: String?
    @Published var launchAgents: [LaunchItem] = []
    @Published var processes: [ProcessItem] = []
    @Published var sortOrder: ProcessSortOrder = .cpu
    @Published var showSystemProcesses = false
    @Published var refreshingProcesses = false
    @Published var message: String?

    struct RunningAppMeta: Sendable {
        let pid: Int32
        let name: String
        let bundlePath: String?
    }

    var sortedProcesses: [ProcessItem] {
        let base = processes.filter { proc in
            if showSystemProcesses { return true }
            // Kullanıcı uygulamalarını her zaman göster; sistem servislerini yalnızca ciddi yük (%2.5+ CPU veya 300MB+ RAM) varsa göster
            return !proc.isSystemDaemon || proc.cpu >= 2.5 || proc.memoryMB >= 300
        }
        switch sortOrder {
        case .cpu:
            return Array(base.sorted {
                if abs($0.cpu - $1.cpu) > 0.05 { return $0.cpu > $1.cpu }
                return $0.memoryMB > $1.memoryMB
            }.prefix(25))
        case .memory:
            return Array(base.sorted {
                if abs($0.memoryMB - $1.memoryMB) > 0.5 { return $0.memoryMB > $1.memoryMB }
                return $0.cpu > $1.cpu
            }.prefix(25))
        }
    }

    func refresh(manual: Bool = false) {
        refreshLaunchAgents()
        refreshProcesses(manual: manual)
        refreshLoginItems()
    }

    func refreshLaunchAgents() {
        Task {
            SystemMonitor.shared.beginTask("Optimizasyon: Başlangıç servisleri taranıyor…")
            let found = await Task.detached { Self.scanLaunchAgents() }.value
            self.launchAgents = found.map { item in
                var copy = item
                copy.icon = Self.resolveIcon(forProgramPath: item.program)
                return copy
            }
            SystemMonitor.shared.endTask()
        }
    }

    func refreshProcesses(manual: Bool = false) {
        guard !refreshingProcesses else { return }
        refreshingProcesses = true
        if manual {
            SystemMonitor.shared.beginTask("Optimizasyon: Uygulama CPU yükleri ölçülüyor…")
        }
        let runningMap = Self.buildRunningAppsMap()
        Task {
            let items = await ProcessSampler.shared.sampleGrouped(runningApps: runningMap, forceFreshWindow: manual)
            self.processes = items
            self.refreshingProcesses = false
            if manual {
                SystemMonitor.shared.endTask("✓ İşlemci analizi güncellendi")
            }
        }
    }

    func refreshLoginItems() {
        let (desc, err) = Shell.appleScript("tell application \"System Events\" to get the name of every login item")
        if let err {
            loginItemsError = "Giriş öğeleri okunamadı. Süpürgeç'e Sistem Ayarları › Gizlilik ve Güvenlik › Otomasyon bölümünden System Events izni verin. (\(err))"
            loginItems = []
            return
        }
        loginItemsError = nil
        var names: [String] = []
        if let desc, desc.numberOfItems > 0 {
            for i in 1...desc.numberOfItems { if let s = desc.atIndex(i)?.stringValue { names.append(s) } }
        } else if let s = desc?.stringValue, !s.isEmpty {
            names = [s]
        }
        loginItems = names
    }

    func removeLoginItem(_ name: String) {
        let safe = name.replacingOccurrences(of: "\"", with: "\\\"")
        let (_, err) = Shell.appleScript("tell application \"System Events\" to delete login item \"\(safe)\"")
        message = err == nil ? "\(name) giriş öğelerinden kaldırıldı." : "Kaldırılamadı: \(err!)"
        refreshLoginItems()
    }

    func disable(_ item: LaunchItem) {
        if item.scope == .user {
            Shell.run("/bin/launchctl", ["unload", "-w", item.url.path])
            do {
                try FileManager.default.removeItem(at: item.url)
                message = "\(item.friendlyTitle) tamamen kaldırıldı (Oturum Açma Öğeleri'nden düşürüldü)."
            } catch {
                message = "\(item.friendlyTitle) kaldırılamadı: \(error.localizedDescription)"
            }
        } else {
            let cmd = "/bin/launchctl bootout system \(Shell.quote(item.url.path)) 2>/dev/null || /bin/launchctl unload -w \(Shell.quote(item.url.path)) 2>/dev/null || true; /bin/rm -f \(Shell.quote(item.url.path))"
            let r = Shell.runAsAdmin(cmd)
            message = r.ok ? "\(item.friendlyTitle) sistemden tamamen silindi (Oturum Açma Öğeleri'nden kaldırıldı)." : "İşlem iptal edildi."
        }
        refreshLaunchAgents()
    }

    func kill(_ p: ProcessItem) {
        if p.isSystemCritical {
            message = "\(p.name) macOS'un çalışması için zorunlu bir sistem sürecidir; kapatılamaz."
            return
        }
        var ok = (Darwin.kill(p.pid, SIGTERM) == 0)
        if !ok {
            for subPID in p.allPIDs where Darwin.kill(subPID, SIGTERM) == 0 {
                ok = true
            }
        }
        message = ok ? "\(p.name) sonlandırıldı." : "\(p.name) sonlandırılamadı."
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            refreshProcesses(manual: true)
        }
    }

    static func buildRunningAppsMap() -> [RunningAppMeta] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let name = app.localizedName, !name.isEmpty else { return nil }
            return RunningAppMeta(pid: app.processIdentifier, name: name, bundlePath: app.bundleURL?.path)
        }
    }

    private static func resolveIcon(forProgramPath program: String) -> NSImage? {
        if let appRange = program.range(of: ".app") {
            let appPath = String(program[..<appRange.upperBound])
            if FileManager.default.fileExists(atPath: appPath) {
                return NSWorkspace.shared.icon(forFile: appPath)
            }
        }
        if !program.isEmpty && FileManager.default.fileExists(atPath: program) {
            return NSWorkspace.shared.icon(forFile: program)
        }
        return nil
    }

    // MARK: - İnsan Diliyle Servis Açıklama Motoru

    nonisolated static func scanLaunchAgents() -> [LaunchItem] {
        let dirs: [(URL, LaunchItem.Scope)] = [
            (FileUtils.library.appendingPathComponent("LaunchAgents"), .user),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .global),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]
        var items: [LaunchItem] = []
        for (dir, scope) in dirs {
            for u in FileUtils.children(of: dir) where u.pathExtension == "plist" {
                let dict = NSDictionary(contentsOf: u) as? [String: Any] ?? [:]
                let label = dict["Label"] as? String ?? u.deletingPathExtension().lastPathComponent
                let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first ?? ""
                let isOrphan = !program.isEmpty && program.hasPrefix("/") && !FileManager.default.fileExists(atPath: program)
                let info = describeService(label: label, program: program, scope: scope, isOrphan: isOrphan)
                items.append(LaunchItem(
                    url: u,
                    label: label,
                    program: program,
                    scope: scope,
                    friendlyTitle: info.title,
                    plainExplanation: info.explanation,
                    impactNote: info.impact,
                    recommendation: info.rec,
                    icon: nil
                ))
            }
        }
        return items.sorted { a, b in
            if a.recommendation != b.recommendation {
                if a.recommendation == .orphaned { return true }
                if b.recommendation == .orphaned { return false }
                return a.recommendation == .safeToDisable
            }
            return a.friendlyTitle.localizedCaseInsensitiveCompare(b.friendlyTitle) == .orderedAscending
        }
    }

    nonisolated private static func describeService(
        label: String,
        program: String,
        scope: LaunchItem.Scope,
        isOrphan: Bool = false
    ) -> (title: String, explanation: String, impact: String, rec: ServiceRecommendation) {
        if isOrphan {
            let orphanApp = extractAppName(from: program) ?? prettifyLabel(label)
            return (
                "\(orphanApp) — Artık (Yetim) Servis Kaydı",
                "Bu servisin işaret ettiği uygulama (\(program)) bilgisayarınızdan silinmiş ama servis dosyası geride kalmış.",
                "Sistem Ayarları › Oturum Açma Öğeleri'nde boşuna görünmemesi için hemen kaldırabilirsiniz.",
                .orphaned
            )
        }
        let l = label.lowercased()
        let p = program.lowercased()

        if l.contains("com.eso.supurgec") {
            return (
                "Süpürgeç Üst Bar Başlatıcısı",
                "Bilgisayarınız açıldığında Süpürgeç'in ana pencereyi açmadan yalnızca üst menü çubuğunda sessizce başlamasını sağlar.",
                "Üst bardaki göstergenin her açılışta otomatik gelmesi için açık bırakın (Ayarlar sekmesinden de yönetebilirsiniz).",
                .keepIfUsed
            )
        }
        if l.contains("google.keystone") || l.contains("googleupdater") || p.contains("googleupdater") {
            return (
                "Google Arka Plan Güncelleyicisi",
                "Chrome ve diğer Google uygulamalarını siz kullanmasanız bile arka planda sürekli kontrol edip günceller.",
                "Kapatırsanız Chrome bozulmaz; güncellemeleri yalnızca Chrome açıkken kontrol eder.",
                .safeToDisable
            )
        }
        if l.contains("logirightsight") || p.contains("logirightsight") {
            return (
                "Logitech Kamera Otomatik Kadraj (RightSight)",
                "Harici Logitech web kameranız varsa görüntülü görüşmelerde yüzünüzü ortalamaya yarar.",
                "Logitech web kamerası kullanmıyorsanız güvenle kapatabilirsiniz.",
                .safeToDisable
            )
        }
        if l.contains("logi") || p.contains("logioptions") || p.contains("logitech") {
            return (
                "Logitech Fare ve Klavye Servisi (Logi Options+)",
                "Logitech fare ve klavyenizin özel tuş atamalarını, DPI hızını ve akıcı kaydırma ayarlarını çalıştırır.",
                "Logitech fare veya klavye kullanıyorsanız kapatmayın; özel tuş ayarlarınız devre dışı kalır.",
                .keepIfUsed
            )
        }
        if l.contains("cloudflare") || l.contains("warp") || p.contains("cloudflare") {
            if l.contains("updater") || p.contains("updater") {
                return (
                    "Cloudflare WARP Otomatik Güncelleyici",
                    "Cloudflare WARP uygulamasının arka planda yeni sürüm kontrolü yapmasını sağlar.",
                    "Kapatırsanız WARP çalışmaya devam eder, yalnızca otomatik güncelleme kapanır.",
                    .safeToDisable
                )
            }
            return (
                "Cloudflare WARP / 1.1.1.1 Ağ Servisi",
                "Cloudflare WARP VPN ve şifreli DNS bağlantısını kuran ana sistem servisidir.",
                "WARP kullanıyorsanız kapatmayın; kapatırsanız WARP internete bağlanamaz.",
                .keepIfUsed
            )
        }
        if l.contains("adobe") || p.contains("adobe") {
            if l.contains("ags") || l.contains("genuine") {
                return (
                    "Adobe Lisans Doğrulama Servisi",
                    "Arka planda Adobe lisans kontrolü yapan ek servistir.",
                    "Kapatılması günlük Mac kullanımınızı hızlandırır.",
                    .safeToDisable
                )
            }
            return (
                "Adobe Creative Cloud Arka Plan Servisi",
                "Adobe uygulamalarının senkronizasyon ve güncelleme işlemlerini yürütür.",
                "Adobe programlarını sık kullanmıyorsanız başlangıçtan kaldırabilirsiniz.",
                .safeToDisable
            )
        }
        if l.contains("microsoft.update") || p.contains("microsoft autoupdate") {
            return (
                "Microsoft Office Otomatik Güncelleyici",
                "Word, Excel ve diğer Office uygulamaları için arka planda güncelleme arar.",
                "Kapatırsanız Office uygulamaları normal çalışır; güncellemeleri elle kontrol edebilirsiniz.",
                .safeToDisable
            )
        }
        if l.contains("valvesoftware.steam") || p.contains("steam") {
            return (
                "Steam Başlangıç Yardımcısı",
                "Steam'in Mac açılışında arka planda hazır beklemesini sağlar.",
                "Oyun oynamadığınız zamanlarda RAM harcamaması için güvenle kapatabilirsiniz.",
                .safeToDisable
            )
        }
        if l.contains("spotify") {
            return (
                "Spotify Başlangıç Servisi",
                "Mac açıldığında Spotify'ı otomatik başlatır.",
                "Kapatırsanız Spotify yalnızca siz tıkladığınızda açılır.",
                .safeToDisable
            )
        }
        if l.contains("zoom") || p.contains("zoom.us") {
            return (
                "Zoom Arka Plan Servisi",
                "Zoom toplantı bağlantılarının hızlı açılması ve güncellemeler için arka planda bekler.",
                "Kapatırsanız Zoom'u normal şekilde açıp kullanmaya devam edebilirsiniz.",
                .safeToDisable
            )
        }
        if l.contains("docker") || p.contains("docker") {
            return (
                "Docker Arka Plan Servisi",
                "Docker konteyner motorunun sistem servisini çalıştırır.",
                "Docker geliştirme yapıyorsanız kalsın; kullanmıyorsanız kapatabilirsiniz.",
                .keepIfUsed
            )
        }

        let appName = extractAppName(from: program) ?? prettifyLabel(label)
        if l.contains("update") || p.contains("update") {
            return (
                "\(appName) — Otomatik Güncelleyici",
                "\(appName) uygulaması için arka planda düzenli yeni sürüm kontrolü yapar.",
                "Kapatırsanız uygulamanın kendisi silinmez veya bozulmaz; yalnızca arka plan güncelleyicisi durur.",
                .safeToDisable
            )
        }
        if l.contains("crash") || p.contains("crash") || l.contains("diagnostic") {
            return (
                "\(appName) — Hata Raporlayıcı",
                "\(appName) çöktüğünde geliştiriciye tanılama raporu gönderen arka plan servisidir.",
                "Güvenle kapatabilirsiniz; uygulamanın çalışmasını etkilemez.",
                .safeToDisable
            )
        }
        if scope == .daemon {
            return (
                "\(appName) — Sistem Arka Plan Servisi",
                "\(appName) uygulamasının Mac açılışında yönetici yetkisiyle başlattığı yardımcı servistir.",
                "Bu uygulamayı aktif kullanıyorsanız açık bırakın; artık kullanmıyorsanız kapatabilirsiniz.",
                .keepIfUsed
            )
        }
        return (
            "\(appName) — Başlangıç Yardımcısı",
            "\(appName) uygulamasının oturum açılışında arka planda otomatik başlamasını sağlar.",
            "Uygulamanın kendi kendine açılmasını istemiyorsanız devre dışı bırakabilirsiniz.",
            .optional
        )
    }

    nonisolated private static func extractAppName(from path: String) -> String? {
        if let r = path.range(of: ".app") {
            let prefix = String(path[..<r.lowerBound])
            let last = (prefix as NSString).lastPathComponent
            if !last.isEmpty { return last }
        }
        let comps = path.split(separator: "/")
        if let appSupportIdx = comps.firstIndex(of: "Application Support"), appSupportIdx + 1 < comps.count {
            return String(comps[appSupportIdx + 1]).replacingOccurrences(of: ".localized", with: "")
        }
        return nil
    }

    nonisolated private static func prettifyLabel(_ label: String) -> String {
        let parts = label.split(separator: ".").map(String.init)
        let filtered = parts.filter { !["com", "org", "net", "io", "app", "macos", "agent", "daemon", "helper", "xpcservice"].contains($0.lowercased()) }
        if let best = filtered.first {
            return best.prefix(1).uppercased() + best.dropFirst()
        }
        return label
    }
}
