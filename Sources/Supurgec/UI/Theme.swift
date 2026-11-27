import SwiftUI

/// macOS CommandLineTools ortamında SwiftUIMacros eklentisi olmadan da
/// SwiftUI.State propertyWrapper'ını doğrudan kullanmak için tür takma adı.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Notification.Name {
    static let navigateToModule = Notification.Name("SupurgecNavigateToModule")
}

enum NavModule: String, CaseIterable, Identifiable {
    case smartScan
    case memoryMonitor
    case cpuMonitor
    case diskMonitor
    case networkMonitor
    case systemJunk
    case uninstaller
    case optimization
    case maintenance
    case settings

    var id: String { rawValue }

    var isLiveMonitor: Bool {
        switch self {
        case .memoryMonitor, .cpuMonitor, .diskMonitor, .networkMonitor:
            return true
        default:
            return false
        }
    }

    var section: String {
        switch self {
        case .smartScan: return "Genel"
        case .memoryMonitor, .cpuMonitor, .diskMonitor, .networkMonitor: return "Canlı İzleyici"
        case .systemJunk: return "Temizlik"
        case .optimization, .maintenance: return "Hız"
        case .uninstaller: return "Uygulamalar"
        case .settings: return "Tercihler"
        }
    }

    var title: String {
        switch self {
        case .smartScan: return "Akıllı Tarama"
        case .memoryMonitor: return "Bellek"
        case .cpuMonitor: return "İşlemci"
        case .diskMonitor: return "Disk"
        case .networkMonitor: return "Ağ"
        case .systemJunk: return "Sistem Çöpü"
        case .uninstaller: return "Kaldırıcı"
        case .optimization: return "Optimizasyon"
        case .maintenance: return "Bakım"
        case .settings: return "Ayarlar"
        }
    }

    var subtitle: String {
        switch self {
        case .smartScan:
            return "Mac'inizi tek dokunuşla analiz edin: gereksiz dosyaları temizleyin, başlangıç öğelerini denetleyin ve performansı artırın."
        case .memoryMonitor:
            return "Belleğinizi kullanan tüm uygulamaları, alt süreçlerini, bağlı/sıkıştırılmış RAM dağılımını ve takas (swap) sağlığını tüm detaylarıyla inceleyin."
        case .cpuMonitor:
            return "Çekirdek bazlı anlık işlemci yükünü, sistem/kullanıcı dağılımını ve işlemciyi kullanan tüm uygulamaları canlı olarak takip edin."
        case .diskMonitor:
            return "APFS depolama dağılımını, temizlenebilir sistem önbelleğini, klasör bazlı alan kullanımını ve unutulmuş büyük dosyaları keşfedin."
        case .networkMonitor:
            return "Hangi uygulamanın anlık ne kadar veri indirip yüklediğini, ağ geçidi/DNS detaylarını ve bağlantı kalitenizi canlı izleyin."
        case .systemJunk:
            return "Önbellekleri, günlükleri, Xcode ve geliştirici kalıntılarını temizleyerek diskinizde güvenli şekilde yer açın."
        case .uninstaller:
            return "İstemediğiniz uygulamaları arkalarında bıraktıkları tüm gizli destek ve önbellek dosyalarıyla birlikte kaldırın."
        case .optimization:
            return "Mac'inizin açılışında başlayan servisleri anlaşılır açıklamalarla yönetin ve kaynak tüketen uygulamaları denetleyin."
        case .maintenance:
            return "RAM boşaltma, DNS önbelleği sıfırlama ve Spotlight indeksleme gibi bakım betikleriyle sisteminizi tazeleyin."
        case .settings:
            return "Üst menü çubuğu görünümünü kişiselleştirin, izinleri yönetin ve Süpürgeç'in kendi anlık kaynak tüketimini izleyin."
        }
    }

