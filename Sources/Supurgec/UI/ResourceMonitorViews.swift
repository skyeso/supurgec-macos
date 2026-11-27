import SwiftUI
import AppKit

// MARK: - Ortak Üst Başlık ve Hızlı Modül Geçiş Çubuğu

private struct MonitorTopBar: View {
    let current: NavModule
    var onNavigate: (NavModule) -> Void

    private let tabs: [NavModule] = [.memoryMonitor, .cpuMonitor, .diskMonitor, .networkMonitor]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Image(systemName: current.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(current.primaryAccent)
                    Text("\(current.title) Merkezi")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text(current.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    let active = (tab == current)
                    Button {
                        onNavigate(tab)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 12, weight: active ? .bold : .medium, design: .rounded))
                        }
                        .foregroundStyle(active ? .white : Theme.subtleText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(
                                    active
                                        ? LinearGradient(colors: tab.accentColors, startPoint: .leading, endPoint: .trailing)
                                        : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.11), lineWidth: 1))
            )
        }
    }
}

private struct MetricExplainCard: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.faintText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

private func formatDurationSeconds(_ sec: Double) -> String {
    let total = Int(sec)
    let hrs = total / 3600
    let mins = (total % 3600) / 60
    let secs = total % 60
    if hrs > 0 {
        return String(format: "%dsa %02ddk", hrs, mins)
    }
    return String(format: "%02d:%02d", mins, secs)
}

private func formatNetworkRate(_ bps: Double) -> String {
    if bps < 1024 { return String(format: "%.0f B/sn", bps) }
    if bps < 1024 * 1024 { return String(format: "%.1f KB/sn", bps / 1024) }
    return String(format: "%.2f MB/sn", bps / (1024 * 1024))
}

// MARK: - 1. BELLEK (RAM) MERKEZİ

struct MemoryMonitorDetailView: View {
    enum Mode: String, CaseIterable {
        case grouped = "Uygulama Grupları"
        case flat = "Tüm Süreçler (PID)"
    }
    enum SortBy: String, CaseIterable {
        case memory = "Bellek (Çoktan Aza)"
        case cpu = "CPU Yükü"
        case count = "Alt Süreç Sayısı"
        case name = "İsim (A–Z)"
    }

    @ObservedObject var monitor = SystemMonitor.shared
    @ObservedObject var inspector: ResourceInspectorModel
    var onNavigate: (NavModule) -> Void

    @ViewState private var mode: Mode = .grouped
    @ViewState private var sortBy: SortBy = .memory
    @ViewState private var includeSystem = true
    @ViewState private var searchText = ""
    @ViewState private var expandedGroups: Set<String> = []
    @ViewState private var freeingRAM = false
    @ViewState private var ramFeedback: String?

    private var pressureInfo: (label: String, color: Color, summary: String) {
        let ratio = monitor.memoryRatio
        if monitor.swapUsed > 1.5 * 1024 * 1024 * 1024 || ratio > 0.90 {
            return (
                "Yüksek Bellek Baskısı",
                .pink,
                "Fiziksel RAM yoğun dolu ve SSD üzerinde takas (swap) aktif kullanılıyor. Kullanmadığınız ağır uygulamaları kapatmanız veya RAM boşaltmanız hız kazandırır."
            )
        } else if monitor.swapUsed > 256 * 1024 * 1024 || ratio > 0.76 {
            return (
                "Dengeli · Orta Yoğunluk",
                .orange,
                "macOS pasif bellek sayfalarını sıkıştırarak çoklu görevi dengeliyor. Günlük kullanımda herhangi bir yavaşlama beklenmez."
            )
        }
        return (
            "Sağlıklı · Düşük Baskı",
            Theme.successGreen,
            "Bellek alanı gayet rahat. macOS boşta kalan RAM'i dosya önbelleği olarak değerlendirip uygulamalarınızın anında açılmasını sağlıyor."
        )
    }

