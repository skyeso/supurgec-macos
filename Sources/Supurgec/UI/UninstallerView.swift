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
        case uninstall = "Kökten Kaldır"
        case reset = "Uygulamayı Sıfırla"
    }

    @ObservedObject var model: UninstallerModel
    @ViewState private var filter: Filter = .user
    @ViewState private var mode: ActionMode = .uninstall
    @ViewState private var confirmAction = false

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
                rightInspectorPane
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if model.apps.isEmpty { await model.load() }
        }
        .alert(confirmDialogTitle, isPresented: $confirmAction) {
            Button("Vazgeç", role: .cancel) {}
            Button(confirmButtonTitle, role: .destructive) {
                executeConfirmedAction()
            }
        } message: {
            Text(confirmDialogMessage)
        }
    }

    // MARK: - Onay Penceresi Metinleri

    private var isBatchMode: Bool { model.checkedApps.count >= 2 }

    private var confirmDialogTitle: String {
        if isBatchMode {
            return "\(model.checkedApps.count) Uygulama Kökten Yok Edilsin mi?"
        }
        let name = model.activeTargetApps.first?.name ?? model.selectedApp?.name ?? "Uygulama"
        return mode == .uninstall ? "\(name) Kökten Yok Edilsin mi?" : "\(name) Verileri Sıfırlansın mı?"
    }

    private var confirmButtonTitle: String {
        if !model.permanentDelete { return "Çöp Kutusu'na Taşı" }
        if isBatchMode { return "Evet, \(model.checkedApps.count) Uygulamayı Yok Et" }
        return mode == .uninstall ? "Evet, Kalıntısız Yok Et" : "Evet, Sıfırla"
    }

    private var confirmDialogMessage: String {
        if isBatchMode {
            let names = model.checkedApps.prefix(5).map(\.name).joined(separator: ", ")
            let suffix = model.checkedApps.count > 5 ? " ve diğerleri" : ""
            return "\(names)\(suffix) (\(model.batchTotalSize.formattedBytes)), arka plan servisleri ve Oturum Açma Öğeleri kayıtlarıyla birlikte kalıcı olarak silinecek."
        }
        let name = model.activeTargetApps.first?.name ?? model.selectedApp?.name ?? "Uygulama"
        return "\(name) ile ilişkili tüm dosyalar, arka plan servisleri ve Oturum Açma Öğeleri izleri geri alınamaz şekilde silinecek."
    }

    private func executeConfirmedAction() {
        Task {
            if isBatchMode {
                await model.uninstallApps(model.checkedApps, permanently: model.permanentDelete)
            } else if mode == .uninstall {
                await model.uninstallApps(model.activeTargetApps, permanently: model.permanentDelete)
            } else if let app = model.selectedApp {
                await model.resetSelectedLeftovers(for: app, permanently: model.permanentDelete)
            }
        }
    }

    // MARK: - Üst Çubuk

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Text("Uygulama Kaldırıcı")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if !model.checkedApps.isEmpty {
                            HStack(spacing: 6) {
                                Text("\(model.checkedApps.count) seçili · \(model.batchTotalSize.formattedBytes)")
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Button {
                                    model.clearSelection()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                                .buttonStyle(.plain)
                                .help("Çoklu seçimi temizle")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(colors[0].opacity(0.45)))
                        }
                    }
                    Text("Kutucukları işaretleyerek tek veya birden fazla uygulamayı zerre kalıntı bırakmadan yok edin")
                        .font(.system(size: 12))
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
                .frame(width: 215)
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
                    Text("Kökten Kalıcı Sil (Çöp Kutusu'nda bekletme)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(model.permanentDelete ? Theme.successGreen : Theme.subtleText)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Sol Uygulama Listesi (Çoklu Seçim Kutucuklu!)

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
                            let isFocused = model.selectedID == app.id
                            let isChecked = model.checkedIDs.contains(app.id)

                            HStack(spacing: 10) {
                                if !app.isSIPProtected {
                                    RoundCheckbox(
                                        isOn: Binding(
                                            get: { isChecked },
                                            set: { _ in model.toggleCheck(app) }
                                        ),
                                        accent: colors[0]
                                    )
                                } else {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.faintText)
                                        .frame(width: 20)
                                }

                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .fixedSize(horizontal: false, vertical: true)
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
                                        .monospacedDigit()
                                } else {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(isChecked ? colors[0].opacity(0.28) : (isFocused ? Color.white.opacity(0.09) : Color.white.opacity(0.025)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(isChecked || isFocused ? colors[0].opacity(0.60) : .clear, lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if app.isSIPProtected { mode = .reset }
                                Task { await model.select(app) }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 330)
    }

    // MARK: - Sağ Panel: Çoklu Seçim Özeti VEYA Tekil Uygulama İnceleyici

    private var rightInspectorPane: some View {
        GlassCard(padding: 18) {
            if isBatchMode {
                batchSummaryView
            } else if let app = model.selectedApp {
                singleAppDetailView(app)
            } else {
                emptyPromptView
            }
        }
    }

    // MARK: - Çoklu Kaldırma Ekranı (2+ Uygulama Seçildiğinde)

    private var batchSummaryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.checkedApps.count) Uygulama Kökten Silinmeye Hazır")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Toplam Açılacak Alan: \(model.batchTotalSize.formattedBytes) · \(model.batchLeftoverCount) ek sistem kalıntısı dahil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors[0])
                }
                Spacer()
                Button("Seçimi Temizle") {
                    model.clearSelection()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.subtleText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Divider().overlay(Color.white.opacity(0.10))

            Text("Seçili tüm uygulamaların ana paketleri, ~/Library ve /Library verileri, arka plan servisleri ve Oturum Açma Öğeleri kayıtları tek seferde yok edilecek:")
                .font(.system(size: 12))
                .foregroundStyle(Theme.subtleText)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.checkedApps) { app in
                        let appLefts = model.leftovers(for: app.id)
                        let isScanning = model.scanningAppIDs.contains(app.id)
                        let totalForApp = (app.size ?? 0) + model.leftoversSelectedSize(for: app.id)

                        HStack(spacing: 12) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 38, height: 38)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(.white)
                                if isScanning {
                                    Text("Sistem kalıntıları taranıyor…")
                                        .font(.system(size: 11))
                                        .foregroundStyle(colors[0])
                                } else {
                                    Text("Uygulama + \(appLefts.filter(\.selected).count) kalıntı noktası")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.subtleText)
                                }
                            }
                            Spacer()

                            Text(totalForApp.formattedBytes)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()

                            Button {
                                model.toggleCheck(app)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.faintText)
                            }
                            .buttonStyle(.plain)
                            .help("Bu uygulamayı listeden çıkar")
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.045)))
                    }
                }
            }

            HStack {
                Spacer()
                OrbActionButton(
                    title: "Tümünü\nYok Et",
                    colors: model.permanentDelete ? [Color.red, Color.pink, colors[2]] : colors,
                    isBusy: model.working,
                    isDisabled: !model.scanningAppIDs.isEmpty
                ) {
                    if model.permanentDelete {
                        confirmAction = true
                    } else {
                        executeConfirmedAction()
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Tekil Uygulama İnceleyici

    private func singleAppDetailView(_ app: AppInfo) -> some View {
        let appLeftovers = model.leftovers(for: app.id)
        let finding = model.scanningAppIDs.contains(app.id)
        let selectedLeftSize = model.leftoversSelectedSize(for: app.id)

        return VStack(alignment: .leading, spacing: 12) {
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
                        Text("Toplam Boyut: \(((app.size ?? 0) + selectedLeftSize).formattedBytes) (\(appLeftovers.count) kalıntı noktası bulundu)")
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
                 ? "Ana paket, tüm gizli klasörler, arka plan servisleri ve Oturum Açma Öğeleri kaydı tamamen yok edilir:"
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

                    if finding {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("28 sistem ve kullanıcı noktasında kalıntılar taranıyor…")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.subtleText)
                        }
                        .padding(.top, 16)
                    } else if appLeftovers.isEmpty {
                        Text("Ek kalıntı dosya veya arka plan servisi bulunamadı.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.faintText)
                            .padding(.top, 16)
                    } else {
                        ForEach(Array(appLeftovers.enumerated()), id: \.element.id) { idx, item in
                            HStack(spacing: 10) {
                                RoundCheckbox(
                                    isOn: Binding(
                                        get: { item.selected },
                                        set: { _ in model.toggleLeftover(appID: app.id, index: idx) }
                                    ),
                                    accent: colors[0]
                                )
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
                    title: mode == .uninstall ? (model.permanentDelete ? "Yok Et" : "Kaldır") : "Sıfırla",
                    colors: (mode == .uninstall && model.permanentDelete) ? [Color.red, Color.pink, colors[2]] : colors,
                    isBusy: model.working,
                    isDisabled: finding || (mode == .reset && selectedLeftSize == 0) || (mode == .uninstall && app.isSIPProtected)
                ) {
                    if model.permanentDelete {
                        confirmAction = true
                    } else {
                        executeConfirmedAction()
                    }
                }
                Spacer()
            }
        }
    }

    private var emptyPromptView: some View {
        VStack(spacing: 16) {
            HeroMedallion(symbol: NavModule.uninstaller.heroSymbol, colors: colors, size: 152)
            Text("Tek veya Çoklu Uygulama Seçin")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Soldaki kutucukları işaretleyerek birden fazla uygulamayı aynı anda kökten silebilir veya bir uygulamaya tıklayarak 28 sistem noktasındaki tüm kalıntılarını inceleyebilirsiniz.")
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