    var icon: String {
        switch self {
        case .smartScan: return "paintbrush.pointed.fill"
        case .memoryMonitor: return "memorychip"
        case .cpuMonitor: return "cpu.fill"
        case .diskMonitor: return "internaldrive.fill"
        case .networkMonitor: return "network"
        case .systemJunk: return "trash.circle.fill"
        case .uninstaller: return "xmark.app.fill"
        case .optimization: return "gauge.with.dots.needle.67percent"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var heroSymbol: String {
        switch self {
        case .smartScan: return "paintbrush.pointed.fill"
        case .memoryMonitor: return "memorychip.fill"
        case .cpuMonitor: return "cpu.fill"
        case .diskMonitor: return "internaldrive.fill"
        case .networkMonitor: return "waveform.path.ecg"
        case .systemJunk: return "externaldrive.fill.badge.minus"
        case .uninstaller: return "square.stack.3d.up.slash.fill"
        case .optimization: return "bolt.shield.fill"
        case .maintenance: return "gearshape.2.fill"
        case .settings: return "slider.horizontal.3"
        }
    }

    var accentColors: [Color] {
        switch self {
        case .smartScan:
            return [Color(red: 0.25, green: 0.78, blue: 1.00), Color(red: 0.58, green: 0.35, blue: 0.98), Color(red: 0.98, green: 0.34, blue: 0.66)]
        case .memoryMonitor:
            return [Color(red: 0.20, green: 0.88, blue: 0.64), Color(red: 0.16, green: 0.72, blue: 0.96), Color(red: 0.48, green: 0.38, blue: 0.96)]
        case .cpuMonitor:
            return [Color(red: 0.68, green: 0.40, blue: 1.00), Color(red: 0.96, green: 0.36, blue: 0.68), Color(red: 0.28, green: 0.68, blue: 1.00)]
        case .diskMonitor:
            return [Color(red: 0.22, green: 0.78, blue: 1.00), Color(red: 0.38, green: 0.48, blue: 0.98), Color(red: 0.92, green: 0.36, blue: 0.68)]
        case .networkMonitor:
            return [Color(red: 0.18, green: 0.84, blue: 0.88), Color(red: 0.20, green: 0.60, blue: 0.98), Color(red: 0.98, green: 0.60, blue: 0.24)]
        case .systemJunk:
            return [Color(red: 0.99, green: 0.34, blue: 0.62), Color(red: 0.88, green: 0.26, blue: 0.78), Color(red: 0.42, green: 0.36, blue: 0.96)]
        case .uninstaller:
            return [Color(red: 0.20, green: 0.66, blue: 1.00), Color(red: 0.32, green: 0.42, blue: 0.98), Color(red: 0.62, green: 0.32, blue: 0.95)]
        case .optimization:
            return [Color(red: 1.00, green: 0.62, blue: 0.22), Color(red: 0.98, green: 0.36, blue: 0.52), Color(red: 0.68, green: 0.28, blue: 0.92)]
        case .maintenance:
            return [Color(red: 0.68, green: 0.36, blue: 1.00), Color(red: 0.96, green: 0.35, blue: 0.68), Color(red: 0.26, green: 0.72, blue: 0.98)]
        case .settings:
            return [Color(red: 0.22, green: 0.82, blue: 0.86), Color(red: 0.40, green: 0.48, blue: 0.98), Color(red: 0.88, green: 0.36, blue: 0.72)]
        }
    }

    var primaryAccent: Color { accentColors[0] }

    var backdropColors: [Color] {
        switch self {
        case .smartScan:
            return [Color(red: 0.10, green: 0.10, blue: 0.20), Color(red: 0.07, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .memoryMonitor:
            return [Color(red: 0.07, green: 0.14, blue: 0.18), Color(red: 0.07, green: 0.09, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .cpuMonitor:
            return [Color(red: 0.13, green: 0.09, blue: 0.22), Color(red: 0.08, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .diskMonitor:
            return [Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.07, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .networkMonitor:
            return [Color(red: 0.07, green: 0.13, blue: 0.21), Color(red: 0.07, green: 0.09, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .systemJunk:
            return [Color(red: 0.15, green: 0.09, blue: 0.19), Color(red: 0.08, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .uninstaller:
            return [Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.07, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .optimization:
            return [Color(red: 0.16, green: 0.10, blue: 0.17), Color(red: 0.09, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .maintenance:
            return [Color(red: 0.13, green: 0.09, blue: 0.21), Color(red: 0.08, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .settings:
            return [Color(red: 0.09, green: 0.13, blue: 0.21), Color(red: 0.07, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.10)]
        }
    }
}

enum Theme {
    static let sidebarSolid = Color(red: 0.065, green: 0.070, blue: 0.125)
    static let cardSolid = Color(red: 0.115, green: 0.120, blue: 0.195)
    static let cardFill = Color(red: 0.125, green: 0.130, blue: 0.210).opacity(0.82)
    static let cardHover = Color.white.opacity(0.085)
    static let cardStroke = Color.white.opacity(0.11)
    static let subtleText = Color.white.opacity(0.70)
    static let faintText = Color.white.opacity(0.46)
    static let successGreen = Color(red: 0.22, green: 0.88, blue: 0.62)
}
