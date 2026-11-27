import Foundation
import AppKit
import Darwin

struct TopConsumer: Identifiable {
    let pid: Int32
    let name: String
    let subtitle: String
    let cpu: Double
    let memoryBytes: Int64
    var icon: NSImage?
    var id: String { name }
}

struct SpeedTestResult {
    let downloadMbps: Double
    let uploadMbps: Double
    let idlePingMs: Double?
    let rpm: Int?
    let interfaceName: String
    let timestamp: Date

    var bufferbloatLabel: String {
        guard let rpm else { return "Ölçüldü" }
        if rpm >= 1000 { return "Mükemmel (Sıfıra Yakın Bufferbloat)" }
        if rpm >= 400 { return "İyi (Düşük-Orta Bufferbloat)" }
        return "Yüksek Bufferbloat"
    }
}

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var cpuPercentInt: Int = 0
    @Published var menuBarTick: UInt64 = 0

    @Published var cpu: Double = 0
    @Published var cpuUser: Double = 0
    @Published var cpuSystem: Double = 0
    @Published var cpuIdle: Double = 1
    @Published var loadAverage: (Double, Double, Double) = (0, 0, 0)
    @Published var coreLoads: [Double] = []
    let coreCount: Int = ProcessInfo.processInfo.activeProcessorCount
    let cpuBrand: String = SystemMonitor.readSysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
    let perfCoreCount: Int = SystemMonitor.readSysctlInt("hw.perflevel0.logicalcpu")
    let effCoreCount: Int = SystemMonitor.readSysctlInt("hw.perflevel1.logicalcpu")
    let pageSizeBytes: Int = Int(sysconf(_SC_PAGESIZE))

    @Published var memoryUsed: Double = 0
    @Published var memoryTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published var memApp: Double = 0
    @Published var memWired: Double = 0
    @Published var memCompressed: Double = 0
    @Published var memCached: Double = 0
    @Published var memFree: Double = 0
    @Published var swapUsed: Double = 0
    @Published var swapTotal: Double = 0
    @Published var pageIns: UInt64 = 0
    @Published var pageOuts: UInt64 = 0

    @Published var diskUsed: Double = 0
    @Published var diskTotal: Double = 1
    @Published var diskFreeImmediate: Double = 0
    @Published var diskPurgeable: Double = 0
    @Published var volumeName: String = "Macintosh HD"
    @Published var fileSystemFormat: String = "APFS"

    @Published var netIn: Double = 0
    @Published var netOut: Double = 0
    @Published var totalNetIn: UInt64 = 0
    @Published var totalNetOut: UInt64 = 0
    @Published var localIP: String = "—"
    @Published var activeInterface: String = "en0"
    @Published var vpnTunnelActive: Bool = false
    @Published var netInHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var netOutHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var peakNetIn: Double = 1024
    @Published var peakNetOut: Double = 1024

    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 60)

    // Süpürgeç anlık işlem ve öz tüketim verileri
    @Published var currentActivity: String = "Hazır · Sistem İzleniyor"
    @Published var isBusyTaskRunning: Bool = false
    @Published var selfCPUPercent: Double = 0
    @Published var selfMemoryBytes: Int64 = 0
    @Published var selfDiskReadBytes: UInt64 = 0
    @Published var selfDiskWriteBytes: UInt64 = 0
    @Published var selfDiskSpeedBps: Double = 0
    @Published var selfGPUActive: Bool = false

    // Kararlı en çok kaynak kullanan uygulamalar
    @Published var topCPUConsumers: [TopConsumer] = []
    @Published var topMemConsumers: [TopConsumer] = []
    @Published var refreshingConsumers: Bool = false

    // Hız testi
    @Published var speedTesting = false
    @Published var speedTestStatus = ""
    @Published var lastSpeedTest: SpeedTestResult?
    @Published var speedTestError: String?

    var memoryRatio: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
    var diskRatio: Double { diskTotal > 0 ? diskUsed / diskTotal : 0 }

    private var activeTaskStack: [String] = []
    private var clearBannerTask: Task<Void, Never>?
    private var prevTicks: (user: Double, system: Double, idle: Double, nice: Double)?
    private var prevCoreTicks: [(user: Double, system: Double, idle: Double)] = []
    private var prevNet: (inB: UInt64, outB: UInt64, at: Date)?
    private var prevSelfUsage: (cpuSec: Double, diskIO: UInt64, at: Date)?
    private var timer: Timer?
    private var activeConsumers = 0

    private init() {
        updateFull()
        scheduleTimer()
    }

    // MARK: - Merkezi İşlem Durumu (Neye Göre Aktif / Hazır)

    func beginTask(_ title: String, gpuAnimated: Bool = false) {
        clearBannerTask?.cancel()
        activeTaskStack.append(title)
        currentActivity = title
        isBusyTaskRunning = true
        if gpuAnimated { selfGPUActive = true }
    }

    func updateTask(_ title: String) {
        if !activeTaskStack.isEmpty {
            activeTaskStack[activeTaskStack.count - 1] = title
        }
        currentActivity = title
        isBusyTaskRunning = true
    }

    func endTask(_ completionNotice: String? = nil) {
        if !activeTaskStack.isEmpty {
            activeTaskStack.removeLast()
        }
        if let current = activeTaskStack.last {
            currentActivity = current
            isBusyTaskRunning = true
        } else {
            selfGPUActive = false
            isBusyTaskRunning = false
            if let notice = completionNotice {
                currentActivity = notice
                clearBannerTask?.cancel()
                clearBannerTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2.2))
                    guard !Task.isCancelled, let self, self.activeTaskStack.isEmpty else { return }
                    self.currentActivity = "Hazır · Sistem İzleniyor"
                }
            } else {
                currentActivity = "Hazır · Sistem İzleniyor"
            }
        }
    }

    // MARK: - Etkileşimli / Arka Plan Zamanlayıcısı

    func beginInteractiveSession() {
        activeConsumers += 1
        if activeConsumers == 1 {
            updateFull()
            scheduleTimer()
        }
    }

    func endInteractiveSession() {
        activeConsumers = max(0, activeConsumers - 1)
        if activeConsumers == 0 {
            scheduleTimer()
        }
    }

    func applyRefreshIntervalChange() {
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let base = MenuBarSettings.shared.refreshInterval
        let detailed = activeConsumers > 0
        let interval: TimeInterval = detailed ? base : max(base, 3.0)

        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.activeConsumers > 0 {
                    self.updateFull()
                } else {
                    self.updateBackgroundLightweight()
                }
            }
        }
        t.tolerance = detailed ? 0.25 : 1.0
        timer = t
    }

    func updateBackgroundLightweight() {
        let settings = MenuBarSettings.shared
        var changed = false

        if settings.showCPU {
            let sample = sampleCPUTicks()
            let pct = Int((sample.totalUsed * 100).rounded())
            if pct != cpuPercentInt {
                cpuPercentInt = pct
                changed = true
            }
        }
        if settings.showRAM {
            readMemory()
            changed = true
        }
        if settings.showNetwork {
            readNetwork()
            changed = true
        }
        if settings.showDisk {
            readDisk()
            changed = true
        }
        if changed {
            menuBarTick &+= 1
        }
    }

    func updateFull() {
        let sample = sampleCPUTicks()
        cpu = sample.totalUsed
        cpuUser = sample.user
        cpuSystem = sample.system
        cpuIdle = sample.idle
        cpuPercentInt = Int((sample.totalUsed * 100).rounded())

        cpuHistory.append(sample.totalUsed)
        if cpuHistory.count > 60 { cpuHistory.removeFirst() }
        samplePerCoreLoads()

        var avg = [Double](repeating: 0, count: 3)
        if getloadavg(&avg, 3) == 3 {
            loadAverage = (avg[0], avg[1], avg[2])
        }

        readMemory()
        readSwap()
        readDisk()
        readNetwork()
        netInHistory.append(netIn)
        if netInHistory.count > 60 { netInHistory.removeFirst() }
        netOutHistory.append(netOut)
        if netOutHistory.count > 60 { netOutHistory.removeFirst() }
        peakNetIn = max(1024, netInHistory.max() ?? 1024)
        peakNetOut = max(1024, netOutHistory.max() ?? 1024)
        readSelfResources()
        menuBarTick &+= 1
    }

    // MARK: - Gerçek Delta CPU Süreç Listesi (Zıplama Yapmaz, Toplam Yük İle Birebir Örtüşür!)

    func refreshTopConsumers(manual: Bool = false) {
        guard !refreshingConsumers else { return }
        refreshingConsumers = true
        let runningMap = OptimizationModel.buildRunningAppsMap()

        Task {
            let grouped = await ProcessSampler.shared.sampleGrouped(runningApps: runningMap, forceFreshWindow: manual)

            // Kullanıcı uygulamalarını ve yalnızca kayda değer yük tüketen sistem servislerini göster
            let visible = grouped.filter { !$0.isSystemDaemon || $0.cpu >= 1.5 || $0.memoryMB >= 300 }

            let mapped: [TopConsumer] = visible.map { g in
                TopConsumer(
                    pid: g.pid,
                    name: g.name,
                    subtitle: g.helperCount > 1 ? "\(g.helperCount) süreç toplamı" : "",
                    cpu: g.cpu,
                    memoryBytes: Int64(g.memoryMB * 1024 * 1024),
                    icon: g.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
                )
            }

            self.topCPUConsumers = Array(
                mapped.sorted {
                    if abs($0.cpu - $1.cpu) > 0.05 { return $0.cpu > $1.cpu }
                    return $0.memoryBytes > $1.memoryBytes
                }.prefix(6)
            )

            self.topMemConsumers = Array(
                mapped.sorted {
                    if $0.memoryBytes != $1.memoryBytes { return $0.memoryBytes > $1.memoryBytes }
                    return $0.cpu > $1.cpu
                }.prefix(6)
            )
            self.refreshingConsumers = false
        }
    }

    // MARK: - Dahili Hız ve Bufferbloat Testi

    func runSpeedTest() {
        guard !speedTesting else { return }
        speedTesting = true
        speedTestError = nil
        beginTask("Ağ: Hız ve bufferbloat ölçülüyor…")
        speedTestStatus = "Apple CDN üzerinden indirme, yükleme ve gecikme ölçülüyor (~8 sn)…"

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<SpeedTestResult, Error> in
                let res = Shell.run("/usr/bin/networkQuality", ["-c", "-M", "8"])
                guard res.status == 0, let data = res.output.data(using: .utf8),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    return .failure(NSError(domain: "SpeedTest", code: Int(res.status),
                                            userInfo: [NSLocalizedDescriptionKey: "Hız testi tamamlanamadı. İnternet bağlantınızı kontrol edin."]))
                }
                let dlBits = (json["dl_throughput"] as? NSNumber)?.doubleValue ?? 0
                let ulBits = (json["ul_throughput"] as? NSNumber)?.doubleValue ?? 0
                let rtt = (json["base_rtt"] as? NSNumber)?.doubleValue
                let rpm = (json["responsiveness"] as? NSNumber)?.intValue
                    ?? (json["dl_responsiveness"] as? NSNumber)?.intValue
                let iface = (json["interface_name"] as? String) ?? "en0"

                if dlBits <= 0 && ulBits <= 0 {
                    return .failure(NSError(domain: "SpeedTest", code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: "Ölçüm verisi alınamadı."]))
                }

                return .success(SpeedTestResult(
                    downloadMbps: dlBits / 1_000_000.0,
                    uploadMbps: ulBits / 1_000_000.0,
                    idlePingMs: rtt,
                    rpm: rpm,
                    interfaceName: iface,
                    timestamp: Date()
                ))
            }.value

            self.speedTesting = false
            self.speedTestStatus = ""
            switch outcome {
            case .success(let r):
                self.lastSpeedTest = r
                self.endTask("✓ Hız testi tamamlandı")
            case .failure(let e):
                self.speedTestError = e.localizedDescription
                self.endTask()
            }
        }
    }

    // MARK: - Süpürgeç Öz Kaynak Ölçümü

    private func readSelfResources() {
        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let r = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if r == KERN_SUCCESS {
            selfMemoryBytes = Int64(vmInfo.phys_footprint)
        }

        var ri = rusage_info_v4()
        let pid = ProcessInfo.processInfo.processIdentifier
        let rr = withUnsafeMutablePointer(to: &ri) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }

        var ru = rusage()
        getrusage(RUSAGE_SELF, &ru)
        let userSec = Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1_000_000.0
        let sysSec = Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1_000_000.0
        let totalCPUSec = userSec + sysSec

        var totalDiskIO: UInt64 = selfDiskReadBytes + selfDiskWriteBytes
        if rr == 0 {
            selfDiskReadBytes = ri.ri_diskio_bytesread
            selfDiskWriteBytes = ri.ri_diskio_byteswritten
            totalDiskIO = ri.ri_diskio_bytesread + ri.ri_diskio_byteswritten
        }

        let now = Date()
        if let prev = prevSelfUsage {
            let dt = now.timeIntervalSince(prev.at)
            if dt > 0.1 {
                let dCPU = max(0, totalCPUSec - prev.cpuSec)
                let cores = Double(max(1, coreCount))
                selfCPUPercent = min(100, (dCPU / (dt * cores)) * 100.0)
                let dIO = totalDiskIO >= prev.diskIO ? Double(totalDiskIO - prev.diskIO) : 0
                selfDiskSpeedBps = dIO / dt
            }
        }
        prevSelfUsage = (totalCPUSec, totalDiskIO, now)
    }

    // MARK: - Sistem Okumaları

    private func sampleCPUTicks() -> (totalUsed: Double, user: Double, system: Double, idle: Double) {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return (cpu, cpuUser, cpuSystem, cpuIdle) }
        let t = load.cpu_ticks
        let now = (user: Double(t.0), system: Double(t.1), idle: Double(t.2), nice: Double(t.3))
        defer { prevTicks = now }
        guard let p = prevTicks else { return (0, 0, 0, 1) }
        let u = now.user - p.user + (now.nice - p.nice)
        let s = now.system - p.system
        let id = now.idle - p.idle
        let total = u + s + id
        guard total > 0 else { return (0, 0, 0, 1) }
        return (
            totalUsed: min(max((u + s) / total, 0), 1),
            user: min(max(u / total, 0), 1),
            system: min(max(s / total, 0), 1),
            idle: min(max(id / total, 0), 1)
        )
    }

    private func samplePerCoreLoads() {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCpuInfo
        )
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return }
        defer {
            let size = vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let count = Int(numCPUsU)
        var current: [(user: Double, system: Double, idle: Double)] = []
        current.reserveCapacity(count)
        var loads: [Double] = []
        loads.reserveCapacity(count)

        for i in 0..<count {
            let base = Int(CPU_STATE_MAX) * i
            let u = Double(info[base + Int(CPU_STATE_USER)]) + Double(info[base + Int(CPU_STATE_NICE)])
            let s = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let id = Double(info[base + Int(CPU_STATE_IDLE)])
            current.append((u, s, id))

            if prevCoreTicks.count == count {
                let p = prevCoreTicks[i]
                let du = u - p.user
                let ds = s - p.system
                let did = id - p.idle
                let tot = du + ds + did
                loads.append(tot > 0 ? min(max((du + ds) / tot, 0), 1) : 0)
            } else {
                loads.append(cpu)
            }
        }
        prevCoreTicks = current
        coreLoads = loads
    }

    private func readMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(sysconf(_SC_PAGESIZE))
        let purgeable = Double(stats.purgeable_count) * page
        let external = Double(stats.external_page_count) * page
        let free = Double(stats.free_count) * page
        let app = max(0, (Double(stats.internal_page_count) - Double(stats.purgeable_count)) * page)
        let wired = Double(stats.wire_count) * page
        let compressed = Double(stats.compressor_page_count) * page

        memApp = app
        memWired = wired
        memCompressed = compressed
        memCached = purgeable + external
        memFree = free
        pageIns = stats.pageins
        pageOuts = stats.pageouts
        memoryUsed = max(0, app + wired + compressed)
    }

    private func readSwap() {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            swapUsed = Double(swap.xsu_used)
            swapTotal = Double(swap.xsu_total)
        }
    }

    private func readDisk() {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey
        ]
        if let v = try? url.resourceValues(forKeys: keys),
           let total = v.volumeTotalCapacity {
            let availImportant = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
            let availImmediate = Double(v.volumeAvailableCapacity ?? Int(availImportant))
            diskTotal = Double(total)
            diskFreeImmediate = max(0, availImmediate)
            diskPurgeable = max(0, availImportant - availImmediate)
            diskUsed = max(0, Double(total) - availImportant)
            if let name = v.volumeName, !name.isEmpty { volumeName = name }
            if let fmt = v.volumeLocalizedFormatDescription, !fmt.isEmpty { fileSystemFormat = fmt }
        }
    }

    private func readNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var inB: UInt64 = 0, outB: UInt64 = 0
        var detectedIP: String?
        var detectedIF: String?
        var hasVPN = false

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            let name = String(cString: ifa.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                if let addr = ifa.ifa_addr {
                    if addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                        let d = data.assumingMemoryBound(to: if_data.self).pointee
                        inB += UInt64(d.ifi_ibytes)
                        outB += UInt64(d.ifi_obytes)
                    } else if addr.pointee.sa_family == UInt8(AF_INET), detectedIP == nil {
                        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                            let ip = String(cString: host)
                            if !ip.hasPrefix("169.254.") {
                                detectedIP = ip
                                detectedIF = name
                            }
                        }
                    }
                }
            } else if name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
                if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    hasVPN = true
                }
            }
            ptr = ifa.ifa_next
        }

        totalNetIn = inB
        totalNetOut = outB
        vpnTunnelActive = hasVPN
        if let detectedIP { localIP = detectedIP }
        if let detectedIF { activeInterface = detectedIF }

        let now = Date()
        if let prev = prevNet {
            let dt = now.timeIntervalSince(prev.at)
            if dt > 0 {
                netIn = inB >= prev.inB ? Double(inB - prev.inB) / dt : 0
                netOut = outB >= prev.outB ? Double(outB - prev.outB) / dt : 0
            }
        }
        prevNet = (inB, outB, now)
    }

    nonisolated private static func readSysctlString(_ key: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func readSysctlInt(_ key: String) -> Int {
        var val: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &val, &size, nil, 0) == 0 else { return 0 }
        return Int(val)
    }
}
