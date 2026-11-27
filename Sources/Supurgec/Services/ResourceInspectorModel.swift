import Foundation
import AppKit
import Darwin

// MARK: - Süreç ve Alt Süreç Veri Modelleri

struct SingleProcessEntry: Identifiable, Sendable {
    let pid: Int32
    let ppid: Int32
    let uid: uid_t
    let name: String
    let fullPath: String
    let bundlePath: String?
    let cpuPercent: Double
    let cpuTotalSeconds: Double
    let memoryBytes: Int64
    let diskReadBytes: UInt64
    let diskWriteBytes: UInt64
    let isSystem: Bool
    let isCritical: Bool

    var id: Int32 { pid }
    var ownerLabel: String { uid == 0 ? "root (Sistem)" : (uid == getuid() ? NSUserName() : "UID \(uid)") }
}

struct DetailedProcessGroup: Identifiable, Sendable {
    let id: String
    let rootPID: Int32
    let name: String
    let subtitle: String
    let bundlePath: String?
    let primaryExecutablePath: String
    let cpuPercent: Double
    let cpuTotalSeconds: Double
    let memoryBytes: Int64
    let diskReadBytes: UInt64
    let diskWriteBytes: UInt64
    let isSystemDaemon: Bool
    let isCritical: Bool
    let subprocesses: [SingleProcessEntry]

    var processCount: Int { subprocesses.count }
}

// MARK: - Disk Klasör ve Büyük Dosya Modelleri

struct DiskCategoryItem: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let colorIndex: Int
    let url: URL
    let bytes: Int64
    let itemCount: Int
    let suggestedModule: String? // "systemJunk" veya "uninstaller"
}

struct LargeDiskEntry: Identifiable, Sendable {
    let id: String
    let name: String
    let locationLabel: String
    let url: URL
    let bytes: Int64
    let modifiedDate: Date?
    let isDirectory: Bool
}

// MARK: - Uygulama Bazlı Canlı Ağ Trafiği Modelleri

struct AppNetworkUsage: Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let bundlePath: String?
    let pidCount: Int
    let downloadBps: Double
    let uploadBps: Double
    let totalInBytes: UInt64
    let totalOutBytes: UInt64
    let isSystemService: Bool

    var activeSpeedBps: Double { downloadBps + uploadBps }
    var totalCombinedBytes: UInt64 { totalInBytes + totalOutBytes }
}

struct NetworkConnectionDetails: Sendable {
    var gatewayIP: String = "—"
    var dnsServers: [String] = []
    var hardwareMAC: String = "—"
    var ssidOrKind: String = "Ağ Bağlantısı"
    var gatewayPingMs: Double? = nil
    var activeVPNInterfaces: [String] = []
}

// MARK: - Tam Süreç ve Kaynak Örnekleyici (Sınırsız + Alt Süreç Kırılımlı)

