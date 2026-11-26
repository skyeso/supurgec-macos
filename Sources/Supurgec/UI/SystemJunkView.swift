import SwiftUI
import AppKit

struct SystemJunkView: View {
    @ObservedObject var scanner: JunkScanner
    @ViewState private var showingDetails = false
    @ViewState private var selectedCategoryID: String?
    @ViewState private var searchText = ""
    @ViewState private var confirmTrashClean = false

    private let colors = NavModule.systemJunk.accentColors

    var body: some View {
        VStack(spacing: 0) {
            switch scanner.phase {
            case .idle:
                Spacer(minLength: 12)
                introView
                Spacer(minLength: 12)
                OrbActionButton(title: "Tara", colors: colors) {
                    showingDetails = false
                    Task { await scanner.scan() }
                }
                .padding(.bottom, 18)

            case .scanning, .cleaning:
                Spacer()
                progressView
                Spacer()
                OrbActionButton(title: scanner.phase == .scanning ? "Taranıyor" : "Temizleniyor", colors: colors, isBusy: true) {}
                    .padding(.bottom, 18)

            case .results:
                if showingDetails {
                    detailsSplitView
                } else {
                    Spacer(minLength: 10)
                    summaryResultsView
                    Spacer(minLength: 10)
                }
                resultsBottomBar
                    .padding(.horizontal, 30)
                    .padding(.bottom, 16)

            case .done:
                Spacer()
                doneView
                Spacer()
                OrbActionButton(title: "Yeniden\nTara", colors: colors) {
                    showingDetails = false
                    Task { await scanner.scan() }
                }
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Karşılama

    private var introView: some View {
        HStack(spacing: 38) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sistem Çöpü")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(NavModule.systemJunk.subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.subtleText)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 15) {
                    FeatureRow(
                        icon: "bolt.circle.fill",
                        color: colors[0],
                        title: "Sistemi ve Uygulamaları Rahatlatır",
                        subtitle: "Şişmiş önbellekleri ve bozuk uygulama durum dosyalarını temizler."
                    )
                    FeatureRow(
                        icon: "internaldrive.fill",
                        color: colors[1],
                        title: "Gigabaytlarca Disk Alanı Açar",
                        subtitle: "Xcode DerivedData, npm/pip/Gradle önbellekleri ve günlükleri yakalar."
                    )
                    FeatureRow(
                        icon: "checkmark.shield.fill",
                        color: colors[2],
                        title: "Akıllı Güvenlik Seçimi",
                        subtitle: "Kişisel belgelerinize dokunmaz; yalnızca yeniden oluşturulabilir verileri seçer."
                    )
                }
            }
            .frame(maxWidth: 440)
            .layoutPriority(1)

            HeroMedallion(symbol: NavModule.systemJunk.heroSymbol, colors: colors, size: 196)
        }
        .padding(.horizontal, 34)
    }

    // MARK: - Tarama / Temizleme İlerlemesi

