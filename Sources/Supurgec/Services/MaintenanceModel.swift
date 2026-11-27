import Foundation

struct MaintenanceTask: Identifiable {
    enum Status { case idle, running, done, failed }
    let id: String
    let title: String
    let detail: String
    let icon: String
    let admin: Bool
    let oneTimeAuth: Bool
    let command: String
    var selected: Bool
    var status: Status = .idle
}

@MainActor
final class MaintenanceModel: ObservableObject {
    @Published var tasks: [MaintenanceTask] = [
        .init(id: "ram", title: "RAM'i Boşalt",
              detail: "Etkin olmayan bellek sayfalarını serbest bırakarak uygulamalara daha fazla kullanılabilir bellek açar.",
              icon: "memorychip", admin: true, oneTimeAuth: true, command: "purge", selected: true),
        .init(id: "dns", title: "DNS Önbelleğini Temizle",
              detail: "Web siteleri açılmıyor veya eski IP adreslerine yönleniyorsa DNS çözümleme önbelleğini sıfırlar.",
              icon: "network", admin: true, oneTimeAuth: true,
              command: "dscacheutil -flushcache; killall -HUP mDNSResponder", selected: true),
        .init(id: "ls", title: "Launch Services'i Yeniden Oluştur",
              detail: "'Birlikte Aç' menüsündeki yinelenen veya silinmiş uygulama kayıtlarını temizler.",
              icon: "square.stack.3d.up.fill", admin: false, oneTimeAuth: false,
              command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -gc -r -all local,system,user",
              selected: true),
        .init(id: "ql", title: "Quick Look Önbelleğini Sıfırla",
              detail: "Bozuk veya eski küçük resim ve dosya önizlemelerini yeniler.",
              icon: "eye.fill", admin: false, oneTimeAuth: false,
              command: "qlmanage -r cache; qlmanage -r", selected: true),
        .init(id: "spotlight", title: "Spotlight'ı Yeniden İndeksle",
              detail: "Arama sonuçları eksik veya hatalıysa Spotlight dizinini baştan oluşturur.",
              icon: "magnifyingglass", admin: true, oneTimeAuth: false, command: "mdutil -E /", selected: false),
        .init(id: "fonts", title: "Font Önbelleğini Temizle",
              detail: "Bozuk görünen yazı tiplerini düzeltir. Sonrasında yeniden başlatma önerilir.",
              icon: "textformat", admin: false, oneTimeAuth: false,
              command: "atsutil databases -removeUser", selected: false),
        .init(id: "snapshots", title: "Yerel Time Machine Anlık Görüntülerini Sil",
              detail: "Diskte yer kaplayan yerel Time Machine anlık görüntülerini inceltir.",
              icon: "clock.arrow.circlepath", admin: true, oneTimeAuth: false,
              command: "tmutil thinlocalsnapshots / 999999999999 4", selected: false),
        .init(id: "dock", title: "Dock ve Finder'ı Yeniden Başlat",
              detail: "Takılan veya yanıt vermeyen Dock ve Finder süreçlerini tazeler.",
              icon: "dock.rectangle", admin: false, oneTimeAuth: false,
              command: "killall Dock; killall Finder", selected: false),
    ]
    @Published var running = false
    @Published var finished = false

    var selectedCount: Int { tasks.filter(\.selected).count }

    func runSelected() async {
        let sel = tasks.indices.filter { tasks[$0].selected }
        guard !sel.isEmpty else { return }
        running = true
        finished = false
        SystemMonitor.shared.beginTask("Bakım görevleri çalıştırılıyor…", gpuAnimated: true)
        for i in tasks.indices { tasks[i].status = tasks[i].selected ? .running : .idle }

        // 1. Yönetici yetkisi gerektirmeyen görevler
        for i in sel where !tasks[i].admin {
            SystemMonitor.shared.updateTask("Bakım: \(tasks[i].title)…")
            let taskID = tasks[i].id
            let cmd = tasks[i].command
            let r = await Task.detached { () -> (status: Int32, output: String) in
                if taskID == "ls" {
                    let lsreg = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
                    let modern = Shell.run(lsreg, ["-gc", "-r", "-all", "local,system,user"])
                    if modern.status == 0 { return modern }
                    let legacy = Shell.run(lsreg, ["-r", "-domain", "local", "-domain", "system", "-domain", "user"])
                    if legacy.status == 0 { return legacy }
                    return Shell.run(lsreg, ["-gc"])
                }
                return Shell.run("/bin/zsh", ["-c", cmd])
            }.value
            tasks[i].status = r.status == 0 ? .done : .failed
        }

        // 2. Tek seferlik parola destekli görevler (RAM & DNS)
        for i in sel where tasks[i].oneTimeAuth {
            SystemMonitor.shared.updateTask("Bakım: \(tasks[i].title)…")
            let ok: Bool
            if tasks[i].id == "ram" {
                ok = await Shell.freeRAMPasswordlessOrSetup()
            } else {
                ok = await Shell.flushDNSPasswordlessOrSetup()
            }
            tasks[i].status = ok ? .done : .failed
        }

        // 3. Kalan tam yönetici görevleri (Spotlight / Time Machine)
        let otherAdmin = sel.filter { tasks[$0].admin && !tasks[$0].oneTimeAuth }
        if !otherAdmin.isEmpty {
            SystemMonitor.shared.updateTask("Bakım: Sistem görevleri yürütülüyor…")
            await Task.yield()
            let cmd = otherAdmin.map { tasks[$0].command }.joined(separator: "; ")
            let r = Shell.runAsAdmin(cmd)
            for i in otherAdmin { tasks[i].status = r.ok ? .done : .failed }
        }

        running = false
        finished = true
        SystemMonitor.shared.endTask("✓ Bakım görevleri tamamlandı")
    }

    func reset() {
        finished = false
        for i in tasks.indices { tasks[i].status = .idle }
    }
}