actor FullProcessSampler {
    static let shared = FullProcessSampler()

    private struct RawEntry {
        let pid: Int32
        let ppid: Int32
        let uid: uid_t
        let rssKB: Double
        let cpuSec: Double
        let path: String
    }

    private var prevTimes: (byPID: [Int32: Double], at: Date)?
    private var smoothedGroupCPU: [String: Double] = [:]

    func sampleAll(
        runningApps: [OptimizationModel.RunningAppMeta],
        forceFreshWindow: Bool
    ) async -> (groups: [DetailedProcessGroup], flat: [SingleProcessEntry]) {
        let t1 = Date()
        let snap1 = Self.readFullTable()

        let baseTimes: [Int32: Double]
        let elapsed: Double
        let snapEnd: [RawEntry]

        if !forceFreshWindow,
           let prev = prevTimes,
           t1.timeIntervalSince(prev.at) >= 0.45,
           t1.timeIntervalSince(prev.at) <= 8.0 {
            baseTimes = prev.byPID
            elapsed = t1.timeIntervalSince(prev.at)
            snapEnd = snap1
            prevTimes = (Dictionary(uniqueKeysWithValues: snap1.map { ($0.pid, $0.cpuSec) }), t1)
        } else {
            let map1 = Dictionary(uniqueKeysWithValues: snap1.map { ($0.pid, $0.cpuSec) })
            try? await Task.sleep(for: .milliseconds(500))
            let t2 = Date()
            let snap2 = Self.readFullTable()
            baseTimes = map1
            elapsed = max(0.25, t2.timeIntervalSince(t1))
            snapEnd = snap2
            prevTimes = (Dictionary(uniqueKeysWithValues: snap2.map { ($0.pid, $0.cpuSec) }), t2)
        }

        let coreCount = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
        let pidToMeta = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.pid, $0) })
        let bundleApps = runningApps.compactMap { meta -> (prefix: String, bundle: String, name: String, pid: Int32, isSys: Bool)? in
            guard let bp = meta.bundlePath else { return nil }
            let sys = bp.hasPrefix("/System/Library/CoreServices") || bp.hasPrefix("/usr/libexec")
            return (bp + "/", bp, meta.name, meta.pid, sys)
        }

        let criticalSet: Set<String> = [
            "WindowServer", "kernel_task", "launchd", "loginwindow", "Finder", "Dock", "SystemUIServer"
        ]
        let systemAgentSet: Set<String> = [
            "talagentd", "launchservicesd", "logd", "UniversalControl", "Evrensel Denetim",
            "NotificationCenter", "Bildirim Merkezi", "ControlCenter", "Denetim Merkezi",
            "System Events", "Sistem Olayları", "WindowManager", "MenuBarAgent", "airportd", "runningboardd"
        ]
        let friendlySystemMap: [String: (title: String, desc: String)] = [
            "WindowServer": ("WindowServer (Ekran Çizim Motoru)", "macOS pencere, ekran ve kompozisyon yöneticisi"),
            "mds_stores": ("Spotlight İndeksleme", "Dosya aramaları için diski indeksleyen servis"),
            "mds": ("Spotlight Arama Servisi", "macOS Spotlight ana arama motoru"),
            "coreaudiod": ("CoreAudio (Ses Motoru)", "Hoparlör ve mikrofon ses akışı servisi"),
            "backupd": ("Time Machine Yedekleme", "macOS arka plan yedekleme servisi"),
            "cloudd": ("iCloud Eşitleme (cloudd)", "iCloud Drive ve uygulama eşitleme servisi"),
            "nsurlsessiond": ("Arka Plan Ağ Aktarımı", "macOS sistem indirme/yükleme kuyruğu"),
            "Syspolicyd": ("Gatekeeper Güvenlik Denetimi", "Uygulama imza ve güvenlik doğrulama servisi"),
            "syspolicyd": ("Gatekeeper Güvenlik Denetimi", "Uygulama imza ve güvenlik doğrulama servisi")
        ]

        struct GroupAcc {
            var key: String
            var rootPID: Int32
            var name: String
            var customDesc: String?
            var bundlePath: String?
            var execPath: String
            var deltaCPUSec: Double
            var totalCPUSec: Double
            var memBytes: Int64
            var diskRead: UInt64
            var diskWrite: UInt64
            var isSys: Bool
            var isCrit: Bool
            var children: [SingleProcessEntry]
        }

        var groupsMap: [String: GroupAcc] = [:]
        var flatEntries: [SingleProcessEntry] = []
        flatEntries.reserveCapacity(snapEnd.count)

        for raw in snapEnd {
            let baseName = (raw.path as NSString).lastPathComponent
            if baseName == "ps" { continue }

            let dSec: Double
            if let old = baseTimes[raw.pid] {
                dSec = max(0, raw.cpuSec - old)
            } else {
                dSec = min(raw.cpuSec, elapsed)
            }
            let singleCPU = min(100.0, (dSec / (elapsed * coreCount)) * 100.0)

            // Gerçek fiziksel bellek ayak izi (Etkinlik Monitörü ile birebir uyumlu ri_phys_footprint + root için rss yedeği)
            var physBytes = Int64(raw.rssKB * 1024.0)
            var dRead: UInt64 = 0
            var dWrite: UInt64 = 0
            var ri = rusage_info_v4()
            let rRes = withUnsafeMutablePointer(to: &ri) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reb in
                    proc_pid_rusage(raw.pid, RUSAGE_INFO_V4, reb)
                }
            }
            if rRes == 0 {
                if ri.ri_phys_footprint > 0 {
                    physBytes = Int64(ri.ri_phys_footprint)
                }
                dRead = ri.ri_diskio_bytesread
                dWrite = ri.ri_diskio_byteswritten
            }

            var groupKey = "proc:\(baseName):\(raw.pid)"
            var groupTitle = baseName
            var customDesc: String? = nil
            var bundlePath: String? = nil
            var leaderPID = raw.pid
            var isSys = raw.uid == 0
                || raw.path.hasPrefix("/System/")
                || raw.path.hasPrefix("/usr/libexec/")
                || raw.path.hasPrefix("/usr/sbin/")
                || raw.path.hasPrefix("/sbin/")

            if let matched = bundleApps.first(where: { raw.path.hasPrefix($0.prefix) }) {
                groupKey = "app:" + matched.bundle
                groupTitle = matched.name
                bundlePath = matched.bundle
                leaderPID = matched.pid
                isSys = matched.isSys || systemAgentSet.contains(matched.name)
            } else if let direct = pidToMeta[raw.pid] {
                groupKey = "pid:\(direct.pid)"
                groupTitle = direct.name
                bundlePath = direct.bundlePath
                leaderPID = direct.pid
                if let bp = direct.bundlePath {
                    isSys = bp.hasPrefix("/System/Library/CoreServices") || systemAgentSet.contains(direct.name)
                }
            } else if let parent = pidToMeta[raw.ppid], raw.ppid > 1 {
                groupKey = "pid:\(parent.pid)"
                groupTitle = parent.name
                bundlePath = parent.bundlePath
                leaderPID = parent.pid
                if let bp = parent.bundlePath {
                    isSys = bp.hasPrefix("/System/Library/CoreServices") || systemAgentSet.contains(parent.name)
                }
            } else if let appRange = raw.path.range(of: ".app/") {
                let bp = String(raw.path[..<appRange.upperBound].dropLast())
                groupKey = "app:" + bp
                groupTitle = ((bp as NSString).lastPathComponent as NSString).deletingPathExtension
                bundlePath = bp
                isSys = bp.hasPrefix("/System/Library/") || systemAgentSet.contains(groupTitle)
            } else {
                // Aynı isimli arka plan servislerini grupla
                groupKey = "bin:" + baseName
            }

            if systemAgentSet.contains(baseName) || systemAgentSet.contains(groupTitle) {
                isSys = true
            }
            if groupTitle == "Finder" {
                isSys = false
            }
            if let f = friendlySystemMap[baseName] {
                groupTitle = f.title
                customDesc = f.desc
                isSys = true
            }

            let isCrit = criticalSet.contains(baseName) || criticalSet.contains(groupTitle)

            let single = SingleProcessEntry(
                pid: raw.pid,
                ppid: raw.ppid,
                uid: raw.uid,
                name: baseName,
                fullPath: raw.path,
                bundlePath: bundlePath,
                cpuPercent: singleCPU,
                cpuTotalSeconds: raw.cpuSec,
                memoryBytes: physBytes,
                diskReadBytes: dRead,
                diskWriteBytes: dWrite,
                isSystem: isSys,
                isCritical: isCrit
            )
            if physBytes >= 512 * 1024 || singleCPU >= 0.05 {
                flatEntries.append(single)
            }

            if var g = groupsMap[groupKey] {
                g.deltaCPUSec += dSec
                g.totalCPUSec += raw.cpuSec
                g.memBytes += physBytes
                g.diskRead += dRead
                g.diskWrite += dWrite
                if g.bundlePath == nil { g.bundlePath = bundlePath }
                g.children.append(single)
                groupsMap[groupKey] = g
            } else {
                groupsMap[groupKey] = GroupAcc(
                    key: groupKey,
                    rootPID: leaderPID,
                    name: groupTitle,
                    customDesc: customDesc,
                    bundlePath: bundlePath,
                    execPath: raw.path,
                    deltaCPUSec: dSec,
                    totalCPUSec: raw.cpuSec,
                    memBytes: physBytes,
                    diskRead: dRead,
                    diskWrite: dWrite,
                    isSys: isSys,
                    isCrit: isCrit,
                    children: [single]
                )
            }
        }

        var nextSmooth: [String: Double] = [:]
        var finalGroups: [DetailedProcessGroup] = []
        finalGroups.reserveCapacity(groupsMap.count)

        for (_, g) in groupsMap {
            if g.memBytes < 1024 * 1024 && g.deltaCPUSec <= 0.001 { continue }
            let rawPct = min(100.0, (g.deltaCPUSec / (elapsed * coreCount)) * 100.0)
            let smoothPct: Double
            if let prev = smoothedGroupCPU[g.key] {
                smoothPct = rawPct * 0.72 + prev * 0.28
            } else {
                smoothPct = rawPct
            }
            nextSmooth[g.key] = smoothPct

            let subtitle: String
            if let desc = g.customDesc {
                subtitle = desc
            } else if g.children.count > 1 {
                subtitle = "Ana uygulama + \(g.children.count - 1) alt süreç toplamı"
            } else if g.isSys {
                subtitle = "macOS sistem servisi · PID \(g.rootPID)"
            } else {
                subtitle = "Çalışan uygulama · PID \(g.rootPID)"
            }

            let sortedChildren = g.children.sorted {
                if $0.memoryBytes != $1.memoryBytes { return $0.memoryBytes > $1.memoryBytes }
                return $0.cpuPercent > $1.cpuPercent
            }

            finalGroups.append(DetailedProcessGroup(
                id: g.key,
                rootPID: g.rootPID,
                name: g.name,
                subtitle: subtitle,
                bundlePath: g.bundlePath,
                primaryExecutablePath: g.execPath,
                cpuPercent: smoothPct,
                cpuTotalSeconds: g.totalCPUSec,
                memoryBytes: g.memBytes,
                diskReadBytes: g.diskRead,
                diskWriteBytes: g.diskWrite,
                isSystemDaemon: g.isSys,
                isCritical: g.isCrit,
                subprocesses: sortedChildren
            ))
        }

        smoothedGroupCPU = nextSmooth
        return (finalGroups, flatEntries)
    }

    private static func readFullTable() -> [RawEntry] {
        let out = Shell.run("/bin/ps", ["-axo", "pid=,ppid=,uid=,rss=,time=,comm="]).output
        var list: [RawEntry] = []
        list.reserveCapacity(320)

        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard parts.count == 6,
                  let pid = Int32(parts[0]), pid > 0,
                  let ppid = Int32(parts[1]),
                  let uidVal = UInt32(parts[2]) else { continue }
            let rss = Double(parts[3]) ?? 0
            let cpuSec = parseTime(parts[4])
            let path = String(parts[5])
            list.append(RawEntry(pid: pid, ppid: ppid, uid: uidVal, rssKB: rss, cpuSec: cpuSec, path: path))
        }
        return list
    }

    private static func parseTime(_ s: Substring) -> Double {
        let clean = s.replacingOccurrences(of: ",", with: ".")
        let cols = clean.split(separator: ":")
        if cols.count == 2 {
            return (Double(cols[0]) ?? 0) * 60.0 + (Double(cols[1]) ?? 0)
        } else if cols.count == 3 {
            return (Double(cols[0]) ?? 0) * 3600.0 + (Double(cols[1]) ?? 0) * 60.0 + (Double(cols[2]) ?? 0)
        }
        return Double(clean) ?? 0
    }
}