    private var progressView: some View {
        VStack(spacing: 20) {
            HeroMedallion(symbol: NavModule.systemJunk.heroSymbol, colors: colors, scanning: true, size: 184)

            VStack(spacing: 8) {
                Text(scanner.phase == .scanning ? "Sistem Çöpü Taranıyor…" : "Seçili Öğeler Temizleniyor…")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if scanner.phase == .scanning && scanner.totalSize > 0 {
                    Text("\(scanner.totalSize.formattedBytes) bulundu")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors[0])
                }

                Text(scanner.currentPath.isEmpty ? "Hazırlanıyor…" : scanner.currentPath)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.faintText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 540)
            }
        }
    }

    // MARK: - Sonuç Özeti

    private var summaryResultsView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Tarama Tamamlandı")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors[0])
                    .textCase(.uppercase)
                    .tracking(1.2)

                Text(scanner.selectedSize.formattedBytes)
                    .font(.system(size: 50, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, Color.white.opacity(0.84)], startPoint: .top, endPoint: .bottom)
                    )

                Text("Otomatik seçilen güvenli temizlik boyutu (Toplam bulunan: \(scanner.totalSize.formattedBytes))")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.subtleText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 12)], spacing: 12) {
                ForEach(scanner.categories) { cat in
                    Button {
                        selectedCategoryID = cat.id
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            showingDetails = true
                        }
                    } label: {
                        GlassCard(padding: 13) {
                            HStack(spacing: 11) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(colors[0].opacity(0.20))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(colors[0])
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(cat.items.count) öğe · \(cat.totalSize.formattedBytes)")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.subtleText)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: cat.anySelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(cat.anySelected ? colors[0] : Theme.faintText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 780)

            Button {
                if selectedCategoryID == nil { selectedCategoryID = scanner.categories.first?.id }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    showingDetails = true
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Ayrıntıları İncele")
                    Image(systemName: "slider.horizontal.3")
                }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.11))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Ayrıntılı İnceleme

    private var detailsSplitView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        showingDetails = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                        Text("Özete Dön")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.faintText)
                    TextField("Dosya veya klasör filtrele…", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .font(.system(size: 12.5))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faintText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(width: 240)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )
            }
            .padding(.top, 8)

            HStack(spacing: 14) {
                GlassCard(padding: 10) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(scanner.categories) { cat in
                                let isCurrent = (selectedCategoryID ?? scanner.categories.first?.id) == cat.id
                                HStack(spacing: 10) {
                                    RoundCheckbox(
                                        isOn: Binding(
                                            get: { cat.anySelected },
                                            set: { scanner.setCategory(cat.id, selected: $0) }
                                        ),
                                        accent: colors[0]
                                    )

                                    Image(systemName: cat.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(isCurrent ? .white : colors[0])
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("Seçili: \(cat.selectedSize.formattedBytes)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.subtleText)
                                    }
                                    Spacer(minLength: 4)
                                    Text(cat.totalSize.formattedBytes)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.84))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(isCurrent ? colors[0].opacity(0.24) : Color.white.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .strokeBorder(isCurrent ? colors[0].opacity(0.55) : .clear, lineWidth: 1)
                                        )
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { selectedCategoryID = cat.id }
                            }
                        }
                    }
                }
                .frame(width: 290)

                GlassCard(padding: 16) {
                    if let catIdx = activeCategoryIndex {
                        let cat = scanner.categories[catIdx]
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cat.title)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text(cat.subtitle)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Theme.subtleText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Button(cat.allSelected ? "Tümünü Kaldır" : "Tümünü Seç") {
                                    scanner.setCategory(cat.id, selected: !cat.allSelected)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(colors[0])
                                .fixedSize()
                            }

                            Divider().overlay(Color.white.opacity(0.10))

                            ScrollView {
                                LazyVStack(spacing: 5) {
                                    ForEach(Array(cat.items.enumerated()), id: \.element.id) { itemIdx, item in
                                        if searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText) {
                                            HStack(spacing: 10) {
                                                RoundCheckbox(
                                                    isOn: $scanner.categories[catIdx].items[itemIdx].selected,
                                                    accent: colors[0]
                                                )
                                                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                                    .resizable()
                                                    .frame(width: 22, height: 22)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.name)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundStyle(.white)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                    Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: FileUtils.home.path, with: "~"))
                                                        .font(.system(size: 10.5))
                                                        .foregroundStyle(Theme.faintText)
                                                        .truncationMode(.middle)
                                                        .lineLimit(1)
                                                }
                                                Spacer(minLength: 4)
                                                RevealInFinderButton(url: item.url)
                                                Text(item.size.formattedBytes)
                                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.88))
                                                    .frame(minWidth: 72, alignment: .trailing)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.white.opacity(0.03))
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Temizlenecek öğe bulunamadı.")
                            .foregroundStyle(Theme.subtleText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 8)
    }

    private var activeCategoryIndex: Int? {
        if let id = selectedCategoryID, let idx = scanner.categories.firstIndex(where: { $0.id == id }) {
            return idx
        }
        return scanner.categories.indices.first
    }

    // MARK: - Sonuç Alt Çubuğu

    private var resultsBottomBar: some View {
        ZStack {
            HStack {
                Button {
                    showingDetails = false
                    scanner.reset()
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

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Seçilen Boyut")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faintText)
                    Text(scanner.selectedSize.formattedBytes)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }

            OrbActionButton(title: "Temizle", colors: colors, isDisabled: scanner.selectedSize == 0) {
                let trashSelected = scanner.categories.first(where: { $0.id == "trash" })?.anySelected == true
                if trashSelected {
                    confirmTrashClean = true
                } else {
                    Task { await scanner.clean() }
                }
            }
        }
        .alert("Çöp Kutusu Kalıcı Olarak Boşaltılsın mı?", isPresented: $confirmTrashClean) {
            Button("Vazgeç", role: .cancel) {}
            Button("Evet, Kalıcı Olarak Temizle", role: .destructive) {
                Task { await scanner.clean() }
            }
        } message: {
            Text("Seçili öğeler arasında Çöp Kutusu da bulunuyor. Bu işlem geri alınamaz.")
        }
    }

    // MARK: - Bitti

    private var doneView: some View {
        VStack(spacing: 18) {
            HeroMedallion(
                symbol: "sparkles",
                colors: [Theme.successGreen, Color(red: 0.20, green: 0.74, blue: 0.96), colors[2]],
                size: 184
            )
            Text("\(scanner.cleanedBytes.formattedBytes) Temizlendi!")
                .font(.system(size: 33, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Gereksiz önbellek ve günlük dosyaları diskinizden güvenle kaldırıldı.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.subtleText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
