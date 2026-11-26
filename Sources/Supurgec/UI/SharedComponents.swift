import SwiftUI

/// CleanMyMac tarzı alt merkez yuvarlak aksiyon butonu (boştayken sıfır GPU tüketir).
struct OrbActionButton: View {
    let title: String
    var colors: [Color]
    var isBusy: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @ViewState private var spin = false
    @ViewState private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [colors.first!.opacity(hovered ? 0.38 : 0.22), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 58
                        )
                    )
                    .frame(width: 112, height: 112)

                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: colors + [colors.first!],
                            center: .center
                        ),
                        lineWidth: isBusy ? 3.0 : 1.6
                    )
                    .frame(width: 92, height: 92)
                    .rotationEffect(.degrees(isBusy && spin ? 360 : 0))
                    .opacity(isDisabled ? 0.3 : 0.85)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDisabled
                                ? [Color(red: 0.18, green: 0.19, blue: 0.26), Color(red: 0.13, green: 0.14, blue: 0.20)]
                                : colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.32), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .padding(2)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: colors.first!.opacity(isDisabled ? 0 : 0.42), radius: hovered ? 20 : 12, y: 5)
                    .scaleEffect(hovered && !isDisabled ? 1.05 : 1.0)

                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.regular)
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isBusy)
        .onHover { h in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { hovered = h }
        }
        .onChange(of: isBusy) { _, busy in
            if busy {
                spin = false
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    spin = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { spin = false }
            }
        }
        .onAppear {
            if isBusy {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    spin = true
                }
            }
        }
    }
}

/// Gerçek boyutlandırılabilir 3B ikon rozeti (yalnızca tarama sırasında döner, boştayken sıfır GPU harcar).
struct HeroMedallion: View {
    let symbol: String
    let colors: [Color]
    var scanning: Bool = false
    var size: CGFloat = 196

    @ViewState private var orbit = false

    var body: some View {
        let plate = size * 0.54
        let corner = plate * 0.29
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[0].opacity(0.32), colors[1].opacity(0.14), .clear],
                        center: .center,
                        startRadius: size * 0.06,
                        endRadius: size * 0.50
                    )
                )
                .frame(width: size, height: size)

            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [.clear, colors[0].opacity(0.65), colors.last!.opacity(0.65), .clear],
                        center: .center
                    ),
                    lineWidth: scanning ? 2.4 : 1.2
                )
                .frame(width: size * 0.75, height: size * 0.75)
                .rotationEffect(.degrees(scanning && orbit ? 360 : 0))

            Circle()
                .strokeBorder(Color.white.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [5, 7]))
                .frame(width: size * 0.88, height: size * 0.88)

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [colors[0], colors[1], colors.last!],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: plate, height: plate)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.36), .clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.38), lineWidth: 1.2)
                )
                .shadow(color: colors[0].opacity(0.40), radius: 20, y: 9)

            Image(systemName: symbol)
                .font(.system(size: plate * 0.42, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color.white.opacity(0.86)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .frame(width: size, height: size)
        .onChange(of: scanning) { _, active in
            if active {
                orbit = false
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    orbit = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { orbit = false }
            }
        }
        .onAppear {
            if scanning {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    orbit = true
                }
            }
        }
    }
}

/// Saydamlığı Azalt ayarına uyumlu kart kapsayıcısı.
struct GlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(reduceTransparency ? Theme.cardSolid : Theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.cardStroke, lineWidth: 1)
                    )
            )
    }
}

/// Modül özellik satırı (karşılama ekranlarında tam metin sarma destekli).
struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.20))
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(color.opacity(0.38), lineWidth: 1)
                    )
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.subtleText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Özel onay kutusu (CleanMyMac yuvarlak tik stili).
struct RoundCheckbox: View {
    @Binding var isOn: Bool
    var accent: Color = Color(red: 0.25, green: 0.78, blue: 1.0)

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(isOn ? accent : Color.white.opacity(0.09))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .strokeBorder(isOn ? accent : Color.white.opacity(0.32), lineWidth: 1.3)
                    )
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Dosyayı Finder'da gösterme ikonu.
struct RevealInFinderButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.48))
        }
        .buttonStyle(.plain)
        .help("Finder'da Göster")
    }
}