// MARK: - Uygulama Bazlı Canlı Ağ Trafiği Örnekleyici (nettop Delta Motoru)

actor NetworkProcessSampler {
    static let shared = NetworkProcessSampler()

    private struct RawNetRow {
        let pid: Int32
        let procName: String
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    private var prevSnap: (byPID: [Int32: (inB: UInt64, outB: UInt64)], at: Date)?

    func sampleApps(
        runningApps: [OptimizationModel.RunningAppMeta],
        forceFreshWindow: Bool
    ) async -> [AppNetworkUsage] {
        let t1 = Date()
        let rows1 = Self.runNettopOnce()
        if rows1.isEmpty { return [] }

        let baseMap: [Int32: (inB: UInt64, outB: UInt64)]
        let elapsed: Double
        let endRows: [RawNetRow]

        if !forceFreshWindow,
           let prev = prevSnap,
           t1.timeIntervalSince(prev.at) >= 0.5,
           t1.timeIntervalSince(prev.at) <= 8.0 {
            baseMap = prev.byPID
            elapsed = t1.timeIntervalSince(prev.at)
            endRows = rows1
            prevSnap = (Dictionary(uniqueKeysWithValues: rows1.map { ($0.pid, ($0.bytesIn, $0.bytesOut)) }), t1)
        } else {
            let map1 = Dictionary(uniqueKeysWithValues: rows1.map { ($0.pid, ($0.bytesIn, $0.bytesOut)) })
            try? await Task.sleep(for: .milliseconds(550))
            let t2 = Date()
            let rows2 = Self.runNettopOnce()
            baseMap = map1
            elapsed = max(0.25, t2.timeIntervalSince(t1))
            endRows = rows2.isEmpty ? rows1 : rows2
            prevSnap = (Dictionary(uniqueKeysWithValues: endRows.map { ($0.pid, ($0.bytesIn, $0.bytesOut)) }), t2)
        }

        // PID -> tam çalıştırılabilir yol haritası (Helper süreçlerini ana .app ile birleştirmek için)
        let pidPaths = Self.readPIDPaths()
        let pidToMeta = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.pid, $0) })
        let bundleApps = runningApps.compactMap { meta -> (prefix: String, bundle: String, name: String)? in
            guard let bp = meta.bundlePath else { return nil }
            return (bp + "/", bp, meta.name)
        }

        struct Bucket {
            var key: String
            var name: String
            var bundlePath: String?
            var pids: Int
            var dIn: UInt64
            var dOut: UInt64
            var totIn: UInt64
            var totOut: UInt64
            var isSys: Bool
        }

        var buckets: [String: Bucket] = [:]

        for row in endRows {
            let dIn: UInt64
            let dOut: UInt64
            if let old = baseMap[row.pid] {
                dIn = row.bytesIn >= old.inB ? (row.bytesIn - old.inB) : 0
                dOut = row.bytesOut >= old.outB ? (row.bytesOut - old.outB) : 0
            } else {
                dIn = 0
                dOut = 0
            }

            if row.bytesIn == 0 && row.bytesOut == 0 && dIn == 0 && dOut == 0 {
                continue
            }

            let fullPath = pidPaths[row.pid] ?? ""
            var key = "net:" + row.procName
            var title = row.procName
            var bundlePath: String? = nil
            var isSys = fullPath.hasPrefix("/System/")
                || fullPath.hasPrefix("/usr/libexec/")
                || fullPath.hasPrefix("/usr/sbin/")

            if let matched = bundleApps.first(where: { !fullPath.isEmpty && fullPath.hasPrefix($0.prefix) }) {
                key = "app:" + matched.bundle
                title = matched.name
                bundlePath = matched.bundle
                isSys = matched.bundle.hasPrefix("/System/Library/CoreServices")
            } else if let direct = pidToMeta[row.pid] {
                key = "app:" + (direct.bundlePath ?? direct.name)
                title = direct.name
                bundlePath = direct.bundlePath
            } else if let appRange = fullPath.range(of: ".app/") {
                let bp = String(fullPath[..<appRange.upperBound].dropLast())
                key = "app:" + bp
                title = ((bp as NSString).lastPathComponent as NSString).deletingPathExtension
                bundlePath = bp
                isSys = bp.hasPrefix("/System/Library/")
            } else if row.procName == "mDNSResponder" {
                title = "mDNSResponder (macOS DNS Çözümleyici)"
                isSys = true
            } else if row.procName == "apsd" {
                title = "Apple Bildirim Servisi (apsd)"
                isSys = true
            } else if row.procName == "nsurlsessiond" {
                title = "macOS Arka Plan İndirme Servisi"
                isSys = true
            } else if row.procName == "cloudd" {
                title = "iCloud Eşitleme Servisi"
                isSys = true
            }

            if var b = buckets[key] {
                b.pids += 1
                b.dIn += dIn
                b.dOut += dOut
                b.totIn += row.bytesIn
                b.totOut += row.bytesOut
                if b.bundlePath == nil { b.bundlePath = bundlePath }
                buckets[key] = b
            } else {
                buckets[key] = Bucket(
                    key: key,
                    name: title,
                    bundlePath: bundlePath,
                    pids: 1,
                    dIn: dIn,
                    dOut: dOut,
                    totIn: row.bytesIn,
                    totOut: row.bytesOut,
                    isSys: isSys
                )
            }
        }

        return buckets.values.map { b in
            let sub = b.pids > 1 ? "\(b.pids) ağ bağlantısı süreci" : (b.isSys ? "macOS ağ servisi" : "Uygulama bağlantısı")
            return AppNetworkUsage(
                id: b.key,
                name: b.name,
                subtitle: sub,
                bundlePath: b.bundlePath,
                pidCount: b.pids,
                downloadBps: Double(b.dIn) / elapsed,
                uploadBps: Double(b.dOut) / elapsed,
                totalInBytes: b.totIn,
                totalOutBytes: b.totOut,
                isSystemService: b.isSys
            )
        }
    }

    private static func runNettopOnce() -> [RawNetRow] {
        let res = Shell.run("/usr/bin/nettop", ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-x"])
        guard res.status == 0 else { return [] }
        var rows: [RawNetRow] = []
        for line in res.output.split(separator: "\n") {
            if line.hasPrefix(",") || line.hasPrefix("time") { continue }
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let nameAndPID = cols[0]
            guard let dotIdx = nameAndPID.lastIndex(of: "."),
                  let pid = Int32(nameAndPID[nameAndPID.index(after: dotIdx)...]) else { continue }
            let procName = String(nameAndPID[..<dotIdx])
            let bIn = UInt64(cols[1]) ?? 0
            let bOut = UInt64(cols[2]) ?? 0
            rows.append(RawNetRow(pid: pid, procName: procName, bytesIn: bIn, bytesOut: bOut))
        }
        return rows
    }

    private static func readPIDPaths() -> [Int32: String] {
        let out = Shell.run("/bin/ps", ["-axo", "pid=,comm="]).output
        var dict: [Int32: String] = [:]
        dict.reserveCapacity(300)
        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            dict[pid] = String(parts[1])
        }
        return dict
    }
}

