import Foundation

struct JunkItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    var selected: Bool
    var name: String { url.lastPathComponent }
}

struct JunkCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    var items: [JunkItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.reduce(0) { $0 + ($1.selected ? $1.size : 0) } }
    var allSelected: Bool { !items.isEmpty && items.allSatisfy(\.selected) }
    var anySelected: Bool { items.contains(where: \.selected) }
}

struct JunkDefinition: Sendable {
    enum Mode: Sendable { case children, whole }

    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let defaultSelected: Bool
    let roots: [String]   // ev dizinine göre
    var mode: Mode = .children

    static let protectedNames: Set<String> = ["com.eso.supurgec", "com.eso.pristine", ".DS_Store", ".localized"]

    func collect() -> [JunkItem] {
        var items: [JunkItem] = []
        for r in roots {
            let url = FileUtils.home.appendingPathComponent(r)
            guard FileUtils.exists(url) else { continue }
            let targets = mode == .children ? FileUtils.children(of: url) : [url]
            for t in targets where !Self.protectedNames.contains(t.lastPathComponent) {
                let s = FileUtils.size(of: t)
                if s > 0 { items.append(JunkItem(url: t, size: s, selected: defaultSelected)) }
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    static let all: [JunkDefinition] = [
        .init(id: "userCache", title: "Kullanıcı Önbelleği",
              subtitle: "Uygulamaların biriktirdiği geçici önbellek dosyaları. Gerektiğinde yeniden oluşturulur.",
              icon: "archivebox.fill", defaultSelected: true, roots: ["Library/Caches"]),
        .init(id: "logs", title: "Kullanıcı Günlükleri",
              subtitle: "Uygulamaların yazdığı günlük (log) ve tanılama dosyaları.",
              icon: "doc.text.fill", defaultSelected: true, roots: ["Library/Logs"]),
        .init(id: "xcode", title: "Xcode Çöpü",
              subtitle: "DerivedData, eski iOS cihaz destek dosyaları ve simülatör önbellekleri.",
              icon: "hammer.fill", defaultSelected: true,
              roots: ["Library/Developer/Xcode/DerivedData",
                      "Library/Developer/Xcode/iOS DeviceSupport",
                      "Library/Developer/CoreSimulator/Caches"]),
        .init(id: "dev", title: "Geliştirici Önbellekleri",
              subtitle: "npm, Gradle, pip ve benzeri paket yöneticilerinin önbellekleri.",
              icon: "chevron.left.forwardslash.chevron.right", defaultSelected: true,
              roots: [".npm/_cacache", ".gradle/caches", ".cache/pip", ".cache/huggingface/xet", ".bun/install/cache"],
              mode: .whole),
        .init(id: "savedState", title: "Kaydedilmiş Uygulama Durumları",
              subtitle: "Uygulama pencerelerini yeniden açmak için tutulan durum dosyaları.",
              icon: "macwindow", defaultSelected: true, roots: ["Library/Saved Application State"]),
        .init(id: "mail", title: "Mail Ekleri",
              subtitle: "Mail uygulamasının indirdiği ek dosyaları. Orijinalleri postalarınızda durur.",
              icon: "envelope.fill", defaultSelected: false,
              roots: ["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"]),
        .init(id: "trash", title: "Çöp Kutusu",
              subtitle: "Çöp Kutusu'ndaki öğeler kalıcı olarak silinir.",
              icon: "trash.fill", defaultSelected: false, roots: [".Trash"]),
    ]
}

@MainActor
final class JunkScanner: ObservableObject {
    enum Phase { case idle, scanning, results, cleaning, done }

    @Published var phase: Phase = .idle
    @Published var categories: [JunkCategory] = []
    @Published var currentPath = ""
    @Published var cleanedBytes: Int64 = 0

    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var totalSize: Int64 { categories.reduce(0) { $0 + $1.totalSize } }

    func scan() async {
        guard phase != .scanning && phase != .cleaning else { return }
        phase = .scanning
        SystemMonitor.shared.beginTask("Sistem Çöpü taranıyor…", gpuAnimated: true)
        categories = []
        for def in JunkDefinition.all {
            currentPath = "~/" + (def.roots.first ?? "")
            SystemMonitor.shared.updateTask("Taranıyor: \(def.title)…")
            let items = await Task.detached(priority: .userInitiated) { def.collect() }.value
            if !items.isEmpty {
                categories.append(JunkCategory(id: def.id, title: def.title, subtitle: def.subtitle,
                                               icon: def.icon, items: items))
            }
        }
        currentPath = ""
        SystemMonitor.shared.endTask("✓ Çöp taraması tamamlandı")
        phase = .results
    }

    func clean() async {
        let targets = categories.flatMap { $0.items.filter(\.selected) }.map { (url: $0.url, size: $0.size) }
        guard !targets.isEmpty else { return }
        phase = .cleaning
        SystemMonitor.shared.beginTask("Gereksiz dosyalar temizleniyor…", gpuAnimated: true)
        let freed = await Task.detached(priority: .userInitiated) { [weak self] () -> Int64 in
            FileUtils.remove(targets) { path in
                Task { @MainActor in self?.currentPath = path }
            }
        }.value
        cleanedBytes = freed
        currentPath = ""
        categories = []
        SystemMonitor.shared.endTask("✓ \(freed.formattedBytes) temizlendi")
        phase = .done
    }

    func setCategory(_ id: String, selected: Bool) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        for j in categories[i].items.indices { categories[i].items[j].selected = selected }
    }

    func reset() { phase = .idle; categories = []; cleanedBytes = 0 }
}
