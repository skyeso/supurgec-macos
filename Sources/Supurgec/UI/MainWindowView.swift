import SwiftUI

struct MainWindowView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewState private var selectedModule: NavModule = .smartScan

    @StateObject private var junkScanner: JunkScanner
    @StateObject private var uninstaller = UninstallerModel()
    @StateObject private var optimization: OptimizationModel
    @StateObject private var maintenance: MaintenanceModel
    @StateObject private var smartScan: SmartScanModel
    @StateObject private var resourceInspector = ResourceInspectorModel()
    @ObservedObject private var monitor = SystemMonitor.shared

    init() {
        let junk = JunkScanner()
        let opt = OptimizationModel()
        let maint = MaintenanceModel()
        _junkScanner = StateObject(wrappedValue: junk)
        _optimization = StateObject(wrappedValue: opt)
        _maintenance = StateObject(wrappedValue: maint)
        _smartScan = StateObject(wrappedValue: SmartScanModel(junkScanner: junk, optimization: opt, maintenance: maint))
    }

    private let sections = ["Genel", "Canlı İzleyici", "Temizlik", "Hız", "Uygulamalar", "Tercihler"]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: selectedModule.backdropColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: selectedModule)

            if !reduceTransparency {
                RadialGradient(
                    colors: [selectedModule.primaryAccent.opacity(0.15), .clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 500
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: selectedModule)
            }

            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 1)
                detailContent
                    .padding(.top, 26)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 1020, minHeight: 680)
        .preferredColorScheme(.dark)
        .onAppear {
            monitor.beginInteractiveSession()
        }
        .onDisappear {
            monitor.endInteractiveSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToModule)) { note in
            if let target = note.object as? NavModule {
                withAnimation(.easeOut(duration: 0.2)) { selectedModule = target }
            }
        }
    }

    // MARK: - Sol Kenar Çubuğu

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.36, blue: 0.62),
                                    Color(red: 0.55, green: 0.27, blue: 0.93),
                                    Color(red: 0.16, green: 0.45, blue: 0.97)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Süpürgeç")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Mac Bakım Stüdyosu")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.faintText)
                }
                Spacer()
            }
            .padding(.top, 42)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.self) { sec in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sec.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(Theme.faintText)
                                .padding(.horizontal, 12)

                            ForEach(NavModule.allCases.filter { $0.section == sec }) { mod in
                                sidebarRow(mod)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            // Sol Alt: Sabit Genişlikli Süpürgeç Öz Kaynak İzleyici + Disk Özeti (Kayma Yapmaz!)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(monitor.isBusyTaskRunning ? Color.cyan : Theme.successGreen)
                            .frame(width: 6, height: 6)
                        Text(monitor.currentActivity)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(monitor.isBusyTaskRunning ? Color.cyan : .white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }

                    // 3 Sabit Sütun: Tek haneden çift haneye çıkınca satır ASLA kaymaz veya alt satıra düşmez
                    HStack(spacing: 0) {
                        Text(String(format: "CPU %%%.1f", monitor.selfCPUPercent))
                            .frame(width: 72, alignment: .leading)
                        Text(String(format: "RAM %.0f MB", Double(monitor.selfMemoryBytes) / (1024 * 1024)))
                            .frame(width: 82, alignment: .center)
                        Text(monitor.selfGPUActive ? "GPU Aktif" : "GPU %0")
                            .frame(width: 58, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.subtleText)
                    .monospacedDigit()
                    .lineLimit(1)
                }

                Divider().overlay(Color.white.opacity(0.09))

                HStack(spacing: 5) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.cyan)
                    Text("SSD:")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\((monitor.diskTotal - monitor.diskUsed).formattedBytes) boş")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.subtleText)
                        .lineLimit(1)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.25, green: 0.78, blue: 1.0), Color(red: 0.98, green: 0.36, blue: 0.62)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * monitor.diskRatio))
                    }
                }
                .frame(height: 5)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) { selectedModule = .settings }
            }
            .help("Süpürgeç'in tüm kaynak detaylarını görmek için tıklayın")
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // En Alt Sürüm ve Katkı İmzası
            VStack(spacing: 2) {
                Text("Alpha Sürüm 0.2")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.subtleText)
                Text("Ensar Gemici katkılarıyla")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.faintText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .frame(width: 258)
        .background(Theme.sidebarSolid)
    }

    private func sidebarRow(_ mod: NavModule) -> some View {
        let active = selectedModule == mod
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedModule = mod
            }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            active
                                ? LinearGradient(colors: mod.accentColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: mod.icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(active ? .white : mod.primaryAccent)
                }

                Text(mod.title)
                    .font(.system(size: 13.5, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? .white : .white.opacity(0.78))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if mod == .systemJunk && junkScanner.phase == .results && junkScanner.selectedSize > 0 {
                    Text(junkScanner.selectedSize.formattedBytes)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(mod.primaryAccent.opacity(0.55)))
                } else if mod == .memoryMonitor {
                    Text(String(format: "%%%.0f", monitor.memoryRatio * 100))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? .white : Theme.subtleText)
                        .monospacedDigit()
                } else if mod == .cpuMonitor {
                    Text("%\(monitor.cpuPercentInt)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? .white : Theme.subtleText)
                        .monospacedDigit()
                } else if mod == .diskMonitor {
                    Text("\((monitor.diskTotal - monitor.diskUsed).formattedBytes)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(active ? .white : Theme.faintText)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(active ? Color.white.opacity(0.13) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(active ? Color.white.opacity(0.16) : .clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sağ İçerik Alanı

    @ViewBuilder
    private var detailContent: some View {
        let nav: (NavModule) -> Void = { target in
            withAnimation(.easeOut(duration: 0.2)) { selectedModule = target }
        }
        switch selectedModule {
        case .smartScan:
            SmartScanView(model: smartScan, onNavigate: nav)
        case .memoryMonitor:
            MemoryMonitorDetailView(inspector: resourceInspector, onNavigate: nav)
        case .cpuMonitor:
            CPUMonitorDetailView(inspector: resourceInspector, onNavigate: nav)
        case .diskMonitor:
            DiskMonitorDetailView(inspector: resourceInspector, onNavigate: nav)
        case .networkMonitor:
            NetworkMonitorDetailView(inspector: resourceInspector, onNavigate: nav)
        case .systemJunk:
            SystemJunkView(scanner: junkScanner)
        case .uninstaller:
            UninstallerView(model: uninstaller)
        case .optimization:
            OptimizationView(model: optimization)
        case .maintenance:
            MaintenanceView(model: maintenance)
        case .settings:
            SettingsView()
        }
    }
}
