import SwiftUI
import AppKit

struct OptimizationView: View {
    enum Tab: String, CaseIterable {
        case agents = "Başlangıç Servisleri"
        case login = "Giriş Öğeleri"
        case processes = "Ağır Tüketiciler"

        var icon: String {
            switch self {
            case .agents: return "gearshape.arrow.triangle.2.circlepath"
            case .login: return "person.crop.circle.badge.checkmark"
            case .processes: return "flame.fill"
            }
        }
    }

    @ObservedObject var model: OptimizationModel
    @ViewState private var tab: Tab = .agents
    @ViewState private var scopeFilter: LaunchItem.Scope? = nil
    @ViewState private var onlySafeToDisable = false

    private let colors = NavModule.optimization.accentColors

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Optimizasyon")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Teknik terimler olmadan hangi servisin ne işe yaradığını görün ve kaynak tüketen uygulamaları sıralayın")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    model.refresh(manual: true)
                } label: {
                    HStack(spacing: 6) {
                        if model.refreshingProcesses {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(model.refreshingProcesses ? "Ölçülüyor…" : "Yenile")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .disabled(model.refreshingProcesses)
            }
            .padding(.top, 8)

            HStack(spacing: 12) {
                let safeCount = model.launchAgents.filter { $0.recommendation == .safeToDisable }.count
                tabCard(.agents, count: "\(model.launchAgents.count) servis (\(safeCount) gereksiz)", subtitle: "Arka plan güncelleyici ve yardımcıları")
                tabCard(.login, count: "\(model.loginItems.count) öğe", subtitle: "Oturum açılış uygulamaları")
                tabCard(.processes, count: "\(model.processes.count) uygulama", subtitle: "Çoktan aza sıralı CPU & RAM")
            }

            if let msg = model.message {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(colors[0])
                    Text(msg)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.message = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(Theme.subtleText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }

            GlassCard(padding: 16) {
                switch tab {
                case .agents:
                    launchAgentsList
                case .login:
                    loginItemsList
                case .processes:
                    processesList
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if model.launchAgents.isEmpty && model.processes.isEmpty {
                model.refresh()
            }
        }
        .task(id: tab) {
            guard tab == .processes else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.0))
                guard !Task.isCancelled else { break }
                model.refreshProcesses(manual: false)
            }
        }
    }

    private func tabCard(_ t: Tab, count: String, subtitle: String) -> some View {
        let active = tab == t
        return Button {
            tab = t
        } label: {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(active ? colors[0].opacity(0.28) : Color.white.opacity(0.07))
                        .frame(width: 38, height: 38)
                    Image(systemName: t.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(active ? colors[0] : .white.opacity(0.78))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.rawValue)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(count)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors[0])
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? colors[0].opacity(0.18) : Theme.cardSolid)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(active ? colors[0].opacity(0.58) : Theme.cardStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - İnsan Diliyle Açıklamalı Başlangıç Servisleri

    private var launchAgentsList: some View {
        let items = model.launchAgents.filter { item in
            let scopeMatch = (scopeFilter == nil || item.scope == scopeFilter)
            let recMatch = (!onlySafeToDisable || item.recommendation == .safeToDisable)
            return scopeMatch && recMatch
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                scopePill(nil, title: "Tümü (\(model.launchAgents.count))")
                scopePill(.user, title: "Kullanıcı")
                scopePill(.global, title: "Tüm Kullanıcılar")
                scopePill(.daemon, title: "Sistem Servisi")

                Spacer()

                Toggle(isOn: $onlySafeToDisable) {
                    Text("Sadece güvenle kapatılabilirler")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.successGreen)
                }
                .toggleStyle(.checkbox)
            }

            if items.isEmpty {
                Text("Bu filtreye uygun başlangıç servisi bulunmuyor.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.subtleText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            let recColor = recommendationColor(item.recommendation)
                            HStack(alignment: .top, spacing: 13) {
                                if let icon = item.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(recColor.opacity(0.18))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "gearshape.2.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(recColor)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(item.friendlyTitle)
                                            .font(.system(size: 13.5, weight: .bold))
                                            .foregroundStyle(.white)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Text(item.recommendation.badgeTitle)
                                            .font(.system(size: 10.5, weight: .bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(recColor.opacity(0.20)))
                                            .foregroundStyle(recColor)

                                        Text(item.scope.rawValue)
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.white.opacity(0.08)))
                                            .foregroundStyle(Theme.subtleText)
                                    }

                                    Text(item.plainExplanation)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.86))
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text("💡 \(item.impactNote)")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(recColor.opacity(0.95))
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text("Teknik ad: \(item.label)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.faintText)
                                }

                                Spacer(minLength: 8)

                                HStack(spacing: 8) {
                                    RevealInFinderButton(url: item.url)
                                    Button("Devre Dışı Bırak") {
                                        model.disable(item)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(
                                            item.recommendation == .safeToDisable
                                                ? Theme.successGreen.opacity(0.32)
                                                : Color.white.opacity(0.11)
                                        )
                                    )
                                    .fixedSize()
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.035))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                            )
                        }
                    }
                }
            }
        }
    }

    private func recommendationColor(_ rec: ServiceRecommendation) -> Color {
        switch rec {
        case .safeToDisable: return Theme.successGreen
        case .keepIfUsed: return .orange
        case .optional: return .cyan
        }
    }

    private func scopePill(_ scope: LaunchItem.Scope?, title: String) -> some View {
        let selected = scopeFilter == scope
        return Button {
            scopeFilter = scope
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(selected ? .white : Theme.subtleText)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? colors[0].opacity(0.32) : Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Giriş Öğeleri

    private var loginItemsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let err = model.loginItemsError {
                VStack(alignment: .leading, spacing: 10) {
                    Label(err, systemImage: "lock.shield")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Sistem Ayarları › Giriş Öğeleri'ni Aç") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(colors[0].opacity(0.35)))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
            } else if model.loginItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.successGreen)
                    Text("Kayıtlı klasik giriş öğesi bulunmuyor")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Modern macOS uygulamalarının arka plan servislerini soldaki 'Başlangıç Servisleri' sekmesinden sade açıklamalarla yönetebilirsiniz.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.subtleText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.loginItems, id: \.self) { name in
                            HStack {
                                Image(systemName: "app.badge.checkmark.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(colors[0])
                                Text(name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button("Kaldır") {
                                    model.removeLoginItem(name)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(colors[1].opacity(0.35)))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Çoktan Aza Sıralı, Gruplanmış Ağır Tüketiciler

    private var processesList: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Toggle(isOn: $model.showSystemProcesses) {
                    Text("Arka plan macOS servislerini de göster")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subtleText)
                }
                .toggleStyle(.checkbox)

                Spacer()
                Text("Sırala:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.subtleText)
                Picker("", selection: $model.sortOrder) {
                    ForEach(ProcessSortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 270)
            }

            HStack {
                Text("UYGULAMA / SÜREÇ")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("İŞLEMCİ (CPU)")
                    .frame(width: 105, alignment: .trailing)
                Text("BELLEK (RAM)")
                    .frame(width: 115, alignment: .trailing)
                Spacer().frame(width: 112)
            }
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(Theme.faintText)
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.sortedProcesses) { proc in
                        HStack(spacing: 12) {
                            HStack(spacing: 10) {
                                if let icon = proc.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 28, height: 28)
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(Color.white.opacity(0.08))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: "gearshape.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.subtleText)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(proc.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(proc.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.faintText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(String(format: "%%%.1f", proc.cpu))
                                .font(.system(size: 13, weight: model.sortOrder == .cpu ? .bold : .medium, design: .rounded))
                                .foregroundStyle(proc.cpu > 40 ? Color.pink : (model.sortOrder == .cpu ? .white : Theme.subtleText))
                                .monospacedDigit()
                                .frame(width: 105, alignment: .trailing)

                            Text(proc.memoryMB >= 1024 ? String(format: "%.2f GB", proc.memoryMB / 1024.0) : String(format: "%.0f MB", proc.memoryMB))
                                .font(.system(size: 13, weight: model.sortOrder == .memory ? .bold : .medium, design: .rounded))
                                .foregroundStyle(model.sortOrder == .memory ? .white : Theme.subtleText)
                                .monospacedDigit()
                                .frame(width: 115, alignment: .trailing)

                            Group {
                                if proc.isSystemCritical {
                                    Text("Sistem Korumalı")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(Theme.faintText)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(Color.white.opacity(0.06)))
                                } else {
                                    Button("Sonlandır") {
                                        model.kill(proc)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.red.opacity(0.34)))
                                }
                            }
                            .frame(width: 112, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
                    }
                }
            }
        }
    }
}
