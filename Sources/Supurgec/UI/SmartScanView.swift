import SwiftUI

struct SmartScanView: View {
    @ObservedObject var model: SmartScanModel
    var onNavigate: (NavModule) -> Void

    private let colors = NavModule.smartScan.accentColors

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            switch model.phase {
            case .idle:
                idleContent
            case .scanning, .results, .running:
                cardsContent
            case .done:
                doneContent
            }

            Spacer(minLength: 12)
            bottomBar
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Karşılama

    private var idleContent: some View {
        VStack(spacing: 20) {
            HeroMedallion(symbol: NavModule.smartScan.heroSymbol, colors: colors, size: 196)

            VStack(spacing: 10) {
                Text("Süpürgeç Akıllı Tarama")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(NavModule.smartScan.subtitle)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.subtleText)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
            }
            .layoutPriority(1)

            HStack(spacing: 14) {
                pillarPill(icon: "trash.fill", label: "Temizlik", color: colors[2])
                pillarPill(icon: "bolt.fill", label: "Hız", color: colors[0])
                pillarPill(icon: "gauge.with.dots.needle.67percent", label: "Optimizasyon", color: colors[1])
            }
            .padding(.top, 4)
        }
    }

    private func pillarPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.90))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.07))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        )
    }

    // MARK: - 3 Sütunlu Tarama / Sonuç Kartları

    private var cardsContent: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text(headerTitle)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(headerSubtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.subtleText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 600)
            }

            HStack(alignment: .top, spacing: 16) {
                smartCard(
                    title: "Temizlik",
                    icon: "externaldrive.fill.badge.minus",
                    tint: Color(red: 0.98, green: 0.34, blue: 0.62),
                    state: model.cleanupState,
                    headline: model.cleanupState == .finished
                        ? (model.junkScanner.selectedSize > 0 ? model.junkScanner.selectedSize.formattedBytes : "Temiz")
                        : "Taranıyor…",
                    caption: model.cleanupState == .finished
                        ? (model.junkScanner.selectedSize > 0 ? "Gereksiz önbellek ve günlük dosyaları bulundu" : "Silinecek çöp bulunamadı")
                        : (model.junkScanner.currentPath.isEmpty ? "Dosyalar analiz ediliyor" : model.junkScanner.currentPath),
                    toggle: model.phase == .results && model.junkScanner.selectedSize > 0 ? $model.runCleanJunk : nil,
                    linkTitle: model.cleanupState == .finished ? "Sistem Çöpü'nü İncele" : nil,
                    onLink: { onNavigate(.systemJunk) }
                )

                smartCard(
                    title: "Hız",
                    icon: "bolt.fill",
                    tint: Color(red: 0.28, green: 0.76, blue: 1.00),
                    state: model.speedState,
                    headline: model.speedState == .finished ? "2 Hızlı Görev" : (model.speedState == .active ? "Kontrol…" : "Bekliyor"),
                    caption: "Quick Look ve Launch Services önbelleklerini tazeler",
                    toggle: model.phase == .results ? $model.runFlushDNSAndCache : nil,
                    linkTitle: model.speedState == .finished ? "Tüm Bakım Görevleri" : nil,
                    onLink: { onNavigate(.maintenance) }
                )

                smartCard(
                    title: "Optimizasyon",
                    icon: "gauge.with.dots.needle.67percent",
                    tint: Color(red: 1.00, green: 0.62, blue: 0.24),
                    state: model.optState,
                    headline: model.optState == .finished
                        ? "\(model.optimization.launchAgents.count) Servis"
                        : (model.optState == .active ? "İnceleniyor…" : "Bekliyor"),
                    caption: topProcessSummary,
                    toggle: nil,
                    linkTitle: model.optState == .finished ? "Servisleri Yönet" : nil,
                    onLink: { onNavigate(.optimization) }
                )
            }
            .frame(maxWidth: 860)
        }
    }

    private var headerTitle: String {
        switch model.phase {
        case .scanning: return "Mac'iniz Analiz Ediliyor…"
        case .results: return "Tarama Tamamlandı"
        case .running: return "Akıllı Bakım Uygulanıyor…"
        default: return ""
        }
    }

    private var headerSubtitle: String {
        if !model.currentSubtitle.isEmpty { return model.currentSubtitle }
        if !model.junkScanner.currentPath.isEmpty { return model.junkScanner.currentPath }
        return "Seçili iyileştirmeleri tek dokunuşla çalıştırabilir veya modül ayrıntılarını inceleyebilirsiniz."
    }

    private var topProcessSummary: String {
        if let top = model.optimization.processes.first {
            return String(format: "En yoğun süreç: %@ (%%%.0f CPU)", top.name, top.cpu)
        }
        return "Başlangıç servisleri ve süreçler denetlendi"
    }

    private func smartCard(
        title: String,
        icon: String,
        tint: Color,
        state: SmartScanModel.StepState,
        headline: String,
        caption: String,
        toggle: Binding<Bool>?,
        linkTitle: String?,
        onLink: @escaping () -> Void
    ) -> some View {
        GlassCard(padding: 18) {
            VStack(spacing: 14) {
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(tint)
                    Spacer()
                    if let toggle {
                        RoundCheckbox(isOn: toggle, accent: tint)
                    } else if state == .active {
                        ProgressView().controlSize(.small)
                    } else if state == .finished {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.successGreen)
                    }
                }

                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 68, height: 68)
                        .overlay(Circle().strokeBorder(tint.opacity(0.38), lineWidth: 1.2))
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(spacing: 6) {
                    Text(headline)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subtleText)
                        .lineSpacing(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 42, alignment: .top)
                }

                if let linkTitle {
                    Button(action: onLink) {
                        HStack(spacing: 4) {
                            Text(linkTitle)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.09)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(height: 26)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Tamamlandı

    private var doneContent: some View {
        VStack(spacing: 20) {
            HeroMedallion(
                symbol: "checkmark.seal.fill",
                colors: [Theme.successGreen, Color(red: 0.16, green: 0.72, blue: 0.92), Color(red: 0.36, green: 0.50, blue: 0.98)],
                size: 186
            )

            VStack(spacing: 8) {
                Text("Mac'iniz Tertemiz ve Hazır!")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 18) {
                    Label("\(model.freedBytes.formattedBytes) alan açıldı", systemImage: "internaldrive.fill")
                    if model.ranTasksCount > 0 {
                        Label("\(model.ranTasksCount) hızlandırma görevi tamamlandı", systemImage: "bolt.fill")
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.subtleText)
            }
        }
    }

    // MARK: - Alt Aksiyon Çubuğu

    @ViewBuilder
    private var bottomBar: some View {
        switch model.phase {
        case .idle:
            OrbActionButton(title: "Tara", colors: colors) {
                Task { await model.startScan() }
            }
        case .scanning:
            OrbActionButton(title: "Taranıyor", colors: colors, isBusy: true) {}
        case .results:
            ZStack {
                HStack {
                    Button {
                        model.reset()
                    } label: {
                        Label("Baştan Başla", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.subtleText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                OrbActionButton(
                    title: "Çalıştır",
                    colors: colors,
                    isDisabled: !model.runCleanJunk && !model.runFlushDNSAndCache
                ) {
                    Task { await model.executeSmartClean() }
                }
            }
        case .running:
            OrbActionButton(title: "Çalışıyor", colors: colors, isBusy: true) {}
        case .done:
            OrbActionButton(title: "Yeniden\nTara", colors: colors) {
                Task { await model.startScan() }
            }
        }
    }
}
