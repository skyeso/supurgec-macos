import Foundation
import AppKit

enum MenuBarIconChoice: String, CaseIterable, Identifiable {
    case none = "none"
    case broom = "paintbrush.pointed.fill"
    case sparkles = "sparkles"
    case cpu = "cpu"
    case memory = "memorychip"
    case gauge = "gauge.with.dots.needle.67percent"
    case bolt = "bolt.fill"
    case leaf = "leaf.fill"
    case shield = "shield.lefthalf.filled"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "İkon Yok (Sadece Yazı)"
        case .broom: return "Fırça / Süpürge"
        case .sparkles: return "Parıltı"
        case .cpu: return "İşlemci"
        case .memory: return "Bellek Çipi"
        case .gauge: return "Gösterge"
        case .bolt: return "Şimşek"
        case .leaf: return "Yaprak"
        case .shield: return "Kalkan"
        }
    }

    var symbolName: String? {
        self == .none ? nil : rawValue
    }
}

enum RAMDisplayFormat: String, CaseIterable, Identifiable {
    case percent = "percent"
    case gigabytes = "gb"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .percent: return "Yüzde (%65)"
        case .gigabytes: return "Gigabayt (10,4 GB)"
        }
    }
}

@MainActor
final class MenuBarSettings: ObservableObject {
    static let shared = MenuBarSettings()

    private let defaults = UserDefaults.standard

    @Published var iconChoice: MenuBarIconChoice {
        didSet { defaults.set(iconChoice.rawValue, forKey: "mb.iconChoice") }
    }
    @Published var showCPU: Bool {
        didSet {
            if !showCPU && !showRAM && !showNetwork && !showDisk && iconChoice == .none {
                iconChoice = .broom
            }
            defaults.set(showCPU, forKey: "mb.showCPU")
        }
    }
    @Published var showRAM: Bool {
        didSet {
            if !showCPU && !showRAM && !showNetwork && !showDisk && iconChoice == .none {
                iconChoice = .broom
            }
            defaults.set(showRAM, forKey: "mb.showRAM")
        }
    }
    @Published var ramFormat: RAMDisplayFormat {
        didSet { defaults.set(ramFormat.rawValue, forKey: "mb.ramFormat") }
    }
    @Published var showNetwork: Bool {
        didSet {
            if !showCPU && !showRAM && !showNetwork && !showDisk && iconChoice == .none {
                iconChoice = .broom
            }
            defaults.set(showNetwork, forKey: "mb.showNetwork")
        }
    }
    @Published var showDisk: Bool {
        didSet {
            if !showCPU && !showRAM && !showNetwork && !showDisk && iconChoice == .none {
                iconChoice = .broom
            }
            defaults.set(showDisk, forKey: "mb.showDisk")
        }
    }
    @Published var showLabels: Bool {
        didSet { defaults.set(showLabels, forKey: "mb.showLabels") }
    }
    @Published var refreshInterval: Double {
        didSet {
            defaults.set(refreshInterval, forKey: "mb.refreshInterval")
            SystemMonitor.shared.applyRefreshIntervalChange()
        }
    }

    private init() {
        let savedIcon = defaults.string(forKey: "mb.iconChoice") ?? MenuBarIconChoice.none.rawValue
        self.iconChoice = MenuBarIconChoice(rawValue: savedIcon) ?? .none
        self.showCPU = defaults.object(forKey: "mb.showCPU") as? Bool ?? true
        self.showRAM = defaults.object(forKey: "mb.showRAM") as? Bool ?? false
        let savedRAMFmt = defaults.string(forKey: "mb.ramFormat") ?? RAMDisplayFormat.percent.rawValue
        self.ramFormat = RAMDisplayFormat(rawValue: savedRAMFmt) ?? .percent
        self.showNetwork = defaults.object(forKey: "mb.showNetwork") as? Bool ?? false
        self.showDisk = defaults.object(forKey: "mb.showDisk") as? Bool ?? false
        self.showLabels = defaults.object(forKey: "mb.showLabels") as? Bool ?? true
        let savedInterval = defaults.double(forKey: "mb.refreshInterval")
        self.refreshInterval = savedInterval > 0 ? savedInterval : 2.0
    }