// MARK: - Ana Uygulama İçi Kapsamlı Kaynak Denetçisi

@MainActor
final class ResourceInspectorModel: ObservableObject {
    @Published var processGroups: [DetailedProcessGroup] = []
    @Published var flatProcesses: [SingleProcessEntry] = []
    @Published var totalProcessCount: Int = 0
    @Published var refreshingProcesses = false
    @Published var actionFeedback: String?

    @Published var diskCategories: [DiskCategoryItem] = []
    @Published var topAppDataFolders: [LargeDiskEntry] = []
    @Published var largeUserFiles: [LargeDiskEntry] = []
    @Published var localSnapshotCount: Int = 0
    @Published var scanningDisk = false
    @Published var diskScanCompleted = false
    @Published var trashState: TrashState = .loading

    @Published var networkApps: [AppNetworkUsage] = []
    @Published var connectionDetails = NetworkConnectionDetails()
    @Published var refreshingNetwork = false

    private var iconCache: [String: NSImage] = [:]

    func icon(forBundlePath bundlePath: String?, fallbackExecPath: String? = nil) -> NSImage? {
        if let bp = bundlePath, !bp.isEmpty {
            if let cached = iconCache[bp] { return cached }
            if FileManager.default.fileExists(atPath: bp) {
                let img = NSWorkspace.shared.icon(forFile: bp)
                iconCache[bp] = img
                return img
            }
        }
        if let ep = fallbackExecPath, let r = ep.range(of: ".app/") {
            let bp = String(ep[..<r.upperBound].dropLast())
            if let cached = iconCache[bp] { return cached }
            if FileManager.default.fileExists(atPath: bp) {
                let img = NSWorkspace.shared.icon(forFile: bp)
                iconCache[bp] = img
                return img
            }
        }
        return nil
    }

