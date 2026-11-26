import SwiftUI
import AppKit

struct MenuBarMonitorView: View {
    enum Page {
        case overview
        case memory
        case cpu
        case network
        case disk
    }

    @ObservedObject var monitor = SystemMonitor.shared
    var onOpenMainWindow: (NavModule?) -> Void

    @ViewState private var page: Page = .overview
    @ViewState private var trashState: TrashState = .loading
    @ViewState private var confirmingTrashEmpty = false
    @ViewState private var freeingRAM = false
    @ViewState private var emptyingTrash = false

    private let cardBg = Theme.cardSolid
    private let stroke = Color.white.opacity(0.11)

    var body: some View {
        ZStack(alignment: .top) {
            // Tam boy arka plan: hiçbir alt sayfada üstte/altta gri boşluk bırakmaz!
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.10, blue: 0.22), Color(red: 0.06, green: 0.07, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Group {
                switch page {
                case .overview:
                    overviewContent
                case .memory:
                    memoryDetailView
                case .cpu:
                    cpuDetailView
                case .network:
                    networkDetailView
                case .disk:
                    diskDetailView
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 384, height: 462)
        .preferredColorScheme(.dark)
        .onAppear {
            refreshTrash()
        }
        .task(id: page) {
            guard page == .cpu || page == .memory else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.0))
                guard !Task.isCancelled else { break }
                monitor.refreshTopConsumers(manual: false)
            }
        }
    }

    // MARK: - Ana Özet Ekranı

    private var overviewContent: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                            .frame(width: 24, height: 24)
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("Süpürgeç Monitör")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(uptimeString)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.faintText)

                Button {
                    onOpenMainWindow(.settings)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .help("Üst Barı ve Ayarları Kişiselleştir")
            }

            HStack(spacing: 10) {
                diskTile
                memoryTile
            }

            HStack(spacing: 10) {
                cpuTile
                networkTile
            }

            // Çöp Kutusu Satırı (Yanlışlıkla Basmaya Karşı Onaylı!)
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.pink.opacity(0.18))
                            .frame(width: 30, height: 30)
                        Image(systemName: trashIconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.pink)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Çöp Kutusu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(confirmingTrashEmpty ? "Öğeler kalıcı olarak silinecek!" : trashSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(confirmingTrashEmpty ? .orange : Theme.subtleText)
                            .lineLimit(1)
                    }
                    Spacer()
                    trashActionView
                }

                if confirmingTrashEmpty {
                    HStack(spacing: 8) {
                        Text("Emin misiniz?")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { confirmingTrashEmpty = false }
                        } label: {
                            Text("Vazgeç")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.subtleText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.09)))
                        }
                        .buttonStyle(.plain)

                        Button {
                            confirmingTrashEmpty = false
                            emptyTrash()
                        } label: {
                            Text("Evet, Kalıcı Boşalt")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.red.opacity(0.75)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(cardBg)
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(confirmingTrashEmpty ? Color.red.opacity(0.45) : stroke, lineWidth: 1))
            )

            // Süpürgeç Canlı Öz Tüketim Çubuğu
            HStack(spacing: 6) {
                Circle()
                    .fill(monitor.isBusyTaskRunning ? Color.cyan : Theme.successGreen)
                    .frame(width: 6, height: 6)
                Text(monitor.currentActivity)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "CPU %%%.1f · %@", monitor.selfCPUPercent, monitor.selfMemoryBytes.formattedMemory))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Theme.faintText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)

            // Alt Eylem Çubuğu
            HStack(spacing: 10) {
                Button {
                    onOpenMainWindow(nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "macwindow")
                        Text("Süpürgeç'i Aç")
                    }
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.55, green: 0.27, blue: 0.93), Color(red: 0.98, green: 0.36, blue: 0.62)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.subtleText)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Süpürgeç'ten Çık")
            }
        }
    }

    private var trashIconName: String {
        if case .items = trashState { return "trash.fill" }
        return "trash"
    }

    private var trashSubtitle: String {
        switch trashState {
        case .loading:
            return "Kontrol ediliyor…"
        case .empty:
            return "Boş"
        case .items(let count, let bytes):
            if bytes > 0 {
                return "\(count) öğe · \(bytes.formattedBytes)"
            }
            return "\(count) öğe dolu"
        case .permissionNeeded:
            return "Görmek için Finder izni gerekli"
        }
    }

    @ViewBuilder
    private var trashActionView: some View {
        switch trashState {
        case .items:
            if emptyingTrash {
                ProgressView().controlSize(.mini)
            } else if !confirmingTrashEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { confirmingTrashEmpty = true }
                } label: {
                    Text("Boşalt")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.pink.opacity(0.40)))
                }
                .buttonStyle(.plain)
            }
        case .permissionNeeded:
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("İzin Ver")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.40)))
            }
            .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }

    // MARK: - Tıklanabilir Kutucuklar

    private var diskTile: some View {
        let free = max(0, monitor.diskTotal - monitor.diskUsed)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(Color.cyan)
                Text("Macintosh HD")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Theme.faintText)
            }
            Text(free.formattedBytes)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Kullanılabilir alan")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.subtleText)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(Color.cyan)
                        .frame(width: max(4, geo.size.width * monitor.diskRatio))
                }
            }
            .frame(height: 5)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(cardBg)
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(stroke, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.16)) { page = .disk }
        }
    }

    private var memoryTile: some View {
        let ratio = monitor.memoryRatio
        let tint: Color = monitor.swapUsed > 512 * 1024 * 1024 || ratio > 0.88 ? .pink : (ratio > 0.75 ? .orange : Theme.successGreen)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                    .foregroundStyle(tint)
                Text("Bellek")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    freeRAM()
                } label: {
                    if freeingRAM {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("Boşalt")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.20)))
                    }
                }
                .buttonStyle(.plain)
                .disabled(freeingRAM)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%%%.0f", ratio * 100))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("Detay ›")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.faintText)
            }
            Text("\(monitor.memoryUsed.formattedMemory) / \(monitor.memoryTotal.formattedMemory)")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.subtleText)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geo.size.width * min(1, ratio)))
                }
            }
            .frame(height: 5)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(cardBg)
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(stroke, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            monitor.refreshTopConsumers()
            withAnimation(.easeOut(duration: 0.16)) { page = .memory }
        }
    }

    private var cpuTile: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundStyle(.purple)
                Text("İşlemci")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%%%d", monitor.cpuPercentInt))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Theme.faintText)
            }

            SparklineGraph(values: monitor.cpuHistory, color: Color(red: 0.70, green: 0.42, blue: 1.0))
                .frame(height: 40)

            Text("Uygulama yüklerini gör")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.subtleText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(cardBg)
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(stroke, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            monitor.refreshTopConsumers()
            withAnimation(.easeOut(duration: 0.16)) { page = .cpu }
        }
    }

    private var networkTile: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(.blue)
                Text("Ağ")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Hız Testi ›")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.cyan)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.successGreen)
                    Text(formatSpeed(monitor.netIn))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text(formatSpeed(monitor.netOut))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }

            Text(
                monitor.lastSpeedTest != nil
                    ? String(format: "Son test: ↓%.0f / ↑%.0f Mbps", monitor.lastSpeedTest!.downloadMbps, monitor.lastSpeedTest!.uploadMbps)
                    : "Detay ve hız testi için dokun"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.subtleText)
            .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(cardBg)
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(stroke, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.16)) { page = .network }
        }
    }

    // MARK: - 1. Bellek Detay Ekranı (Üst Başlık Sabit + İçerik Kaydırılabilir!)

    private var memoryDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailHeader(title: "Bellek (RAM)", icon: "memorychip", tint: Theme.successGreen) {
                Button {
                    freeRAM()
                } label: {
                    if freeingRAM {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("RAM Boşalt")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.successGreen.opacity(0.35)))
                    }
                }
                .buttonStyle(.plain)
                .disabled(freeingRAM)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(monitor.memoryUsed.formattedMemory) / \(monitor.memoryTotal.formattedMemory)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(monitor.swapUsed < 64 * 1024 * 1024 ? "Baskı: Düşük (Sağlıklı)" : "Takas: \(monitor.swapUsed.formattedMemory)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(monitor.swapUsed < 64 * 1024 * 1024 ? Theme.successGreen : .orange)
                        }
                        Text("macOS hız için boş belleği dosya önbelleği olarak hazır tutar. Takas \(monitor.swapUsed.formattedMemory) iken bellek darlığı yoktur.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(cardBg).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 1)))

                    HStack(spacing: 8) {
                        metricMiniBox(label: "Uygulama", value: monitor.memApp.formattedMemory, color: .cyan)
                        metricMiniBox(label: "Bağlı (Wired)", value: monitor.memWired.formattedMemory, color: .purple)
                    }
                    HStack(spacing: 8) {
                        metricMiniBox(label: "Sıkıştırılmış", value: monitor.memCompressed.formattedMemory, color: .orange)
                        metricMiniBox(label: "Önbellek", value: monitor.memCached.formattedMemory, color: Theme.successGreen)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("EN ÇOK BELLEK KULLANAN UYGULAMALAR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.faintText)
                            Spacer()
                            if monitor.refreshingConsumers {
                                ProgressView().controlSize(.mini)
                            } else {
                                Button { monitor.refreshTopConsumers(manual: true) } label: {
                                    Label("Yenile", systemImage: "arrow.clockwise")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(Theme.subtleText)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        ForEach(monitor.topMemConsumers) { p in
                            consumerRow(p, rightText: p.memoryBytes.formattedMemory, highlight: false)
                        }
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(cardBg).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 1)))
                }
                .padding(.trailing, 2)
            }
        }
    }

    // MARK: - 2. İşlemci (CPU) Detay Ekranı (Sabit Başlık + Gruplanmış Uygulamalar!)

    private var cpuDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailHeader(title: "İşlemci (CPU)", icon: "cpu.fill", tint: .purple) {
                Text("\(monitor.coreCount) Çekirdek")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.subtleText)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(format: "Toplam Yük: %%%d", monitor.cpuPercentInt))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                            Spacer()
                            Text(String(format: "Ort: %.2f · %.2f · %.2f", monitor.loadAverage.0, monitor.loadAverage.1, monitor.loadAverage.2))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.subtleText)
                        }

                        SparklineGraph(values: monitor.cpuHistory, color: Color(red: 0.70, green: 0.42, blue: 1.0))
                            .frame(height: 50)

                        HStack(spacing: 8) {
                            metricMiniBox(label: "Kullanıcı", value: String(format: "%%%.1f", monitor.cpuUser * 100), color: .cyan)
                            metricMiniBox(label: "Sistem", value: String(format: "%%%.1f", monitor.cpuSystem * 100), color: .pink)
                            metricMiniBox(label: "Boşta", value: String(format: "%%%.1f", monitor.cpuIdle * 100), color: Theme.successGreen)
                        }
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(cardBg).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 1)))

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("EN ÇOK CPU KULLANANLAR (TOPLAM MAC YÜKÜ)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.faintText)
                            Spacer()
                            if monitor.refreshingConsumers {
                                ProgressView().controlSize(.mini)
                            } else {
                                Button { monitor.refreshTopConsumers(manual: true) } label: {
                                    Label("Yenile", systemImage: "arrow.clockwise")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(Theme.subtleText)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if monitor.topCPUConsumers.isEmpty {
                            Text("Şu an işlemciyi yoran bir uygulama yok.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.subtleText)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(monitor.topCPUConsumers) { p in
                                consumerRow(p, rightText: String(format: "%%%.1f", p.cpu), highlight: p.cpu > 35)
                            }
                        }
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(cardBg).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 1)))
                }
                .padding(.trailing, 2)
            }
        }
    }

    private func consumerRow(_ p: TopConsumer, rightText: String, highlight: Bool) -> some View {
        HStack(spacing: 8) {
            if let icon = p.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.subtleText)
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(p.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !p.subtitle.isEmpty {
                    Text(p.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.faintText)
                }
            }
            Spacer()
            Text(rightText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? .pink : .white.opacity(0.9))
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }

    // MARK: - 3. Ağ & Speed Test Detay Ekranı

    private var networkDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailHeader(title: "Ağ ve Hız Testi", icon: "network", tint: .cyan) {
                Text("\(monitor.activeInterface) · \(monitor.localIP)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.subtleText)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            metricMiniBox(
                                label: "Anlık İndirme",
                                value: "↓ " + formatSpeed(monitor.netIn),
                                color: Theme.successGreen
                            )
                            metricMiniBox(
                                label: "Anlık Yükleme",
                                value: "↑ " + formatSpeed(monitor.netOut),
                                color: .orange
                            )
                        }
                        HStack {
                            Text("Oturum Toplamı: ↓ \(Int64(monitor.totalNetIn).formattedBytes)")
                            Spacer()
                            Text("↑ \(Int64(monitor.totalNetOut).formattedBytes)")
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.faintText)
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(cardBg).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 1)))

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Bağlantı Hızı ve Bufferbloat Testi", systemImage: "speedometer")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)

                        if monitor.speedTesting {
                            VStack(spacing: 8) {
                                ProgressView().controlSize(.regular)
                                Text(monitor.speedTestStatus)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.subtleText)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        } else if let res = monitor.lastSpeedTest {
                            HStack(spacing: 8) {
                                metricMiniBox(label: "İndirme", value: String(format: "%.1f Mbps", res.downloadMbps), color: Theme.successGreen)
                                metricMiniBox(label: "Yükleme", value: String(format: "%.1f Mbps", res.uploadMbps), color: .cyan)
                            }
                            HStack(spacing: 8) {
                                metricMiniBox(label: "Boşta Ping", value: res.idlePingMs != nil ? String(format: "%.0f ms", res.idlePingMs!) : "—", color: .purple)
                                metricMiniBox(label: "Yük Altı Yanıt", value: res.rpm != nil ? "\(res.rpm!) RPM" : "—", color: (res.rpm ?? 0) >= 800 ? Theme.successGreen : .orange)
                            }
                            Text("Kalite: \(res.bufferbloatLabel)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle((res.rpm ?? 0) >= 800 ? Theme.successGreen : .orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let err = monitor.speedTestError {
                            Text(err)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("İndirme/yükleme hızınızı, boşta ping süresini ve yük altındaki bufferbloat (RPM) kalitesini ölçer.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.subtleText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            monitor.runSpeedTest()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text(monitor.lastSpeedTest == nil ? "Hız Testini Başlat" : "Yeniden Test Et")
                            }
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.16, green: 0.56, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.78)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(monitor.speedTesting)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(cardBg).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 1)))
                }
                .padding(.trailing, 2)
            }
        }
    }

    // MARK: - 4. Disk Detay Ekranı (Tam Dolu Tasarım, Üst/Alt Boş Bar Yok!)

    private var diskDetailView: some View {
        let free = max(0, monitor.diskTotal - monitor.diskUsed)
        return VStack(alignment: .leading, spacing: 12) {
            detailHeader(title: "Macintosh HD", icon: "internaldrive.fill", tint: .cyan) {
                Text(String(format: "%%%.0f Dolu", monitor.diskRatio * 100))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(free.formattedBytes)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("kullanılabilir")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.subtleText)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, Color(red: 0.55, green: 0.27, blue: 0.93)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * monitor.diskRatio))
                        }
                    }
                    .frame(height: 10)
                }

                HStack(spacing: 8) {
                    metricMiniBox(label: "Toplam Kapasite", value: monitor.diskTotal.formattedBytes, color: .white)
                    metricMiniBox(label: "Kullanılan Alan", value: monitor.diskUsed.formattedBytes, color: .pink)
                }

                metricMiniBox(label: "Çöp Kutusu Durumu", value: trashSubtitle, color: .orange)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 12).fill(cardBg).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 1)))

            VStack(spacing: 8) {
                Button {
                    onOpenMainWindow(.systemJunk)
                } label: {
                    Label("Sistem Çöpü Taramasını Aç", systemImage: "sparkles")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(LinearGradient(colors: NavModule.systemJunk.accentColors, startPoint: .leading, endPoint: .trailing))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/"))
                } label: {
                    Label("Macintosh HD'yi Finder'da Aç", systemImage: "folder.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.09)))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Sabit Üst Başlık (Asla Kaybolmaz)

    private func detailHeader<Trailing: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { page = .overview }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Geri")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            trailing()
        }
    }

    private func metricMiniBox(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.subtleText)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.045)))
    }

    // MARK: - Yardımcılar

    private var uptimeString: String {
        let sec = Int(ProcessInfo.processInfo.systemUptime)
        let days = sec / 86400
        let hours = (sec % 86400) / 3600
        let mins = (sec % 3600) / 60
        if days > 0 { return "Açık: \(days)g \(hours)sa" }
        return "Açık: \(hours)sa \(mins)dk"
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/sn", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/sn", bytesPerSec / 1024) }
        return String(format: "%.2f MB/sn", bytesPerSec / (1024 * 1024))
    }

    private func refreshTrash() {
        Task {
            trashState = await TrashService.inspect()
        }
    }

    private func emptyTrash() {
        emptyingTrash = true
        Task {
            _ = await TrashService.empty()
            emptyingTrash = false
            refreshTrash()
            monitor.updateFull()
        }
    }

    private func freeRAM() {
        freeingRAM = true
        Task {
            _ = await Shell.freeRAMPasswordlessOrSetup()
            freeingRAM = false
            monitor.updateFull()
            if page == .memory { monitor.refreshTopConsumers() }
        }
    }
}

struct SparklineGraph: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = values.isEmpty ? [0.0] : values
            let step = pts.count > 1 ? w / CGFloat(pts.count - 1) : w

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    for (idx, v) in pts.enumerated() {
                        let x = CGFloat(idx) * step
                        let y = h - CGFloat(min(max(v, 0), 1)) * (h - 4) - 2
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.42), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    for (idx, v) in pts.enumerated() {
                        let x = CGFloat(idx) * step
                        let y = h - CGFloat(min(max(v, 0), 1)) * (h - 4) - 2
                        if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
