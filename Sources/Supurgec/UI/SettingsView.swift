import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings = MenuBarSettings.shared
    @ObservedObject var monitor = SystemMonitor.shared
    @ViewState private var launchAtLogin = LaunchAtLoginService.isEnabled
    @ViewState private var helperInstalled = FileManager.default.fileExists(atPath: Shell.sudoersPath)
    @ViewState private var fullDiskAccess = TrashService.hasFullDiskAccess()
    @ViewState private var statusBanner: String?

    private let colors = NavModule.settings.accentColors

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ayarlar ve Öz Kaynak İzleyici")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(NavModule.settings.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)

                if let banner = statusBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.successGreen)
                        Text(banner).font(.system(size: 12.5)).foregroundStyle(.white)
                        Spacer()
                        Button { statusBanner = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(Theme.subtleText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Theme.successGreen.opacity(0.16)))
                }

                menuBarCustomizationCard
                selfResourceCard
                permissionsCard
                aboutCard
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStates()
        }
    }

    private func refreshPermissionStates() {
        launchAtLogin = LaunchAtLoginService.isEnabled
        helperInstalled = FileManager.default.fileExists(atPath: Shell.sudoersPath)
        fullDiskAccess = TrashService.hasFullDiskAccess()
    }

    // MARK: - 1. Üst Menü Çubuğu Kişiselleştirme Kartı

    private var menuBarCustomizationCard: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Üst Menü Çubuğu Görünümü", systemImage: "menubar.rectangle")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()

                    HStack(spacing: 5) {
                        Text("Canlı Önizleme:")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faintText)
                        HStack(spacing: 3) {
                            if let sym = settings.iconChoice.symbolName {
                                Image(systemName: sym)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Text(settings.formattedTitle(monitor: monitor).trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                        )
                    }
                }

                Divider().overlay(Color.white.opacity(0.09))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Menü Çubuğu İkonu (İstediğinizi seçin veya ikonu tamamen kaldırın)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], spacing: 8) {
                        ForEach(MenuBarIconChoice.allCases) { choice in
                            let selected = settings.iconChoice == choice
                            Button {
                                settings.iconChoice = choice
                            } label: {
                                HStack(spacing: 8) {
                                    if let sym = choice.symbolName {
                                        Image(systemName: sym)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(selected ? colors[0] : .white.opacity(0.75))
                                            .frame(width: 18)
                                    } else {
                                        Image(systemName: "nosign")
                                            .font(.system(size: 12))
                                            .foregroundStyle(selected ? colors[0] : Theme.faintText)
                                            .frame(width: 18)
                                    }
                                    Text(choice.title)
                                        .font(.system(size: 12, weight: selected ? .bold : .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(selected ? colors[0].opacity(0.22) : Color.white.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9)
                                                .strokeBorder(selected ? colors[0].opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.09))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Üst Barda Gösterilecek Veriler (Sabit genişlikli, sağa sola kayma yapmaz)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    HStack(spacing: 12) {
                        toggleTile(title: "İşlemci (CPU)", subtitle: "Anlık % yük", icon: "cpu", isOn: $settings.showCPU)
                        toggleTile(title: "Bellek (RAM)", subtitle: "% veya GB gösterimi", icon: "memorychip", isOn: $settings.showRAM)
                        toggleTile(title: "Ağ Hızı", subtitle: "Anlık indirme", icon: "network", isOn: $settings.showNetwork)
                        toggleTile(title: "Boş Disk", subtitle: "Kalan GB", icon: "internaldrive", isOn: $settings.showDisk)
                    }

                    HStack(spacing: 20) {
                        if settings.showRAM {
                            HStack(spacing: 8) {
                                Text("RAM Biçimi:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.subtleText)
                                Picker("", selection: $settings.ramFormat) {
                                    ForEach(RAMDisplayFormat.allCases) { fmt in
                                        Text(fmt.title).tag(fmt)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 240)
                            }
                        }

                        Toggle(isOn: $settings.showLabels) {
                            Text("Birden fazla veri açıkken 'CPU / RAM' etiketi yaz")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                        .toggleStyle(.checkbox)

                        Spacer()
                    }
                    .padding(.top, 4)
                }

                Divider().overlay(Color.white.opacity(0.09))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ölçüm Yenileme Sıklığı")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Daha uzun süre pil tasarrufunu artırır")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.subtleText)
                    }
                    Spacer()
                    Picker("", selection: $settings.refreshInterval) {
                        Text("Hızlı (1 sn)").tag(1.0)
                        Text("Dengeli (2 sn)").tag(2.0)
                        Text("Tasarruf (5 sn)").tag(5.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 290)
                }
            }
        }
    }

    private func toggleTile(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isOn.wrappedValue ? colors[0] : Theme.subtleText)
                    Spacer()
                    Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn.wrappedValue ? colors[0] : Theme.faintText)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtleText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isOn.wrappedValue ? colors[0].opacity(0.18) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(isOn.wrappedValue ? colors[0].opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Süpürgeç Canlı Öz Kaynak Tüketimi

    private var selfResourceCard: some View {
        let statusTint: Color = monitor.isBusyTaskRunning ? .cyan : Theme.successGreen
        return GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Süpürgeç Anlık Öz Kaynak Kullanımı", systemImage: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusTint)
                            .frame(width: 8, height: 8)
                        Text(monitor.currentActivity)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(statusTint)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(statusTint.opacity(0.15)))
                }

                Text("Süpürgeç'in Mac'inizde kendi tükettiği gerçek çekirdek verileri (toplam Mac kapasitesine göre):")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subtleText)

                HStack(spacing: 12) {
                    selfStatBox(
                        title: "Kendi CPU Kullanımı",
                        value: String(format: "%%%.1f", monitor.selfCPUPercent),
                        detail: "Pencere kapalıyken ~%0,0",
                        icon: "cpu.fill",
                        tint: colors[0]
                    )
                    selfStatBox(
                        title: "Kendi Bellek (RAM) İzi",
                        value: monitor.selfMemoryBytes.formattedMemory,
                        detail: "Yerel Swift ikilisi",
                        icon: "memorychip",
                        tint: Theme.successGreen
                    )
                    selfStatBox(
                        title: "Kendi GPU Kullanımı",
                        value: monitor.selfGPUActive ? "Aktif" : "%0",
                        detail: monitor.selfGPUActive ? "Tarama animasyonu aktif" : "Boştayken animasyonlar kapalı",
                        icon: "sparkles.tv.fill",
                        tint: .purple
                    )
                    selfStatBox(
                        title: "Kendi Disk Okuma/Yazma",
                        value: formatDiskSpeed(monitor.selfDiskSpeedBps),
                        detail: "Toplam: \((Int64(monitor.selfDiskReadBytes + monitor.selfDiskWriteBytes)).formattedBytes)",
                        icon: "internaldrive.fill",
                        tint: .orange
                    )
                }
            }
        }
    }

    private func selfStatBox(title: String, value: String, detail: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.faintText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.045)))
    }

    private func formatDiskSpeed(_ bps: Double) -> String {
        if bps < 1024 { return "0 KB/sn" }
        if bps < 1024 * 1024 { return String(format: "%.0f KB/sn", bps / 1024) }
        return String(format: "%.1f MB/sn", bps / (1024 * 1024))
    }

    // MARK: - 3. İzinler ve Tek Seferlik Şifre Yönetimi (Canlı Tam Disk Erişimi Algılamalı!)

    private var permissionsCard: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("İzinler ve Şifresiz Bakım Yetkisi", systemImage: "lock.shield.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        refreshPermissionStates()
                    } label: {
                        Label("Durumu Kontrol Et", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.subtleText)
                    }
                    .buttonStyle(.plain)
                }

                // 0. Satır: Bilgisayar Açılışında Üst Barda Başlat
                HStack(spacing: 14) {
                    Image(systemName: launchAtLogin ? "menubar.dock.rectangle.badge.record" : "menubar.rectangle")
                        .font(.system(size: 22))
                        .foregroundStyle(launchAtLogin ? Theme.successGreen : Theme.subtleText)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Bilgisayar Açıldığında Yalnızca Üst Barda Başlat")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white)
                            statusPill(active: launchAtLogin)
                        }
                        Text("Mac yeniden başladığında veya açıldığında ana pencere ve Dock ikonu açılmaz; yalnızca üst menü çubuğu göstergesi sessizce başlar.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newVal in
                            if LaunchAtLoginService.setEnabled(newVal) {
                                launchAtLogin = newVal
                                statusBanner = newVal
                                    ? "Oturum açılışında üst barda sessiz başlatma etkinleştirildi."
                                    : "Oturum açılışında otomatik başlatma kapatıldı."
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Divider().overlay(Color.white.opacity(0.09))

                // 1. Satır: Şifresiz RAM & DNS
                HStack(spacing: 14) {
                    Image(systemName: helperInstalled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(helperInstalled ? Theme.successGreen : .orange)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Şifresiz RAM Boşaltma ve DNS Temizleme Yetkisi")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white)
                            statusPill(active: helperInstalled)
                        }
                        Text("Aktif olduğunda RAM boşaltırken ve DNS sıfırlarken her seferinde şifre sormaz.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if helperInstalled {
                        Button("Yetkiyi Kaldır") {
                            let r = Shell.runAsAdmin("/bin/rm -f \(Shell.quote(Shell.sudoersPath))")
                            refreshPermissionStates()
                            if r.ok { statusBanner = "Şifresiz yetki kaldırıldı." }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.red.opacity(0.32)))
                        .fixedSize()
                    } else {
                        Button("Tek Seferlik Yetkilendir") {
                            Task {
                                let ok = await Shell.freeRAMPasswordlessOrSetup()
                                refreshPermissionStates()
                                if ok { statusBanner = "Tek seferlik yetki tanımlandı; artık şifre sormadan çalışacak." }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(colors[0].opacity(0.35)))
                        .fixedSize()
                    }
                }

                Divider().overlay(Color.white.opacity(0.09))

                // 2. Satır: Tam Disk Erişimi (Canlı Doğrulamalı!)
                HStack(spacing: 14) {
                    Image(systemName: fullDiskAccess ? "checkmark.shield.fill" : "folder.badge.questionmark")
                        .font(.system(size: 22))
                        .foregroundStyle(fullDiskAccess ? Theme.successGreen : .orange)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Tam Disk Erişimi (Çöp Kutusu ve Tüm Önbellekler)")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white)
                            statusPill(active: fullDiskAccess)
                        }
                        Text(fullDiskAccess
                             ? "Tam Disk Erişimi doğrulandı. Çöp Kutusu, Mail ve Safari önbellekleri doğrudan tam hızda okunuyor."
                             : "Verildiğinde Finder'a sormaya gerek kalmadan Çöp Kutusu ve tüm korumalı uygulama önbellekleri doğrudan okunur.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()

                    if fullDiskAccess {
                        HStack(spacing: 8) {
                            Label("Tam Erişim Verildi", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.successGreen)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Theme.successGreen.opacity(0.15)))

                            Button {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.subtleText)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .help("Sistem Ayarları › Tam Disk Erişimi")
                        }
                        .fixedSize()
                    } else {
                        Button("Sistem Ayarları'nı Aç") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.orange.opacity(0.32)))
                        .fixedSize()
                    }
                }
            }
        }
    }

    private func statusPill(active: Bool) -> some View {
        Text(active ? "Aktif" : "İzin Bekleniyor")
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill((active ? Theme.successGreen : Color.orange).opacity(0.22)))
            .foregroundStyle(active ? Theme.successGreen : .orange)
    }

    // MARK: - 4. Hakkında & Katkı Kartı

    private var aboutCard: some View {
        GlassCard(padding: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Süpürgeç · Sürüm 0.1 Alpha")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Ensar Gemici katkılarıyla geliştirilmiştir.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subtleText)
                }
                Spacer()
                Text("macOS Yerel (SwiftUI + AppKit)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.faintText)
            }
        }
    }
}
