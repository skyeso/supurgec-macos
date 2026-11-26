import Foundation

@MainActor
final class SmartScanModel: ObservableObject {
    enum Phase {
        case idle
        case scanning
        case results
        case running
        case done
    }

    enum StepState {
        case waiting
        case active
        case finished
    }

    @Published var phase: Phase = .idle
    @Published var cleanupState: StepState = .waiting
    @Published var speedState: StepState = .waiting
    @Published var optState: StepState = .waiting

    @Published var currentSubtitle: String = ""
    @Published var runCleanJunk: Bool = true
    @Published var runFlushDNSAndCache: Bool = true
    @Published var freedBytes: Int64 = 0
    @Published var ranTasksCount: Int = 0

    let junkScanner: JunkScanner
    let optimization: OptimizationModel
    let maintenance: MaintenanceModel

    var hasPasswordlessHelper: Bool {
        FileManager.default.fileExists(atPath: Shell.sudoersPath)
    }

    init(junkScanner: JunkScanner, optimization: OptimizationModel, maintenance: MaintenanceModel) {
        self.junkScanner = junkScanner
        self.optimization = optimization
        self.maintenance = maintenance
    }

    func startScan() async {
        guard phase != .scanning && phase != .running else { return }
        phase = .scanning
        SystemMonitor.shared.beginTask("Akıllı Tarama yürütülüyor…", gpuAnimated: true)
        cleanupState = .active
        speedState = .waiting
        optState = .waiting
        freedBytes = 0
        ranTasksCount = 0

        // 1. Sistem Çöpü ve Güvenli Uygulama İçi Önbellek Taraması
        currentSubtitle = "Sistem önbellekleri, günlükler ve uygulama kalıntıları taranıyor…"
        SystemMonitor.shared.updateTask("Akıllı Tarama: Sistem çöpü inceleniyor…")
        await junkScanner.scan()
        cleanupState = .finished

        // 2. Hız & Bakım Analizi
        speedState = .active
        currentSubtitle = "RAM, DNS ve sistem önbellek görevleri kontrol ediliyor…"
        SystemMonitor.shared.updateTask("Akıllı Tarama: Hız görevleri denetleniyor…")
        try? await Task.sleep(for: .milliseconds(500))
        speedState = .finished

        // 3. Optimizasyon & Başlangıç Öğeleri
        optState = .active
        currentSubtitle = "Başlangıç servisleri ve işlemci yükü inceleniyor…"
        SystemMonitor.shared.updateTask("Akıllı Tarama: Servisler analiz ediliyor…")
        optimization.refreshLaunchAgents()
        optimization.refreshProcesses()
        try? await Task.sleep(for: .milliseconds(500))
        optState = .finished

        runCleanJunk = junkScanner.selectedSize > 0
        runFlushDNSAndCache = true
        currentSubtitle = ""
        SystemMonitor.shared.endTask("✓ Akıllı Tarama tamamlandı")
        phase = .results
    }

    func executeSmartClean() async {
        guard phase == .results else { return }
        phase = .running
        SystemMonitor.shared.beginTask("Akıllı Bakım uygulanıyor…", gpuAnimated: true)
        var freed: Int64 = 0
        var taskCount = 0

        if runCleanJunk && junkScanner.selectedSize > 0 {
            currentSubtitle = "Gereksiz önbellek ve günlük dosyaları temizleniyor…"
            SystemMonitor.shared.updateTask("Akıllı Bakım: Çöp dosyaları siliniyor…")
            await junkScanner.clean()
            freed = junkScanner.cleanedBytes
        }

        if runFlushDNSAndCache {
            // Tek seferlik şifresiz yetki kuruluysa RAM boşaltma ve DNS sıfırlamayı da şifre sormadan çalıştır!
            if hasPasswordlessHelper {
                currentSubtitle = "Etkin olmayan RAM boşaltılıyor ve DNS önbelleği yenileniyor…"
                SystemMonitor.shared.updateTask("Akıllı Bakım: RAM ve DNS tazeleniyor…")
                if await Shell.freeRAMPasswordlessOrSetup() { taskCount += 1 }
                if await Shell.flushDNSPasswordlessOrSetup() { taskCount += 1 }
            }

            currentSubtitle = "Quick Look ve Launch Services önbellekleri yenileniyor…"
            SystemMonitor.shared.updateTask("Akıllı Bakım: Hız betikleri çalıştırılıyor…")
            let cmds = [
                "qlmanage -r cache; qlmanage -r",
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"
            ]
            for cmd in cmds {
                let r = await Task.detached { Shell.run("/bin/zsh", ["-c", cmd]) }.value
                if r.status == 0 { taskCount += 1 }
            }
        }

        SystemMonitor.shared.updateFull()
        freedBytes = freed
        ranTasksCount = taskCount
        currentSubtitle = ""
        SystemMonitor.shared.endTask("✓ Akıllı Bakım tamamlandı")
        phase = .done
    }

    func reset() {
        phase = .idle
        cleanupState = .waiting
        speedState = .waiting
        optState = .waiting
        currentSubtitle = ""
    }
}