    private var filteredGroups: [DetailedProcessGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = inspector.processGroups.filter { g in
            if !includeSystem && g.isSystemDaemon { return false }
            if q.isEmpty { return true }
            return g.name.lowercased().contains(q)
                || "\(g.rootPID)".contains(q)
                || g.subprocesses.contains { $0.name.lowercased().contains(q) || "\($0.pid)".contains(q) }
        }
        switch sortBy {
        case .memory:
            return base.sorted { $0.memoryBytes != $1.memoryBytes ? $0.memoryBytes > $1.memoryBytes : $0.cpuPercent > $1.cpuPercent }
        case .cpu:
            return base.sorted { abs($0.cpuPercent - $1.cpuPercent) > 0.05 ? $0.cpuPercent > $1.cpuPercent : $0.memoryBytes > $1.memoryBytes }
        case .count:
            return base.sorted { $0.processCount != $1.processCount ? $0.processCount > $1.processCount : $0.memoryBytes > $1.memoryBytes }
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var filteredFlat: [SingleProcessEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = inspector.flatProcesses.filter { p in
            if !includeSystem && p.isSystem { return false }
            if q.isEmpty { return true }
            return p.name.lowercased().contains(q) || "\(p.pid)".contains(q) || p.ownerLabel.lowercased().contains(q)
        }
        switch sortBy {
        case .memory, .count:
            return base.sorted { $0.memoryBytes != $1.memoryBytes ? $0.memoryBytes > $1.memoryBytes : $0.cpuPercent > $1.cpuPercent }
        case .cpu:
            return base.sorted { abs($0.cpuPercent - $1.cpuPercent) > 0.05 ? $0.cpuPercent > $1.cpuPercent : $0.memoryBytes > $1.memoryBytes }
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MonitorTopBar(current: .memoryMonitor, onNavigate: onNavigate)

                // Panoramik RAM Dağılım Kartı
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(monitor.memoryUsed.formattedMemory) / \(monitor.memoryTotal.formattedMemory)")
                                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                        .monospacedDigit()

                                    Text(String(format: "%%%.0f Kullanımda", monitor.memoryRatio * 100))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(pressureInfo.color)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(pressureInfo.color.opacity(0.16)))
                                }

                                Text("\(pressureInfo.label) — \(pressureInfo.summary)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.subtleText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Button {
                                freeRAMAction()
                            } label: {
                                HStack(spacing: 7) {
                                    if freeingRAM {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(freeingRAM ? "Temizleniyor…" : "RAM Boşalt")
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: NavModule.memoryMonitor.accentColors,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(freeingRAM)
                        }

                        if let msg = ramFeedback ?? inspector.actionFeedback {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Theme.successGreen)
                                Text(msg)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.successGreen.opacity(0.14)))
                        }

                        // Çok Katmanlı Görsel RAM Çubuğu
                        GeometryReader { geo in
                            let tot = max(1, monitor.memoryTotal)
                            let wApp = max(0, geo.size.width * (monitor.memApp / tot))
                            let wWired = max(0, geo.size.width * (monitor.memWired / tot))
                            let wComp = max(0, geo.size.width * (monitor.memCompressed / tot))
                            let wCache = max(0, geo.size.width * (monitor.memCached / tot))
                            HStack(spacing: 2) {
                                Rectangle().fill(Color.cyan).frame(width: wApp)
                                Rectangle().fill(Color.purple).frame(width: wWired)
                                Rectangle().fill(Color.orange).frame(width: wComp)
                                Rectangle().fill(Theme.successGreen.opacity(0.75)).frame(width: wCache)
                                Rectangle().fill(Color.white.opacity(0.08))
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 14)

                        // 6 Detaylı Bellek Kutusu
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            MetricExplainCard(
                                title: "Uygulama Belleği",
                                value: monitor.memApp.formattedMemory,
                                detail: "Açık uygulama ve belgelerin aktif RAM kullanımı",
                                color: .cyan
                            )
                            MetricExplainCard(
                                title: "Bağlı (Wired) Bellek",
                                value: monitor.memWired.formattedMemory,
                                detail: "macOS çekirdeğinin kilitlediği kritik sistem belleği",
                                color: .purple
                            )
                            MetricExplainCard(
                                title: "Sıkıştırılmış (Compressed)",
                                value: monitor.memCompressed.formattedMemory,
                                detail: "Yer açmak için sıkıştırılan pasif bellek sayfaları",
                                color: .orange
                            )
                            MetricExplainCard(
                                title: "Önbellek + Hazır Alan",
                                value: (monitor.memCached + monitor.memFree).formattedMemory,
                                detail: "İhtiyaç anında uygulamalara anında verilebilen alan",
                                color: Theme.successGreen
                            )
                            MetricExplainCard(
                                title: "Takas Alanı (SSD Swap)",
                                value: monitor.swapTotal > 0
                                    ? "\(monitor.swapUsed.formattedMemory) / \(monitor.swapTotal.formattedMemory)"
                                    : monitor.swapUsed.formattedMemory,
                                detail: "RAM yetmediğinde SSD üzerinde açılan sanal bellek",
                                color: monitor.swapUsed > 512 * 1024 * 1024 ? .pink : .white
                            )
                            MetricExplainCard(
                                title: "Sayfa Giriş / Çıkış",
                                value: "\(monitor.pageIns) / \(monitor.pageOuts)",
                                detail: "Sayfa boyutu: \(monitor.pageSizeBytes / 1024) KB · Disk sayfalama sayacı",
                                color: .white.opacity(0.88)
                            )
                        }
                    }
                }

                // Sınırsız Bellek Tüketen Uygulamalar & Süreçler Tablosu
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tüm Bellek Kullanan Uygulamalar ve Süreçler")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(
                                    mode == .grouped
                                        ? "\(filteredGroups.count) uygulama/servis grubu listeleniyor (\(inspector.totalProcessCount) aktif süreç) — Alt süreçleri görmek için satıra tıklayın."
                                        : "\(filteredFlat.count) tekil süreç (PID) listeleniyor — Etkinlik Monitörü fiziksel bellek ayak izi ile uyumlu."
                                )
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.subtleText)
                            }
                            Spacer()

                            Button {
                                Task { await inspector.refreshAllProcesses(manual: true) }
                            } label: {
                                HStack(spacing: 5) {
                                    if inspector.refreshingProcesses {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Yenile")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                        }

                        // Filtre ve Arama Araç Çubuğu
                        HStack(spacing: 10) {
                            HStack(spacing: 7) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(Theme.faintText)
                                TextField("Uygulama, alt süreç veya PID ara…", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.white)
                                if !searchText.isEmpty {
                                    Button { searchText = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faintText)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                            .frame(maxWidth: 280)

                            Picker("", selection: $mode) {
                                ForEach(Mode.allCases, id: \.self) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 260)

                            Toggle("Sistem Servisleri", isOn: $includeSystem)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.subtleText)

                            Spacer()

                            Menu {
                                ForEach(SortBy.allCases, id: \.self) { s in
                                    Button {
                                        sortBy = s
                                    } label: {
                                        HStack {
                                            Text(s.rawValue)
                                            if sortBy == s { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text(sortBy.rawValue)
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        Divider().overlay(Color.white.opacity(0.09))

                        // Sütun Başlıkları
                        HStack(spacing: 10) {
                            Text("UYGULAMA / SÜREÇ")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("CPU")
                                .frame(width: 64, alignment: .trailing)
                            Text("RAM PAYI")
                                .frame(width: 120, alignment: .trailing)
                            Text("BELLEK")
                                .frame(width: 96, alignment: .trailing)
                            Text("İŞLEM")
                                .frame(width: 82, alignment: .trailing)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.faintText)
                        .padding(.horizontal, 8)

                        LazyVStack(spacing: 6) {
                            if mode == .grouped {
                                ForEach(filteredGroups) { group in
                                    groupedMemoryRow(group)
                                }
                            } else {
                                ForEach(filteredFlat) { proc in
                                    flatProcessRow(proc, emphasizeCPU: false)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .task {
            await inspector.refreshAllProcesses(manual: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.0))
                guard !Task.isCancelled else { break }
                await inspector.refreshAllProcesses(manual: false)
            }
        }
    }

    private func groupedMemoryRow(_ g: DetailedProcessGroup) -> some View {
        let isExpanded = expandedGroups.contains(g.id)
        let share = monitor.memoryTotal > 0 ? Double(g.memoryBytes) / monitor.memoryTotal : 0
        let barColor: Color = g.memoryBytes > 1_500_000_000 ? .pink : (g.memoryBytes > 600_000_000 ? .orange : .cyan)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let icon = inspector.icon(forBundlePath: g.bundlePath, fallbackExecPath: g.primaryExecutablePath) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 28, height: 28)
                        Image(systemName: g.isSystemDaemon ? "gearshape.2.fill" : "terminal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.subtleText)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(g.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if g.processCount > 1 {
                            Text("\(g.processCount) süreç")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.cyan.opacity(0.16)))
                        }
                        if g.isSystemDaemon {
                            Text("Sistem")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Theme.faintText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.07)))
                        }
                        if g.processCount > 1 {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Theme.faintText)
                        }
                    }
                    Text(g.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faintText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(String(format: "%%%.1f", g.cpuPercent))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(g.cpuPercent > 20 ? .orange : Theme.subtleText)
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)

                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.09))
                            Capsule()
                                .fill(barColor)
                                .frame(width: max(3, geo.size.width * min(1, share * 2.2)))
                        }
                    }
                    .frame(width: 64, height: 6)

                    Text(String(format: "%%%.1f", share * 100))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.subtleText)
                        .monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }
                .frame(width: 120, alignment: .trailing)

                Text(g.memoryBytes.formattedMemory)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(g.memoryBytes > 1_500_000_000 ? .pink : .white)
                    .monospacedDigit()
                    .frame(width: 96, alignment: .trailing)

                HStack(spacing: 6) {
                    if let bp = g.bundlePath {
                        RevealInFinderButton(url: URL(fileURLWithPath: bp))
                    } else if FileManager.default.fileExists(atPath: g.primaryExecutablePath) {
                        RevealInFinderButton(url: URL(fileURLWithPath: g.primaryExecutablePath))
                    }

                    if g.isCritical {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faintText)
                            .frame(width: 52)
                            .help("macOS için zorunlu sistem bileşeni")
                    } else {
                        Button {
                            inspector.terminateGroup(g)
                        } label: {
                            Text("Kapat")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.red.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 82, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                guard g.processCount > 1 else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    if isExpanded { expandedGroups.remove(g.id) }
                    else { expandedGroups.insert(g.id) }
                }
            }

            if isExpanded && g.processCount > 1 {
                VStack(spacing: 4) {
                    ForEach(g.subprocesses) { sub in
                        HStack(spacing: 8) {
                            Text("↳ PID \(sub.pid)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.faintText)
                                .frame(width: 84, alignment: .leading)
                            Text(sub.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "CPU %%%.1f", sub.cpuPercent))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(Theme.faintText)
                                .monospacedDigit()
                            Text(sub.memoryBytes.formattedMemory)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.cyan)
                                .monospacedDigit()
                                .frame(width: 86, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.bottom, 8)
                .background(Color.black.opacity(0.16))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func flatProcessRow(_ p: SingleProcessEntry, emphasizeCPU: Bool) -> some View {
        let share = monitor.memoryTotal > 0 ? Double(p.memoryBytes) / monitor.memoryTotal : 0
        return HStack(spacing: 10) {
            if let icon = inspector.icon(forBundlePath: p.bundlePath, fallbackExecPath: p.fullPath) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: p.isSystem ? "gearshape.fill" : "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subtleText)
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(p.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("PID \(p.pid) · \(p.ownerLabel)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.faintText)
            }
            Spacer(minLength: 8)

            Text(String(format: "%%%.1f", p.cpuPercent))
                .font(.system(size: 12, weight: emphasizeCPU ? .bold : .medium, design: .rounded))
                .foregroundStyle(emphasizeCPU ? .white : Theme.subtleText)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)

            Text(String(format: "%%%.1f", share * 100))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.faintText)
                .monospacedDigit()
                .frame(width: 120, alignment: .trailing)

            Text(p.memoryBytes.formattedMemory)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: 96, alignment: .trailing)

            HStack(spacing: 6) {
                if FileManager.default.fileExists(atPath: p.fullPath) {
                    RevealInFinderButton(url: URL(fileURLWithPath: p.fullPath))
                }
                if p.isCritical {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faintText)
                        .frame(width: 52)
                } else {
                    Button {
                        inspector.terminateSingle(p)
                    } label: {
                        Text("Kapat")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.red.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 82, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.035)))
    }

    private func freeRAMAction() {
        let beforeUsed = monitor.memoryUsed
        freeingRAM = true
        Task {
            let ok = await Shell.freeRAMPasswordlessOrSetup()
            monitor.updateFull()
            await inspector.refreshAllProcesses(manual: true)
            freeingRAM = false
            if ok {
                let diff = max(0, beforeUsed - monitor.memoryUsed)
                ramFeedback = diff > 32 * 1024 * 1024
                    ? "RAM önbelleği temizlendi · \(diff.formattedMemory) bellek anında serbest bırakıldı."
                    : "RAM önbelleği tazelendi · Tüm temizlenebilir sayfalar boşaltıldı."
            }
        }
    }
}