    var needsBackgroundMemoryOrNet: Bool {
        showRAM || showNetwork || showDisk
    }

    /// Sabit genişlik için rakamları hizalı metin üretir (tek haneden çift haneye geçerken kayma yapmaz).
    func formattedTitle(monitor: SystemMonitor) -> String {
        var parts: [String] = []
        let multi = [showCPU, showRAM, showNetwork, showDisk].filter { $0 }.count > 1

        if showCPU {
            // Rakam alanı sabit 3 karakter (Figure Space U+2007 rakamla birebir aynı piksel genişliğindedir)
            let num = padPercent(monitor.cpuPercentInt)
            let label = (showLabels && multi) ? "CPU " : ""
            parts.append("\(label)%\(num)")
        }

        if showRAM {
            let label = (showLabels && multi) ? "RAM " : (showLabels && !showCPU ? "RAM " : "")
            switch ramFormat {
            case .percent:
                let pct = Int((monitor.memoryRatio * 100).rounded())
                parts.append("\(label)%\(padPercent(pct))")
            case .gigabytes:
                let gb = monitor.memoryUsed / (1024 * 1024 * 1024)
                parts.append(String(format: "%@%.1fG", label, gb))
            }
        }

        if showNetwork {
            let mbps = monitor.netIn / (1024 * 1024)
            if mbps >= 0.1 {
                parts.append(String(format: "↓%.1fM", mbps))
            } else {
                let kbps = monitor.netIn / 1024
                parts.append(String(format: "↓%3.0fK", kbps))
            }
        }

        if showDisk {
            let freeGB = max(0, monitor.diskTotal - monitor.diskUsed) / 1_000_000_000
            parts.append(String(format: "%.0fG", freeGB))
        }

        let joined = parts.joined(separator: "  ")
        if iconChoice.symbolName != nil && !joined.isEmpty {
            return " " + joined
        }
        return joined
    }

    /// Tek/çift/üç haneli yüzdeleri sabit piksel genişliğinde tutar:
    /// %0..%9 -> "\u{2007}9", %10..%99 -> "42", %100 -> "99" (üst barda 2 hane sabit kilit)
    private func padPercent(_ v: Int) -> String {
        let clamped = min(max(v, 0), 99)
        if clamped < 10 {
            return "\u{2007}\(clamped)"
        }
        return "\(clamped)"
    }

    /// Seçili öğelere göre sabit NSStatusItem piksel genişliğini döndürür.
    func fixedBarWidth(for sampleTitle: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textWidth = (sampleTitle as NSString).size(withAttributes: [.font: font]).width
        let iconWidth: CGFloat = iconChoice.symbolName != nil ? 20 : 0
        let horizontalPadding: CGFloat = 14
        return ceil(iconWidth + textWidth + horizontalPadding)
    }

    /// Maksimum genişlikteki örnek metni oluşturarak çubuğun genişliğini sabitler.
    var maxSampleTitle: String {
        var parts: [String] = []
        let multi = [showCPU, showRAM, showNetwork, showDisk].filter { $0 }.count > 1

        if showCPU {
            let label = (showLabels && multi) ? "CPU " : ""
            parts.append("\(label)%88")
        }
        if showRAM {
            let label = (showLabels && multi) ? "RAM " : (showLabels && !showCPU ? "RAM " : "")
            switch ramFormat {
            case .percent: parts.append("\(label)%88")
            case .gigabytes: parts.append("\(label)88.8G")
            }
        }
        if showNetwork { parts.append("↓888K") }
        if showDisk { parts.append("888G") }

        let joined = parts.joined(separator: "  ")
        if iconChoice.symbolName != nil && !joined.isEmpty {
            return " " + joined
        }
        return joined
    }
}