    // MARK: - 1. Bellek & İşlemci Süreç Yenileme

    func refreshAllProcesses(manual: Bool = false) async {
        guard !refreshingProcesses else { return }
        refreshingProcesses = true
        let runningMap = OptimizationModel.buildRunningAppsMap()
        let result = await FullProcessSampler.shared.sampleAll(runningApps: runningMap, forceFreshWindow: manual)
        processGroups = result.groups
        flatProcesses = result.flat
        totalProcessCount = result.flat.count
        refreshingProcesses = false
    }

    func terminateGroup(_ group: DetailedProcessGroup) {
        if group.isCritical {
            actionFeedback = "\(group.name) macOS'un çalışması için zorunlu bir sistem bileşenidir; sonlandırılamaz."
            return
        }
        var terminated = false
        if Darwin.kill(group.rootPID, SIGTERM) == 0 {
            terminated = true
        }
        for sub in group.subprocesses where Darwin.kill(sub.pid, SIGTERM) == 0 {
            terminated = true
        }
        actionFeedback = terminated
            ? "✓ \(group.name) sonlandırıldı."
            : "\(group.name) yönetici/sistem korumalı olduğu için sonlandırılamadı."
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            await refreshAllProcesses(manual: true)
            SystemMonitor.shared.updateFull()
        }
    }

    func terminateSingle(_ entry: SingleProcessEntry) {
        if entry.isCritical {
            actionFeedback = "\(entry.name) kritik bir macOS sürecidir; sonlandırılamaz."
            return
        }
        let ok = (Darwin.kill(entry.pid, SIGTERM) == 0)
        actionFeedback = ok
            ? "✓ \(entry.name) (PID \(entry.pid)) sonlandırıldı."
            : "\(entry.name) (PID \(entry.pid)) sonlandırılamadı."
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            await refreshAllProcesses(manual: true)
            SystemMonitor.shared.updateFull()
        }
    }

    // MARK: - 2. Disk Klasör Dağılımı & Büyük Dosya Taraması

    func refreshTrashStatus() {
        Task {
            trashState = await TrashService.inspect()
        }
    }

    func scanDiskBreakdown(force: Bool = false) async {
        if scanningDisk || (diskScanCompleted && !force) { return }
        scanningDisk = true
        SystemMonitor.shared.beginTask("Disk: Klasör dağılımı ve büyük dosyalar analiz ediliyor…")
        refreshTrashStatus()

        let result = await Task.detached(priority: .userInitiated) {
            Self.performDiskAnalysis()
        }.value

        diskCategories = result.categories
        topAppDataFolders = result.appDataFolders
        largeUserFiles = result.largeFiles
        localSnapshotCount = result.snapshotCount
        scanningDisk = false
        diskScanCompleted = true
        SystemMonitor.shared.endTask("✓ Disk analizi tamamlandı")
    }

    nonisolated private static func performDiskAnalysis() -> (
        categories: [DiskCategoryItem],
        appDataFolders: [LargeDiskEntry],
        largeFiles: [LargeDiskEntry],
        snapshotCount: Int
    ) {
        let home = FileUtils.home
        let lib = FileUtils.library

        let specs: [(id: String, title: String, sub: String, icon: String, cIdx: Int, url: URL, mod: String?)] = [
            ("apps", "Yüklü Uygulamalar (/Applications)", "Mac'inizde kurulu tüm uygulama paketleri", "square.grid.2x2.fill", 0, URL(fileURLWithPath: "/Applications"), "uninstaller"),
            ("appsupport", "Uygulama Verileri (Application Support)", "Uygulamaların veritabanları, profilleri ve eklentileri", "folder.fill.badge.gearshape", 1, lib.appendingPathComponent("Application Support"), nil),
            ("caches", "Kullanıcı Önbellekleri (~/Library/Caches)", "Geçici hızlandırma dosyaları — güvenle temizlenebilir", "archivebox.fill", 2, lib.appendingPathComponent("Caches"), "systemJunk"),
            ("containers", "Korumalı Uygulama Kapsayıcıları (Containers)", "App Store ve korumalı uygulamaların çalışma alanları", "shippingbox.fill", 3, lib.appendingPathComponent("Containers"), nil),
            ("downloads", "İndirilenler Klasörü", "İnternetten indirdiğiniz kurulum paketleri ve arşivler", "arrow.down.circle.fill", 4, home.appendingPathComponent("Downloads"), nil),
            ("developer", "Geliştirici Araçları & Xcode Verileri", "Derleme önbellekleri, simülatörler ve SDK verileri", "hammer.fill", 5, lib.appendingPathComponent("Developer"), "systemJunk"),
            ("documents", "Belgelerim (~/Documents)", "Kişisel çalışma dosyalarınız ve belgeleriniz", "doc.text.fill", 0, home.appendingPathComponent("Documents"), nil),
            ("desktop", "Masaüstü (~/Desktop)", "Masaüstünde tutulan dosya ve klasörler", "menubar.dock.rectangle", 1, home.appendingPathComponent("Desktop"), nil),
            ("movies", "Filmler ve Ekran Kayıtları (~/Movies)", "Video projeleri ve medya dosyaları", "film.fill", 2, home.appendingPathComponent("Movies"), nil),
            ("pictures", "Resimler ve Fotoğraf Arşivi (~/Pictures)", "Fotoğraflar kütüphanesi ve görseller", "photo.fill", 3, home.appendingPathComponent("Pictures"), nil),
            ("music", "Müzik ve Ses Kütüphanesi (~/Music)", "İndirilmiş müzikler ve ses projeleri", "music.note.list", 4, home.appendingPathComponent("Music"), nil)
        ]

        var categories: [DiskCategoryItem] = []
        for s in specs where FileUtils.exists(s.url) {
            let children = FileUtils.children(of: s.url)
            let bytes = FileUtils.size(of: s.url)
            if bytes > 0 {
                categories.append(DiskCategoryItem(
                    id: s.id,
                    title: s.title,
                    subtitle: s.sub,
                    icon: s.icon,
                    colorIndex: s.cIdx,
                    url: s.url,
                    bytes: bytes,
                    itemCount: children.count,
                    suggestedModule: s.mod
                ))
            }
        }
        categories.sort { $0.bytes > $1.bytes }

        // En çok yer kaplayan Application Support + Caches alt klasörleri
        var appFolders: [LargeDiskEntry] = []
        let dataRoots: [(URL, String)] = [
            (lib.appendingPathComponent("Application Support"), "Application Support"),
            (lib.appendingPathComponent("Caches"), "Önbellek (Caches)")
        ]
        for (root, label) in dataRoots {
            for child in FileUtils.children(of: root) {
                let name = child.lastPathComponent
                if name.hasPrefix(".") { continue }
                let sz = FileUtils.size(of: child)
                if sz >= 25 * 1000 * 1000 {
                    let modDate = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    appFolders.append(LargeDiskEntry(
                        id: child.path,
                        name: name,
                        locationLabel: label,
                        url: child,
                        bytes: sz,
                        modifiedDate: modDate,
                        isDirectory: true
                    ))
                }
            }
        }
        appFolders.sort { $0.bytes > $1.bytes }
        if appFolders.count > 25 { appFolders = Array(appFolders.prefix(25)) }

        // İndirilenler, Masaüstü, Belgeler ve Filmler içindeki büyük tekil dosyalar (>= 20 MB)
        var bigFiles: [LargeDiskEntry] = []
        let userRoots: [(URL, String)] = [
            (home.appendingPathComponent("Downloads"), "İndirilenler"),
            (home.appendingPathComponent("Desktop"), "Masaüstü"),
            (home.appendingPathComponent("Documents"), "Belgeler"),
            (home.appendingPathComponent("Movies"), "Filmler")
        ]
        let fileKeys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey
        ]

        for (root, label) in userRoots where FileUtils.exists(root) {
            if let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(fileKeys),
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator {
                    guard let vals = try? url.resourceValues(forKeys: fileKeys) else { continue }
                    if vals.isSymbolicLink == true { continue }
                    if vals.isPackage == true {
                        enumerator.skipDescendants()
                        let pkgSize = FileUtils.size(of: url)
                        if pkgSize >= 25 * 1000 * 1000 {
                            bigFiles.append(LargeDiskEntry(
                                id: url.path,
                                name: url.lastPathComponent,
                                locationLabel: label,
                                url: url,
                                bytes: pkgSize,
                                modifiedDate: vals.contentModificationDate,
                                isDirectory: true
                            ))
                        }
                        continue
                    }
                    if vals.isRegularFile == true {
                        let sz = Int64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? 0)
                        if sz >= 20 * 1000 * 1000 {
                            bigFiles.append(LargeDiskEntry(
                                id: url.path,
                                name: url.lastPathComponent,
                                locationLabel: label,
                                url: url,
                                bytes: sz,
                                modifiedDate: vals.contentModificationDate,
                                isDirectory: false
                            ))
                        }
                    }
                }
            }
        }
        bigFiles.sort { $0.bytes > $1.bytes }
        if bigFiles.count > 30 { bigFiles = Array(bigFiles.prefix(30)) }

        // APFS yerel Time Machine anlık görüntü sayısı
        let tmOut = Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).output
        let snapCount = tmOut.split(separator: "\n").filter { $0.contains("com.apple.") }.count

        return (categories, appFolders, bigFiles, snapCount)
    }

    // MARK: - 3. Canlı Uygulama Bazlı Ağ Trafiği & Bağlantı Bilgileri

    func refreshNetworkApps(manual: Bool = false) async {
        guard !refreshingNetwork else { return }
        refreshingNetwork = true
        let runningMap = OptimizationModel.buildRunningAppsMap()
        let apps = await NetworkProcessSampler.shared.sampleApps(runningApps: runningMap, forceFreshWindow: manual)
        networkApps = apps
        refreshingNetwork = false
    }

    func refreshConnectionMetadata() async {
        let activeIF = SystemMonitor.shared.activeInterface
        let details = await Task.detached(priority: .utility) { () -> NetworkConnectionDetails in
            var d = NetworkConnectionDetails()

            // Varsayılan Ağ Geçidi (Modem IP)
            let routeOut = Shell.run("/sbin/route", ["-n", "get", "default"]).output
            for line in routeOut.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("gateway:") {
                    d.gatewayIP = t.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }

            // Aktif DNS Sunucuları
            let dnsOut = Shell.run("/usr/sbin/scutil", ["--dns"]).output
            var seenDNS = Set<String>()
            var dnsList: [String] = []
            for line in dnsOut.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("nameserver[") {
                    if let colon = t.firstIndex(of: ":") {
                        let ip = t[t.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                        if !ip.isEmpty && seenDNS.insert(ip).inserted {
                            dnsList.append(ip)
                        }
                    }
                }
            }
            d.dnsServers = Array(dnsList.prefix(4))

            // Donanım arayüz türü ve MAC adresi
            let ifOut = Shell.run("/sbin/ifconfig", [activeIF]).output
            for line in ifOut.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("ether ") {
                    d.hardwareMAC = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                }
            }
            d.ssidOrKind = activeIF == "en0" ? "Wi-Fi / Birincil Ağ (\(activeIF))" : "Ağ Arayüzü (\(activeIF))"

            // Aktif VPN Tünelleri (utun / ipsec / ppp)
            let allIF = Shell.run("/sbin/ifconfig", ["-a"]).output
            var currentIF = ""
            var vpnIFs: [String] = []
            for line in allIF.split(separator: "\n") {
                if !line.hasPrefix("\t") && !line.hasPrefix(" ") {
                    if let colon = line.firstIndex(of: ":") {
                        currentIF = String(line[..<colon])
                    }
                } else if (currentIF.hasPrefix("utun") || currentIF.hasPrefix("ppp") || currentIF.hasPrefix("ipsec")),
                          line.contains("inet ") && !line.contains("127.0.0.1") {
                    if !vpnIFs.contains(currentIF) { vpnIFs.append(currentIF) }
                }
            }
            d.activeVPNInterfaces = vpnIFs

            // Modem Gecikmesi (Gateway Ping)
            if d.gatewayIP != "—" && !d.gatewayIP.isEmpty {
                let pingOut = Shell.run("/sbin/ping", ["-c", "1", "-W", "800", d.gatewayIP]).output
                if let r = pingOut.range(of: "time=") {
                    let after = pingOut[r.upperBound...]
                    if let space = after.firstIndex(of: " ") {
                        d.gatewayPingMs = Double(after[..<space])
                    }
                }
            }

            return d
        }.value

        connectionDetails = details
    }
}