// MARK: - 2. İŞLEMCİ (CPU) MERKEZİ

struct CPUMonitorDetailView: View {
    enum Mode: String, CaseIterable {
        case grouped = "Uygulama Grupları"
        case flat = "Tüm Süreçler (PID)"
    }
    enum SortBy: String, CaseIterable {
        case cpu = "Anlık CPU (%)"
        case cpuTime = "Toplam CPU Süresi"
        case memory = "Bellek Kullanımı"
        case name = "İsim (A–Z)"
    }

    @ObservedObject var monitor = SystemMonitor.shared
    @ObservedObject var inspector: ResourceInspectorModel
    var onNavigate: (NavModule) -> Void

    @ViewState private var mode: Mode = .grouped
    @ViewState private var sortBy: SortBy = .cpu
    @ViewState private var includeSystem = true
    @ViewState private var searchText = ""
    @ViewState private var expandedGroups: Set<String> = []

    private var coreSummaryText: String {
        if monitor.perfCoreCount > 0 && monitor.effCoreCount > 0 {
            return "\(monitor.coreCount) Çekirdek (\(monitor.perfCoreCount) Performans + \(monitor.effCoreCount) Verimlilik)"
        }
        return "\(monitor.coreCount) Mantıksal Çekirdek"
    }

    private var uptimeText: String {
        let sec = Int(ProcessInfo.processInfo.systemUptime)
        let d = sec / 86400
        let h = (sec % 86400) / 3600
        let m = (sec % 3600) / 60
        return d > 0 ? "\(d) gün \(h) sa \(m) dk" : "\(h) saat \(m) dk"
    }

    private var loadHealthNote: (label: String, color: Color) {
        let ratio = monitor.loadAverage.0 / Double(max(1, monitor.coreCount))
        if ratio >= 1.15 { return ("Yoğun İşlem Kuyruğu", .pink) }
        if ratio >= 0.65 { return ("Orta Düzey Yük", .orange) }
        return ("Akıcı · Rahat Kapasite", Theme.successGreen)
    }

