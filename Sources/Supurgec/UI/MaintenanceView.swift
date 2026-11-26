import SwiftUI

struct MaintenanceView: View {
    @ObservedObject var model: MaintenanceModel
    @ViewState private var activeID: String = "ram"

    private let colors = NavModule.maintenance.accentColors

    private var activeTask: MaintenanceTask {
        model.tasks.first { $0.id == activeID } ?? model.tasks[0]
    }

    private var helperAuthorized: Bool {
        FileManager.default.fileExists(atPath: Shell.sudoersPath)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bakım Görevleri")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(model.selectedCount) görev çalıştırılmak üzere seçildi")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.subtleText)
                }
                Spacer()
                if model.finished {
                    Button {
                        model.reset()
                    } label: {
                        Label("Durumu Sıfırla", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.09)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)

            HStack(spacing: 16) {
                GlassCard(padding: 10) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(model.tasks.indices, id: \.self) { i in
                                let t = model.tasks[i]
                                let isCurrent = t.id == activeTask.id
                                HStack(alignment: .center, spacing: 11) {
                                    RoundCheckbox(isOn: $model.tasks[i].selected, accent: colors[0])

                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(colors[0].opacity(0.20))
                                            .frame(width: 32, height: 32)
                                        Image(systemName: t.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(colors[0])
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                                            Text(t.title)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if t.admin && !(t.oneTimeAuth && helperAuthorized) {
                                                Image(systemName: "key.fill")
                                                    .font(.system(size: 9.5))
                                                    .foregroundStyle(Theme.faintText)
                                                    .help("Yönetici izni gerektirir")
                                            }
                                        }
                                        statusSubtitle(t.status)
                                    }
                                    Spacer(minLength: 4)
                                    statusIcon(t.status)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(isCurrent ? colors[0].opacity(0.24) : Color.white.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .strokeBorder(isCurrent ? colors[0].opacity(0.58) : .clear, lineWidth: 1)
                                        )
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { activeID = t.id }
                            }
                        }
                    }
                }
                .frame(width: 356)

                GlassCard(padding: 24) {
                    VStack(spacing: 16) {
                        Spacer(minLength: 4)

                        HeroMedallion(symbol: activeTask.icon, colors: colors, scanning: model.running, size: 152)

                        VStack(spacing: 10) {
                            Text(activeTask.title)
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(activeTask.detail)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.subtleText)
                                .lineSpacing(3)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 420)
                        }
                        .layoutPriority(1)

                        VStack(spacing: 8) {
                            if activeTask.oneTimeAuth {
                                if helperAuthorized {
                                    Label("Tek seferlik yetki tanımlı · Şifre sormadan anında çalışır", systemImage: "checkmark.shield.fill")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.successGreen)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Label("Şifrenizi yalnızca ilk seferde ister; sonrasında şifresiz çalışır", systemImage: "lock.open.rotation")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.orange.opacity(0.95))
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else if activeTask.admin {
                                Label("Çalıştırıldığında macOS yönetici parolası ister", systemImage: "lock.shield")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.orange.opacity(0.95))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(activeTask.command)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.faintText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: 420)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.28)))
                        }
                        .layoutPriority(1)

                        Spacer(minLength: 4)

                        OrbActionButton(
                            title: "Çalıştır",
                            colors: colors,
                            isBusy: model.running,
                            isDisabled: model.selectedCount == 0
                        ) {
                            Task { await model.runSelected() }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func statusSubtitle(_ status: MaintenanceTask.Status) -> some View {
        switch status {
        case .idle:
            Text("Hazır").font(.system(size: 11)).foregroundStyle(Theme.faintText)
        case .running:
            Text("Çalıştırılıyor…").font(.system(size: 11)).foregroundStyle(colors[0])
        case .done:
            Text("Tamamlandı").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.successGreen)
        case .failed:
            Text("İptal edildi / Hata").font(.system(size: 11)).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: MaintenanceTask.Status) -> some View {
        switch status {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.successGreen)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
