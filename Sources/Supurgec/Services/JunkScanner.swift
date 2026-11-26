import Foundation
import AppKit

struct JunkItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let displayLabel: String?
    var selected: Bool

    init(url: URL, size: Int64, selected: Bool, displayLabel: String? = nil) {
        self.url = url
        self.size = size
        self.selected = selected
        self.displayLabel = displayLabel
    }

    var name: String { displayLabel ?? url.lastPathComponent }
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
    enum Mode: Sendable { case children, whole, appSupportSafeCaches }

    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let defaultSelected: Bool
    let roots: [String]
    var mode: Mode = .children

    /// Sistem ve iCloud servislerinin bozulmaması için ~/Library/Caches altında dokunulmayacak korumalı öğeler.
    static let protectedCacheNames: Set<String> = [
        "com.eso.supurgec", "com.eso.pristine", ".DS_Store", ".localized",
        "CloudKit", "FamilyCircle", "com.apple.HomeKit", "com.apple.bird",
        "com.apple.nsurlsessiond", "com.apple.ap.adprivacyd", "com.apple.akd",
        "com.apple.icloud.fmfd", "com.apple.PassKit"
    ]

    /// ~/Library/Application Support altında ASLA taranmayacak macOS sistem klasörleri.
    static let protectedAppSupportVendors: Set<String> = [
        "apple", "addressbook", "callhistorydb", "callhistorytransactions",
        "clouddocs", "coreparsec", "dock", "fileprovider", "icdd", "knowledge",
        "mobilesync", "syncservices", "crashreporter", "animoji", "stickers"
    ]

    /// Yalnızca %100 geçici ve silindiğinde şifre/oturum/ayar kaybı yaratmayan alt önbellek klasör adları.
    static let safeCacheFolderNames: Set<String> = [
        "cache", "code cache", "gpucache", "dawncache", "dawnwebgpucache",
        "dawngraphitecache", "grshadercache", "shadercache", "media cache",
        "cacheddata", "cachedextensionvsixs", "persistentcache"
    ]

    func collect(runningTokens: Set<String>) -> [JunkItem] {
        if mode == .appSupportSafeCaches {
            return collectSafeAppSupportCaches(runningTokens: runningTokens)
        }

        var items: [JunkItem] = []
        for r in roots {
            let url = FileUtils.home.appendingPathComponent(r)
            guard FileUtils.exists(url) else { continue }
            let targets = mode == .children ? FileUtils.children(of: url) : [url]
            for t in targets {
                let name = t.lastPathComponent
                if Self.protectedCacheNames.contains(name) { continue }
                if id == "userCache" && name.hasPrefix("com.apple.") && name != "com.apple.dt.Xcode" {
                    // macOS çekirdek/sistem önbelleklerine zarar vermemek için com.apple.* sistem servislerini koru
                    continue
                }
                let s = FileUtils.size(of: t)
                guard s > 0 else { continue }

                // Açık olan uygulamaların ~/Library/Caches klasörünü de koruma bilinciyle işaretle
                let norm = Self.normalize(name)
                let isOpenApp = id == "userCache" && runningTokens.contains(where: { tok in
                    tok.count >= 5 && norm.contains(tok)
                })
                if isOpenApp {
                    items.append(JunkItem(
                        url: t,
                        size: s,
                        selected: false,
                        displayLabel: "\(name) (Açık uygulama — korundu)"
                    ))
                } else {
                    items.append(JunkItem(url: t, size: s, selected: defaultSelected))
                }
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// ~/Library/Application Support içindeki şifrelere, çerezlere ve ayarlara ASLA dokunmadan
    /// yalnızca geçici önbellek alt klasörlerini (Code Cache, GPUCache, Service Worker/CacheStorage vb.) bulur.
    private func collectSafeAppSupportCaches(runningTokens: Set<String>) -> [JunkItem] {
        let appSupport = FileUtils.library.appendingPathComponent("Application Support")
        guard FileUtils.exists(appSupport) else { return [] }

        var results: [JunkItem] = []

        for topDir in FileUtils.children(of: appSupport) where FileUtils.isDirectory(topDir) {
            let topName = topDir.lastPathComponent
            let topLow = topName.lowercased()
            if topName.hasPrefix(".") || topLow.hasPrefix("com.apple.") || Self.protectedAppSupportVendors.contains(topLow) {
                continue
            }

            let normTop = Self.normalize(topName)
            let topIsRunning = runningTokens.contains { tok in
                tok.count >= 4 && (normTop == tok || normTop.contains(tok) || tok.contains(normTop))
            }

            // En fazla 3 seviye derinlikte yalnızca izinli önbellek klasörlerini ara
            scanAppSupportSubtree(
                dir: topDir,
                appOwnerLabel: topName,
                parentRunning: topIsRunning,
                runningTokens: runningTokens,
                depth: 1,
                into: &results
            )
        }

        return results.sorted { $0.size > $1.size }
    }

    private func scanAppSupportSubtree(
        dir: URL,
        appOwnerLabel: String,
        parentRunning: Bool,
        runningTokens: Set<String>,
        depth: Int,
        into results: inout [JunkItem]
    ) {
        guard depth <= 3 else { return }

        for child in FileUtils.children(of: dir) where FileUtils.isDirectory(child) {
            let name = child.lastPathComponent
            if name.hasPrefix(".") { continue }
            let low = name.lowercased()

            // Özel durum: Service Worker/CacheStorage (Service Worker'ın veritabanına dokunmadan yalnızca CacheStorage!)
            if low == "service worker" {
                let cacheStorage = child.appendingPathComponent("CacheStorage")
                if FileUtils.isDirectory(cacheStorage) {
                    let s = FileUtils.size(of: cacheStorage)
                    if s > 64 * 1024 {
                        let label = parentRunning
                            ? "\(appOwnerLabel) › Service Worker Önbelleği (Açık — korundu)"
                            : "\(appOwnerLabel) › Service Worker Önbelleği"
                        results.append(JunkItem(url: cacheStorage, size: s, selected: !parentRunning, displayLabel: label))
                    }
                }
                continue
            }

            // İzinli güvenli önbellek klasörü mü?
            if Self.safeCacheFolderNames.contains(low) {
                let s = FileUtils.size(of: child)
                if s > 64 * 1024 {
                    let label = parentRunning
                        ? "\(appOwnerLabel) › \(name) (Açık — korundu)"
                        : "\(appOwnerLabel) › \(name)"
                    results.append(JunkItem(url: child, size: s, selected: !parentRunning, displayLabel: label))
                }
                // Önbellek klasörünün daha altına inmeye gerek yok
                continue
            }

            // Alt profil / ürün klasörlerine in (örn. BraveSoftware -> Brave-Browser -> Default -> Code Cache)
            if depth < 3 {
                let normChild = Self.normalize(name)
                let childRunning = parentRunning || runningTokens.contains { tok in
                    tok.count >= 4 && (normChild == tok || normChild.contains(tok))
                }
                let nextLabel = depth == 1 && !["default", "user", "profiles"].contains(low) && !low.hasPrefix("profile ")
                    ? "\(appOwnerLabel) (\(name))"
                    : appOwnerLabel
                scanAppSupportSubtree(
                    dir: child,
                    appOwnerLabel: nextLabel,
                    parentRunning: childRunning,
                    runningTokens: runningTokens,
                    depth: depth + 1,
                    into: &results
                )
            }
        }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    static let all: [JunkDefinition] = [
        .init(id: "userCache", title: "Kullanıcı Önbelleği",
              subtitle: "Uygulamaların ~/Library/Caches altında biriktirdiği geçici dosyalar. Açık uygulamalar ve sistem servisleri korunur.",
              icon: "archivebox.fill", defaultSelected: true, roots: ["Library/Caches"]),
        .init(id: "appSupportCache", title: "Uygulama İçi Gizli Önbellekler",
              subtitle: "Tarayıcı, Discord, Spotify, VS Code gibi uygulamaların Application Support altındaki geçici GPU, Kod ve Service Worker önbellekleri. Şifre ve oturumlara dokunulmaz; açık uygulamalar korunur.",
              icon: "square.stack.3d.down.right.fill", defaultSelected: true, roots: ["Library/Application Support"],
              mode: .appSupportSafeCaches),
        .init(id: "logs", title: "Kullanıcı Günlükleri",
              subtitle: "Uygulamaların yazdığı günlük (log) ve eski tanılama dosyaları.",
              icon: "doc.text.fill", defaultSelected: true, roots: ["Library/Logs"]),
        .init(id: "xcode", title: "Xcode Çöpü",
              subtitle: "DerivedData, eski iOS cihaz destek dosyaları ve simülatör önbellekleri.",
              icon: "hammer.fill", defaultSelected: true,
              roots: ["Library/Developer/Xcode/DerivedData",
                      "Library/Developer/Xcode/iOS DeviceSupport",
                      "Library/Developer/CoreSimulator/Caches"]),
        .init(id: "dev", title: "Geliştirici Paket Önbellekleri",
              subtitle: "npm, Gradle, pip, bun ve benzeri paket yöneticilerinin indirme önbellekleri.",
              icon: "chevron.left.forwardslash.chevron.right", defaultSelected: true,
              roots: [".npm/_cacache", ".gradle/caches", ".cache/pip", ".cache/huggingface/xet", ".bun/install/cache"],
              mode: .whole),
        .init(id: "savedState", title: "Kaydedilmiş Pencere Durumları",
              subtitle: "Kapatılan uygulamaların eski pencere konumlarını tutan geçici durum dosyaları.",
              icon: "macwindow", defaultSelected: true, roots: ["Library/Saved Application State"]),
        .init(id: "mail", title: "Yerel Mail Ekleri",
              subtitle: "Mail uygulamasının önbelleğe indirdiği ek kopyaları. Orijinalleri posta sunucunuzda durur.",
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

    /// Şu an açık olan uygulamaların normalize isimlerini çıkarır (açık uygulamalara zarar vermemek için!).
    static func activeRunningTokens() -> Set<String> {
        var tokens: Set<String> = ["supurgec", "antigravity", "finder", "dock"]
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName {
                let n = JunkDefinition.normalize(name)
                if n.count >= 4 { tokens.insert(n) }
                // Örn: "Brave Browser" -> "brave", "Google Chrome" -> "chrome"
                for part in name.split(separator: " ") {
                    let p = JunkDefinition.normalize(String(part))
                    if p.count >= 5 && p != "browser" && p != "helper" {
                        tokens.insert(p)
                    }
                }
            }
            if let bid = app.bundleIdentifier {
                let parts = bid.split(separator: ".")
                if let last = parts.last {
                    let l = JunkDefinition.normalize(String(last))
                    if l.count >= 4 && l != "browser" && l != "macos" {
                        tokens.insert(l)
                    }
                }
            }
        }
        return tokens
    }

    func scan() async {
        guard phase != .scanning && phase != .cleaning else { return }
        phase = .scanning
        SystemMonitor.shared.beginTask("Sistem Çöpü taranıyor…", gpuAnimated: true)
        categories = []
        let running = Self.activeRunningTokens()

        for def in JunkDefinition.all {
            currentPath = "~/" + (def.roots.first ?? "")
            SystemMonitor.shared.updateTask("Taranıyor: \(def.title)…")
            let items = await Task.detached(priority: .userInitiated) { def.collect(runningTokens: running) }.value
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