    private var filteredGroups: [DetailedProcessGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = inspector.processGroups.filter { g in
            if !includeSystem && g.isSystemDaemon { return false }
            if q.isEmpty { return true }
            return g.name.lowercased().contains(q) || "\(g.rootPID)".contains(q)
        }
        switch sortBy {
        case .cpu:
            return base.sorted { abs($0.cpuPercent - $1.cpuPercent) > 0.04 ? $0.cpuPercent > $1.cpuPercent : $0.cpuTotalSeconds > $1.cpuTotalSeconds }
        case .cpuTime:
            return base.sorted { $0.cpuTotalSeconds > $1.cpuTotalSeconds }
        case .memory:
            return base.sorted { $0.memoryBytes > $1.memoryBytes }
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var filteredFlat: [SingleProcessEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = inspector.flatProcesses.filter { p in
            if !includeSystem && p.isSystem { return false }
            if q.isEmpty { return true }
            return p.name.lowercased().contains(q) || "\(p.pid)".contains(q)
        }
        switch sortBy {
        case .cpu:
            return base.sorted { abs($0.cpuPercent - $1.cpuPercent) > 0.04 ? $0.cpuPercent > $1.cpuPercent : $0.cpuTotalSeconds > $1.cpuTotalSeconds }
        case .cpuTime:
            return base.sorted { $0.cpuTotalSeconds > $1.cpuTotalSeconds }
        case .memory:
            return base.sorted { $0.memoryBytes > $1.memoryBytes }
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MonitorTopBar(current: .cpuMonitor, onNavigate: onNavigate)

                // Donanım Özeti + Canlı CPU Zaman Grafiği
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 10) {
                                    Text(String(format: "%%%d Toplam Yük", monitor.cpuPercentInt))
                                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                        .monospacedDigit()

                                    Text("\(monitor.cpuBrand) · \(coreSummaryText)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.purple)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.purple.opacity(0.18)))
                                }
                                Text("Açık kalma süresi: \(uptimeText) · Aktif süreç sayısı: \(inspector.totalProcessCount) · Durum: \(loadHealthNote.label)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.subtleText)
                            }
                            Spacer()
                        }

                        SparklineGraph(values: monitor.cpuHistory, color: Color(red: 0.72, green: 0.42, blue: 1.0))
                            .frame(height: 82)
                            .padding(.vertical, 2)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            MetricExplainCard(
                                title: "Kullanıcı (% User)",
                                value: String(format: "%%%.1f", monitor.cpuUser * 100),
                                detail: "Uygulamalarınızın tükettiği işlemci payı",
                                color: .cyan
                            )
                            MetricExplainCard(
                                title: "Sistem (% Kernel)",
                                value: String(format: "%%%.1f", monitor.cpuSystem * 100),
                                detail: "macOS çekirdeği ve donanım sürücüleri",
                                color: .pink
                            )
                            MetricExplainCard(
                                title: "Boşta (% Idle)",
                                value: String(format: "%%%.1f", monitor.cpuIdle * 100),
                                detail: "Anlık hazır bekleyen işlemci gücü",
                                color: Theme.successGreen
                            )
                            MetricExplainCard(
                                title: "Yük Ortalaması (Load)",
                                value: String(format: "%.2f · %.2f · %.2f", monitor.loadAverage.0, monitor.loadAverage.1, monitor.loadAverage.2),
                                detail: "Son 1, 5 ve 15 dakikalık iş kuyruğu yoğunluğu",
                                color: loadHealthNote.color
                            )
                        }
                    }
                }

                // Çekirdek Bazlı Canlı Yük Izgarası
                if !monitor.coreLoads.isEmpty {
                    GlassCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Çekirdek Bazlı Canlı Dağılım (\(monitor.coreLoads.count) Çekirdek)", systemImage: "square.grid.3x2.fill")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("Her bir işlemci çekirdeğinin anlık gerçek kullanım yüzdesi")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.faintText)
                            }

