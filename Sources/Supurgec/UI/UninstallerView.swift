import SwiftUI
import AppKit

struct UninstallerView: View {
    enum Filter: String, CaseIterable {
        case all = "Tümü"
        case user = "Kullanıcı"
        case large = "Büyük (>150 MB)"
        case system = "Apple / Sistem"
    }

    enum ActionMode: String, CaseIterable {
        case uninstall = "Tam Kaldır"
        case reset = "Uygulamayı Sıfırla"
    }

    @ObservedObject var model: UninstallerModel
    @ViewState private var filter: Filter = .user
    @ViewState private var mode: ActionMode = .uninstall
    @ViewState private var confirmPermanent = false

    private let colors = NavModule.uninstaller.accentColors

    private var displayedApps: [AppInfo] {
        model.filtered.filter { app in
            switch filter {
            case .all: return true
            case .user: return !app.isSystem
            case .large: return (app.size ?? 0) >= 150 * 1024 * 1024
            case .system: return app.isSystem
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            headerBar
                .padding(.top, 8)

            if let msg = model.message {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.successGreen)
                    Text(msg)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.message = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(Theme.subtleText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.successGreen.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.successGreen.opacity(0.35), lineWidth: 1))
                )
            }

            HStack(spacing: 14) {
                appListPane
                detailPane
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if model.apps.isEmpty { await model.load() }
        }
    }

    // MARK: - Üst Çubuk

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uygulama Kaldırıcı")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(displayedApps.count) uygulama listeleniyor · Derin kalıntı taraması aktif")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.subtleText)
                }

                Spacer()

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.faintText)
                    TextField("Uygulama ara…", text: $model.search)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .font(.system(size: 12.5))
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faintText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(width: 220)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )

                Button {
                    Task { await model.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .help("Uygulama listesini yenile")
            }

            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button {
                        filter = f
                    } label: {
                        Text(f.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(filter == f ? .white : Theme.subtleText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(filter == f ? colors[0].opacity(0.35) : Color.white.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                Toggle(isOn: $model.permanentDelete) {
                    Text("Çöp Kutusu'nu atla (Kalıcı sil)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(model.permanentDelete ? .pink : Theme.subtleText)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Sol Uygulama Listesi

    private var appListPane: some View {
        GlassCard(padding: 10) {
            if model.loading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Uygulamalar taranıyor…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.subtleText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.faintText)
                    Text("Eşleşen uygulama yok")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.subtleText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(displayedApps) { app in
                            let selected = model.selectedID == app.id
                            HStack(spacing: 11) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 34, height: 34)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(app.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if app.isSystem {
                                            Image(systemName: "lock.shield.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Theme.faintText)
                                        }
                                    }
                                    Text(app.version.isEmpty ? app.bundleID : "Sürüm \(app.version)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.faintText)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if let s = app.size {
                                    Text(s.formattedBytes)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.84))
                                } else {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(selected ? colors[0].opacity(0.24) : Color.white.opacity(0.025))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(selected ? colors[0].opacity(0.55) : .clear, lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if app.isSIPProtected {
                                    mode = .reset
                                }
                                Task { await model.select(app) }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 315)
    }

    // MARK: - Sağ Ayrıntı & Derin Kalıntı Paneli

    private var detailPane: some View {
        GlassCard(padding: 18) {
            if let app = model.selectedApp {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 14) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 56, height: 56)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(app.name)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    RevealInFinderButton(url: app.url)
                                }
                                Text(app.bundleID.isEmpty ? app.url.path : app.bundleID)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Theme.subtleText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("Toplam Boyut: \(((app.size ?? 0) + model.leftoversSelectedSize).formattedBytes) (\(model.leftovers.count) kalıntı konumu bulundu)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(colors[0])
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Picker("", selection: $mode) {
                            ForEach(ActionMode.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    Divider().overlay(Color.white.opacity(0.10))

                    Text(mode == .uninstall
                         ? "Uygulama kapatılır, arka plan servisleri durdurulur, tercih önbelleği sıfırlanır ve seçili tüm dosyalar silinir:"
                         : "Uygulamanın kendisi korunur; yalnızca seçili önbellek, servis ve ayar dosyaları sıfırlanır:")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subtleText)
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        VStack(spacing: 5) {
                            HStack(spacing: 10) {
                                Image(systemName: mode == .uninstall ? "checkmark.circle.fill" : "shield.lefthalf.filled")
                                    .foregroundStyle(mode == .uninstall ? colors[0] : Theme.successGreen)
                                Text("\(app.name).app")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(mode == .uninstall ? "Ana Uygulama Paketi" : "Korunacak")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.white.opacity(0.10)))
                                    .foregroundStyle(Theme.subtleText)
                                Spacer(minLength: 4)
                                RevealInFinderButton(url: app.url)
                                Text((app.size ?? 0).formattedBytes)
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))

                            if model.findingLeftovers {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("~/Library, /Library, arka plan servisleri ve kurulum kayıtları taranıyor…")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Theme.subtleText)
                                }
                                .padding(.top, 16)
                            } else if model.leftovers.isEmpty {
                                Text("Ek kalıntı dosya veya arka plan servisi bulunamadı.")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.faintText)
                                    .padding(.top, 16)
                            } else {
                                ForEach(model.leftovers.indices, id: \.self) { i in
                                    let item = model.leftovers[i]
                                    HStack(spacing: 10) {
                                        RoundCheckbox(isOn: $model.leftovers[i].selected, accent: colors[0])
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(item.name)
                                                    .font(.system(size: 12.5, weight: .medium))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                Text(item.kind)
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 1.5)
                                                    .background(Capsule().fill(colors[0].opacity(0.18)))
                                                    .foregroundStyle(colors[0])
                                                if item.requiresAdmin {
                                                    Image(systemName: "key.fill")
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(Theme.faintText)
                                                        .help("Sistem dizininde — yönetici izni gerektirir")
                                                }
                                            }
                                            Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: FileUtils.home.path, with: "~"))
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(Theme.faintText)
                                                .truncationMode(.middle)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 4)
                                        RevealInFinderButton(url: item.url)
                                        Text(item.size.formattedBytes)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
                                }
                            }
                        }
                    }

                    if app.isSIPProtected {
                        Label("Bu yerleşik bir Apple sistem uygulamasıdır (SIP korumalı). Uygulamanın kendisi silinemez; ancak 'Uygulamayı Sıfırla' moduyla önbellek ve ayarlarını temizleyebilirsiniz.", systemImage: "lock.shield.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.cyan)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Spacer()
                        OrbActionButton(
                            title: mode == .uninstall ? "Kaldır" : "Sıfırla",
                            colors: model.permanentDelete ? [Color.red, Color.pink, colors[2]] : colors,
                            isBusy: model.working,
                            isDisabled: (mode == .reset && model.leftoversSelectedSize == 0) || (mode == .uninstall && app.isSIPProtected)
                        ) {
                            if model.permanentDelete {
                                confirmPermanent = true
                            } else {
                                Task {
                                    if mode == .uninstall {
                                        await model.uninstall(app, permanently: false)
                                    } else {
                                        await model.resetSelectedLeftovers(for: app, permanently: false)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .alert("Kalıcı Olarak Silinsin mi?", isPresented: $confirmPermanent) {
                        Button("Vazgeç", role: .cancel) {}
                        Button("Evet, Kalıcı Olarak Yok Et", role: .destructive) {
                            Task {
                                if mode == .uninstall {
                                    await model.uninstall(app, permanently: true)
                                } else {
                                    await model.resetSelectedLeftovers(for: app, permanently: true)
                                }
                            }
                        }
                    } message: {
                        Text("\(app.name) ve seçili tüm sistem kalıntıları Çöp Kutusu'na uğramadan kalıcı olarak silinecek. Bu işlem geri alınamaz.")
                    }
                }
            } else {
                VStack(spacing: 16) {
                    HeroMedallion(symbol: NavModule.uninstaller.heroSymbol, colors: colors, size: 152)
                    Text("Kaldırmak veya Sıfırlamak İçin Bir Uygulama Seçin")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Süpürgeç; ~/Library, sistem /Library dizinleri, arka plan servisleri, yetkili yardımcılar ve kurulum fişleri dahil 24 ayrı noktayı tarayarak tek bir kalıntı bırakmaz.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.subtleText)
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