                            let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: min(5, max(2, monitor.coreLoads.count / 2)))
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(Array(monitor.coreLoads.enumerated()), id: \.offset) { idx, load in
                                    let pct = Int((load * 100).rounded())
                                    let barTint: Color = load > 0.80 ? .pink : (load > 0.45 ? .orange : (load > 0.15 ? .cyan : Theme.successGreen))
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text("Çekirdek \(idx + 1)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Theme.subtleText)
                                            Spacer()
                                            Text("%\(pct)")
                                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .monospacedDigit()
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(Color.white.opacity(0.09))
                                                Capsule()
                                                    .fill(barTint)
                                                    .frame(width: max(3, geo.size.width * min(1, load)))
                                            }
                                        }
                                        .frame(height: 6)
                                    }
                                    .padding(9)
                                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.045)))
                                }
                            }
                        }
                    }
                }

                // Tüm İşlemci Tüketen Uygulamalar & Süreçler Tablosu
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tüm İşlemci Kullanan Uygulamalar ve Süreçler")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("Yüzdeler tüm Mac kapasitesine (%0–%100) göre hesaplanır; 1000% gibi yanıltıcı tek çekirdek sıçramaları yapmaz.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.subtleText)
                            }
                            Spacer()
                            Button {
                                Task { await inspector.refreshAllProcesses(manual: true) }
                            } label: {
                                HStack(spacing: 5) {
                                    if inspector.refreshingProcesses { ProgressView().controlSize(.mini) }
                                    else { Image(systemName: "arrow.clockwise") }
                                    Text("Yenile")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 10) {
                            HStack(spacing: 7) {
                                Image(systemName: "magnifyingglass").foregroundStyle(Theme.faintText)
                                TextField("Uygulama veya PID ara…", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.white)
                                if !searchText.isEmpty {
                                    Button { searchText = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faintText)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                            .frame(maxWidth: 260)

                            Picker("", selection: $mode) {
                                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 260)

                            Toggle("Sistem Servisleri", isOn: $includeSystem)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.subtleText)

                            Spacer()

                            Menu {
                                ForEach(SortBy.allCases, id: \.self) { s in
                                    Button { sortBy = s } label: {
                                        HStack {
                                            Text(s.rawValue)
                                            if sortBy == s { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text(sortBy.rawValue)
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        Divider().overlay(Color.white.opacity(0.09))

                        HStack(spacing: 10) {
                            Text("UYGULAMA / SÜREÇ")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("CPU SÜRESİ")
                                .frame(width: 86, alignment: .trailing)
                            Text("BELLEK")
                                .frame(width: 88, alignment: .trailing)
                            Text("ANLIK CPU YÜKÜ")
                                .frame(width: 140, alignment: .trailing)
                            Text("İŞLEM")
                                .frame(width: 82, alignment: .trailing)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.faintText)
                        .padding(.horizontal, 8)

                        LazyVStack(spacing: 6) {
                            if mode == .grouped {
                                ForEach(filteredGroups) { g in
                                    groupedCPURow(g)
                                }
                            } else {
                                ForEach(filteredFlat) { p in
                                    flatCPURow(p)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .task {
            await inspector.refreshAllProcesses(manual: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.0))
                guard !Task.isCancelled else { break }
                await inspector.refreshAllProcesses(manual: false)
            }
        }
    }

    private func groupedCPURow(_ g: DetailedProcessGroup) -> some View {
        let isExpanded = expandedGroups.contains(g.id)
        let tint: Color = g.cpuPercent > 35 ? .pink : (g.cpuPercent > 12 ? .orange : .purple)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let icon = inspector.icon(forBundlePath: g.bundlePath, fallbackExecPath: g.primaryExecutablePath) {
                    Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)).frame(width: 28, height: 28)
                        Image(systemName: g.isSystemDaemon ? "gearshape.2.fill" : "terminal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.subtleText)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(g.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if g.processCount > 1 {
                            Text("\(g.processCount) süreç")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.purple.opacity(0.18)))
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Theme.faintText)
                        }
                    }
                    Text(g.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faintText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(formatDurationSeconds(g.cpuTotalSeconds))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.subtleText)
                    .frame(width: 86, alignment: .trailing)

                Text(g.memoryBytes.formattedMemory)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.subtleText)
                    .monospacedDigit()
                    .frame(width: 88, alignment: .trailing)

                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.09))
                            Capsule()
                                .fill(tint)
                                .frame(width: max(3, geo.size.width * min(1, g.cpuPercent / 100.0)))
                        }
                    }
                    .frame(width: 72, height: 6)

                    Text(String(format: "%%%.1f", g.cpuPercent))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(g.cpuPercent > 35 ? .pink : .white)
                        .monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
                .frame(width: 140, alignment: .trailing)

                HStack(spacing: 6) {
                    if let bp = g.bundlePath {
                        RevealInFinderButton(url: URL(fileURLWithPath: bp))
                    }
                    if g.isCritical {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faintText)
                            .frame(width: 52)
                    } else {
                        Button {
                            inspector.terminateGroup(g)
                        } label: {
                            Text("Kapat")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.red.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 82, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                guard g.processCount > 1 else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    if isExpanded { expandedGroups.remove(g.id) }
                    else { expandedGroups.insert(g.id) }
                }
            }

            if isExpanded && g.processCount > 1 {
                VStack(spacing: 4) {
                    ForEach(g.subprocesses) { sub in
                        HStack(spacing: 8) {
                            Text("↳ PID \(sub.pid)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.faintText)
                                .frame(width: 84, alignment: .leading)
                            Text(sub.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                            Text(sub.memoryBytes.formattedMemory)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(Theme.faintText)
                            Text(String(format: "%%%.1f", sub.cpuPercent))
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.purple)
                                .monospacedDigit()
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.bottom, 8)
                .background(Color.black.opacity(0.16))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func flatCPURow(_ p: SingleProcessEntry) -> some View {
        HStack(spacing: 10) {
            if let icon = inspector.icon(forBundlePath: p.bundlePath, fallbackExecPath: p.fullPath) {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: p.isSystem ? "gearshape.fill" : "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subtleText)
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("PID \(p.pid) · \(p.ownerLabel)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.faintText)
            }
            Spacer(minLength: 8)
            Text(formatDurationSeconds(p.cpuTotalSeconds))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.subtleText)
                .frame(width: 86, alignment: .trailing)
            Text(p.memoryBytes.formattedMemory)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.subtleText)
                .monospacedDigit()
                .frame(width: 88, alignment: .trailing)
            Text(String(format: "%%%.1f", p.cpuPercent))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(p.cpuPercent > 25 ? .pink : .white)
                .monospacedDigit()
                .frame(width: 140, alignment: .trailing)
            HStack(spacing: 6) {
                if p.isCritical {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faintText)
                        .frame(width: 52)
                } else {
                    Button { inspector.terminateSingle(p) } label: {
                        Text("Kapat")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.red.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 82, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.035)))
    }
}

// MARK: - 3. DİSK VE DEPOLAMA MERKEZİ

struct DiskMonitorDetailView: View {
    enum Tab: String, CaseIterable {
        case categories = "Klasör & Kategori Haritası"
        case appData = "En Büyük Uygulama Verileri"
        case largeFiles = "Unutulmuş Büyük Dosyalar"
    }

    @ObservedObject var monitor = SystemMonitor.shared
    @ObservedObject var inspector: ResourceInspectorModel
    var onNavigate: (NavModule) -> Void

    @ViewState private var selectedTab: Tab = .categories
    @ViewState private var emptyingTrash = false

    private let palette: [Color] = [.cyan, .purple, .pink, .orange, Theme.successGreen, .blue]

    private var trashText: String {
        switch inspector.trashState {
        case .loading: return "Hesaplanıyor…"
        case .empty: return "Boş (0 B)"
        case .items(let count, let bytes):
            return bytes > 0 ? "\(bytes.formattedBytes) (\(count) öğe)" : "\(count) öğe"
        case .permissionNeeded:
            return "Finder izni gerekli"
        }
    }

    var body: some View {
        let freeImportant = max(0, monitor.diskTotal - monitor.diskUsed)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MonitorTopBar(current: .diskMonitor, onNavigate: onNavigate)

                // Panoramik APFS Depolama Panosu
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(freeImportant.formattedBytes) Kullanılabilir")
                                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("\(monitor.volumeName) · \(monitor.fileSystemFormat)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(.cyan)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.cyan.opacity(0.16)))
                                }
                                Text("APFS diskinizde macOS \(monitor.diskPurgeable.formattedBytes) alanı 'Temizlenebilir Önbellek' olarak tutuyor; büyük bir dosya kaydettiğinizde otomatik boşaltılır.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.subtleText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Button {
                                    Task { await inspector.scanDiskBreakdown(force: true) }
                                } label: {
                                    HStack(spacing: 5) {
                                        if inspector.scanningDisk { ProgressView().controlSize(.mini) }
                                        else { Image(systemName: "arrow.clockwise") }
                                        Text(inspector.scanningDisk ? "Analiz Ediliyor…" : "Yeniden Analiz Et")
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10)))
                                }
                                .buttonStyle(.plain)
                                .disabled(inspector.scanningDisk)

                                Button {
                                    onNavigate(.systemJunk)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash.circle.fill")
                                        Text("Sistem Çöpü Aç")
                                    }
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(LinearGradient(colors: NavModule.systemJunk.accentColors, startPoint: .leading, endPoint: .trailing))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // 3 Katmanlı APFS Çubuğu: Net Dolu + Purgeable + Doğrudan Boş
                        GeometryReader { geo in
                            let tot = max(1, monitor.diskTotal)
                            let wUsed = max(0, geo.size.width * (monitor.diskUsed / tot))
                            let wPurg = max(0, geo.size.width * (monitor.diskPurgeable / tot))
                            HStack(spacing: 2) {
                                Rectangle()
                                    .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: wUsed)
                                Rectangle()
                                    .fill(Color.orange.opacity(0.75))
                                    .frame(width: wPurg)
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 14)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            MetricExplainCard(
                                title: "Toplam SSD Kapasitesi",
                                value: monitor.diskTotal.formattedBytes,
                                detail: "Birim: \(monitor.volumeName) (\(monitor.fileSystemFormat))",
                                color: .white
                            )
                            MetricExplainCard(
                                title: "Net Kullanılan Alan",
                                value: monitor.diskUsed.formattedBytes,
                                detail: String(format: "Toplam diskin %%%.1f kadarı dolu", monitor.diskRatio * 100),
                                color: .cyan
                            )
                            MetricExplainCard(
                                title: "Temizlenebilir Sistem Alanı",
                                value: monitor.diskPurgeable.formattedBytes,
                                detail: "macOS'un gerektiğinde kendiliğinden sildiği geçici alan",
                                color: .orange
                            )
                            MetricExplainCard(
                                title: "Anında Saf Boş Alan",
                                value: monitor.diskFreeImmediate.formattedBytes,
                                detail: "Hiçbir önbellek silinmeden doğrudan hazır alan",
                                color: Theme.successGreen
                            )
                            MetricExplainCard(
                                title: "Çöp Kutusu",
                                value: trashText,
                                detail: "Silinmeyi bekleyen dosyalar",
                                color: .pink
                            )
                            MetricExplainCard(
                                title: "Yerel APFS Snapshot",
                                value: "\(inspector.localSnapshotCount) adet",
                                detail: "Time Machine yerel geri dönüş noktaları",
                                color: .purple
                            )
                        }
                    }
                }

                // Detaylı Depolama Dağılımı Sekmeleri
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Picker("", selection: $selectedTab) {
                                ForEach(Tab.allCases, id: \.self) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 580)

                            Spacer()

                            if case .items = inspector.trashState {
                                Button {
                                    emptyingTrash = true
                                    Task {
                                        _ = await TrashService.empty()
                                        emptyingTrash = false
                                        inspector.refreshTrashStatus()
                                        monitor.updateFull()
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        if emptyingTrash { ProgressView().controlSize(.mini) }
                                        else { Image(systemName: "trash.slash.fill") }
                                        Text("Çöpü Boşalt")
                                    }
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.pink.opacity(0.55)))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if inspector.scanningDisk && inspector.diskCategories.isEmpty {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Klasör boyutları ve büyük dosyalar taranıyor, lütfen birkaç saniye bekleyin…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.subtleText)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 36)
                        } else {
                            switch selectedTab {
                            case .categories:
                                categoriesListView
                            case .appData:
                                largeEntriesListView(
                                    items: inspector.topAppDataFolders,
                                    emptyText: "25 MB üzerinde uygulama veri klasörü bulunamadı.",
                                    headerNote: "~/Library/Application Support ve ~/Library/Caches altında en çok yer tutan uygulama klasörleri:"
                                )
                            case .largeFiles:
                                largeEntriesListView(
                                    items: inspector.largeUserFiles,
                                    emptyText: "İndirilenler, Masaüstü veya Belgeler'de 20 MB üzerinde büyük dosya bulunamadı.",
                                    headerNote: "İndirilenler, Masaüstü, Belgeler ve Filmler klasörlerinizdeki en büyük dosyalar (hiçbir dosyaya otomatik dokunulmaz):"
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .task {
            await inspector.scanDiskBreakdown(force: false)
        }
    }

    private var categoriesListView: some View {
        let maxCat = max(1, inspector.diskCategories.first?.bytes ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(inspector.diskCategories) { cat in
                let tint = palette[cat.colorIndex % palette.count]
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: cat.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(cat.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("\(cat.itemCount) öğe")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Theme.faintText)
                        }
                        Text(cat.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.subtleText)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule()
                                    .fill(tint)
                                    .frame(width: max(5, geo.size.width * (Double(cat.bytes) / Double(maxCat))))
                            }
                        }
                        .frame(height: 5)
                    }

                    Spacer(minLength: 12)

                    if let mod = cat.suggestedModule {
                        Button {
                            onNavigate(mod == "uninstaller" ? .uninstaller : .systemJunk)
                        } label: {
                            Text(mod == "uninstaller" ? "Kaldırıcı'da Aç" : "Temizle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(tint.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(cat.bytes.formattedBytes)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 96, alignment: .trailing)

                    RevealInFinderButton(url: cat.url)
                }
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.04)))
            }
        }
    }

    private func largeEntriesListView(items: [LargeDiskEntry], emptyText: String, headerNote: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerNote)
                .font(.system(size: 12))
                .foregroundStyle(Theme.subtleText)
                .padding(.bottom, 2)

            if items.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.faintText)
                    .padding(.vertical, 20)
            } else {
                let topBytes = max(1, items.first?.bytes ?? 1)
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable()
                            .frame(width: 26, height: 26)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(item.locationLabel)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.cyan)
                                Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: FileUtils.home.path, with: "~"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.faintText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Spacer(minLength: 8)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule()
                                    .fill(Color.cyan)
                                    .frame(width: max(4, geo.size.width * (Double(item.bytes) / Double(topBytes))))
                            }
                        }
                        .frame(width: 90, height: 6)

                        Text(item.bytes.formattedBytes)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(item.bytes > 1_000_000_000 ? .orange : .white)
                            .monospacedDigit()
                            .frame(width: 92, alignment: .trailing)

                        RevealInFinderButton(url: item.url)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.038)))
                }
            }
        }
    }
}

// MARK: - 4. AĞ VE CANLI TRAFİK MERKEZİ

struct NetworkMonitorDetailView: View {
    enum SortBy: String, CaseIterable {
        case downSpeed = "Anlık İndirme (↓)"
        case upSpeed = "Anlık Yükleme (↑)"
        case totalData = "Toplam Veri Alışverişi"
        case name = "İsim (A–Z)"
    }

    @ObservedObject var monitor = SystemMonitor.shared
    @ObservedObject var inspector: ResourceInspectorModel
    var onNavigate: (NavModule) -> Void

    @ViewState private var sortBy: SortBy = .downSpeed
    @ViewState private var includeSystem = true
    @ViewState private var searchText = ""
    @ViewState private var flushingDNS = false
    @ViewState private var dnsNotice: String?

    private var filteredApps: [AppNetworkUsage] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = inspector.networkApps.filter { app in
            if !includeSystem && app.isSystemService { return false }
            if q.isEmpty { return true }
            return app.name.lowercased().contains(q)
        }
        switch sortBy {
        case .downSpeed:
            return base.sorted {
                if abs($0.downloadBps - $1.downloadBps) > 32 { return $0.downloadBps > $1.downloadBps }
                if abs($0.uploadBps - $1.uploadBps) > 32 { return $0.uploadBps > $1.uploadBps }
                return $0.totalCombinedBytes > $1.totalCombinedBytes
            }
        case .upSpeed:
            return base.sorted {
                if abs($0.uploadBps - $1.uploadBps) > 32 { return $0.uploadBps > $1.uploadBps }
                return $0.totalOutBytes > $1.totalOutBytes
            }
        case .totalData:
            return base.sorted { $0.totalCombinedBytes > $1.totalCombinedBytes }
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        let conn = inspector.connectionDetails
        let peakScale = max(monitor.peakNetIn, monitor.peakNetOut, 1024)
        let normDown = monitor.netInHistory.map { min(1.0, $0 / peakScale) }
        let normUp = monitor.netOutHistory.map { min(1.0, $0 / peakScale) }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MonitorTopBar(current: .networkMonitor, onNavigate: onNavigate)

                // Bağlantı Kimliği & Canlı İndirme/Yükleme Dalga Grafiği
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 14) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(Theme.successGreen)
                                        Text(formatNetworkRate(monitor.netIn))
                                            .font(.system(size: 23, weight: .heavy, design: .rounded))
                                            .foregroundStyle(.white)
                                            .monospacedDigit()
                                    }
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .foregroundStyle(.orange)
                                        Text(formatNetworkRate(monitor.netOut))
                                            .font(.system(size: 23, weight: .heavy, design: .rounded))
                                            .foregroundStyle(.white)
                                            .monospacedDigit()
                                    }

                                    if monitor.vpnTunnelActive || !conn.activeVPNInterfaces.isEmpty {
                                        Text("VPN Tüneli Aktif")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.cyan)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 3.5)
                                            .background(Capsule().fill(Color.cyan.opacity(0.18)))
                                    }
                                }

                                Text("\(conn.ssidOrKind) · Yerel IP: \(monitor.localIP) · Tepe hız ölçeği: \(formatNetworkRate(peakScale))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.subtleText)
                            }

                            Spacer()

                            Button {
                                flushDNSAction()
                            } label: {
                                HStack(spacing: 6) {
                                    if flushingDNS { ProgressView().controlSize(.mini) }
                                    else { Image(systemName: "arrow.triangle.2.circlepath") }
                                    Text("DNS Önbelleğini Yenile")
                                }
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                            .disabled(flushingDNS)
                        }

                        if let dnsNotice {
                            Text(dnsNotice)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.successGreen)
                        }

                        // Çift Katmanlı İndirme (Yeşil) + Yükleme (Turuncu) Dalga Grafiği
                        ZStack(alignment: .topTrailing) {
                            SparklineGraph(values: normDown, color: Theme.successGreen)
                            SparklineGraph(values: normUp, color: .orange)
                            HStack(spacing: 12) {
                                Label("İndirme", systemImage: "circle.fill")
                                    .foregroundStyle(Theme.successGreen)
                                Label("Yükleme", systemImage: "circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.32)))
                        }
                        .frame(height: 84)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            MetricExplainCard(
                                title: "Modem / Ağ Geçidi",
                                value: conn.gatewayIP,
                                detail: conn.gatewayPingMs != nil
                                    ? String(format: "Yerel modem gecikmesi: %.1f ms", conn.gatewayPingMs!)
                                    : "Varsayılan yönlendirici adresi",
                                color: .cyan
                            )
                            MetricExplainCard(
                                title: "Aktif DNS Sunucuları",
                                value: conn.dnsServers.isEmpty ? "Otomatik" : conn.dnsServers.prefix(2).joined(separator: ", "),
                                detail: conn.dnsServers.count > 2 ? "Toplam \(conn.dnsServers.count) DNS tanımlı" : "Alan adı çözümleme sunucuları",
                                color: .purple
                            )
                            MetricExplainCard(
                                title: "Oturum Toplam İndirilen",
                                value: Int64(monitor.totalNetIn).formattedBytes,
                                detail: "Açılıştan bu yana alınan toplam veri",
                                color: Theme.successGreen
                            )
                            MetricExplainCard(
                                title: "Oturum Toplam Yüklenen",
                                value: Int64(monitor.totalNetOut).formattedBytes,
                                detail: "Açılıştan bu yana gönderilen toplam veri",
                                color: .orange
                            )
                            MetricExplainCard(
                                title: "Donanım (MAC) / Arayüz",
                                value: monitor.activeInterface,
                                detail: "MAC: \(conn.hardwareMAC)",
                                color: .white
                            )
                            MetricExplainCard(
                                title: "VPN / Tünel Arayüzü",
                                value: conn.activeVPNInterfaces.isEmpty ? "Yok (Doğrudan)" : conn.activeVPNInterfaces.joined(separator: ", "),
                                detail: conn.activeVPNInterfaces.isEmpty ? "Şifreli tünel arayüzü algılanmadı" : "Aktif sanal ağ tüneli",
                                color: conn.activeVPNInterfaces.isEmpty ? Theme.subtleText : .cyan
                            )
                        }
                    }
                }

                // Hız ve Bufferbloat Test Kartı
                GlassCard(padding: 16) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Bağlantı Hızı ve Bufferbloat (RPM) Kalite Testi", systemImage: "speedometer")
                                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            if monitor.speedTesting {
                                Text(monitor.speedTestStatus)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.cyan)
                            } else if let res = monitor.lastSpeedTest {
                                Text(
                                    String(
                                        format: "↓ %.1f Mbps  ·  ↑ %.1f Mbps  ·  Boşta Ping: %@  ·  Yük Altı: %@ (%@)",
                                        res.downloadMbps,
                                        res.uploadMbps,
                                        res.idlePingMs != nil ? String(format: "%.0f ms", res.idlePingMs!) : "—",
                                        res.rpm != nil ? "\(res.rpm!) RPM" : "—",
                                        res.bufferbloatLabel
                                    )
                                )
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.successGreen)
                            } else if let err = monitor.speedTestError {
                                Text(err).font(.system(size: 12)).foregroundStyle(.orange)
                            } else {
                                Text("Apple CDN üzerinden gerçek indirme/yükleme kapasitenizi ve yük altındaki oyun/görüntülü görüşme gecikmesini (RPM) ölçer.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.subtleText)
                            }
                        }

                        Spacer()

                        Button {
                            monitor.runSpeedTest()
                        } label: {
                            HStack(spacing: 6) {
                                if monitor.speedTesting { ProgressView().controlSize(.small) }
                                else { Image(systemName: "play.fill") }
                                Text(monitor.speedTesting ? "Ölçülüyor…" : (monitor.lastSpeedTest == nil ? "Hız Testi Başlat" : "Yeniden Ölç"))
                            }
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(LinearGradient(colors: NavModule.networkMonitor.accentColors, startPoint: .leading, endPoint: .trailing))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(monitor.speedTesting)
                    }
                }

                // Uygulama Bazlı Canlı Veri Alışverişi Tablosu
                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Uygulama Bazlı Canlı Veri Alışverişi")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("Hangi uygulamanın şu an interneti kullandığını ve toplam ne kadar veri harcadığını canlı izleyin (bu ekran kapandığında sıfır CPU tüketir).")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.subtleText)
                            }
                            Spacer()
                            Button {
                                Task {
                                    await inspector.refreshNetworkApps(manual: true)
                                    await inspector.refreshConnectionMetadata()
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    if inspector.refreshingNetwork { ProgressView().controlSize(.mini) }
                                    else { Image(systemName: "arrow.clockwise") }
                                    Text("Yenile")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 10) {
                            HStack(spacing: 7) {
                                Image(systemName: "magnifyingglass").foregroundStyle(Theme.faintText)
                                TextField("Uygulama veya ağ servisi ara…", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.white)
                                if !searchText.isEmpty {
                                    Button { searchText = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faintText)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                            .frame(maxWidth: 280)

                            Toggle("Sistem Ağ Servisleri", isOn: $includeSystem)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.subtleText)

                            Spacer()

                            Menu {
                                ForEach(SortBy.allCases, id: \.self) { s in
                                    Button { sortBy = s } label: {
                                        HStack {
                                            Text(s.rawValue)
                                            if sortBy == s { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text(sortBy.rawValue)
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        Divider().overlay(Color.white.opacity(0.09))

                        HStack(spacing: 10) {
                            Text("UYGULAMA / AĞ SERVİSİ")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("ANLIK İNDİRME (↓)")
                                .frame(width: 126, alignment: .trailing)
                            Text("ANLIK YÜKLEME (↑)")
                                .frame(width: 126, alignment: .trailing)
                            Text("TOPLAM ALINAN")
                                .frame(width: 104, alignment: .trailing)
                            Text("TOPLAM GÖNDERİLEN")
                                .frame(width: 118, alignment: .trailing)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.faintText)
                        .padding(.horizontal, 8)

                        LazyVStack(spacing: 6) {
                            ForEach(filteredApps) { app in
                                networkAppRow(app)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .task {
            await inspector.refreshConnectionMetadata()
            await inspector.refreshNetworkApps(manual: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.2))
                guard !Task.isCancelled else { break }
                await inspector.refreshNetworkApps(manual: false)
            }
        }
    }

    private func networkAppRow(_ app: AppNetworkUsage) -> some View {
        let activeNow = app.downloadBps >= 64 || app.uploadBps >= 64
        return HStack(spacing: 10) {
            if let icon = inspector.icon(forBundlePath: app.bundlePath) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 26, height: 26)
                    Image(systemName: app.isSystemService ? "network" : "globe")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.cyan)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if activeNow {
                        Circle()
                            .fill(Theme.successGreen)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(app.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faintText)
            }

            Spacer(minLength: 8)

            Text(app.downloadBps >= 1 ? "↓ " + formatNetworkRate(app.downloadBps) : "—")
                .font(.system(size: 12.5, weight: app.downloadBps >= 1024 ? .bold : .medium, design: .rounded))
                .foregroundStyle(app.downloadBps >= 1 ? Theme.successGreen : Theme.faintText)
                .monospacedDigit()
                .frame(width: 126, alignment: .trailing)

            Text(app.uploadBps >= 1 ? "↑ " + formatNetworkRate(app.uploadBps) : "—")
                .font(.system(size: 12.5, weight: app.uploadBps >= 1024 ? .bold : .medium, design: .rounded))
                .foregroundStyle(app.uploadBps >= 1 ? .orange : Theme.faintText)
                .monospacedDigit()
                .frame(width: 126, alignment: .trailing)

            Text(Int64(app.totalInBytes).formattedBytes)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .monospacedDigit()
                .frame(width: 104, alignment: .trailing)

            Text(Int64(app.totalOutBytes).formattedBytes)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.subtleText)
                .monospacedDigit()
                .frame(width: 118, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(activeNow ? Color.white.opacity(0.065) : Color.white.opacity(0.035))
        )
    }

    private func flushDNSAction() {
        flushingDNS = true
        Task {
            let ok = await Shell.flushDNSPasswordlessOrSetup()
            flushingDNS = false
            dnsNotice = ok ? "✓ DNS önbelleği sıfırlandı ve mDNSResponder yenilendi." : nil
            await inspector.refreshConnectionMetadata()
        }
    }
}
