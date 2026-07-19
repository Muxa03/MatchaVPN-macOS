import SwiftUI

struct SettingsView: View {
    @ObservedObject var sub: SubscriptionStore
    @ObservedObject var tunnel: TunnelManager
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var sysext = SystemExtensionManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Настройки")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.mCream)
                Spacer()
                CloseButton { dismiss() }
            }
            .padding(20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    themeSection
                    sysextSection
                    aboutSection
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 430, height: 600)
        .background(Color.mTeal.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Тема
    private var themeSection: some View {
        section("Тема") {
            VStack(spacing: 10) {
                ForEach(Palette.all) { p in
                    Button {
                        withAnimation(.spring(response: 0.3)) { theme.select(p) }
                    } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                swatch(p.teal); swatch(p.lime); swatch(p.cream)
                            }
                            Text(p.name)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.mCream)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Spacer()
                            if p.id == theme.palette.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.mLime)
                            }
                        }
                        .padding(13)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.mTealD))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(p.id == theme.palette.id ? Color.mLime : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(HoverScaleStyle())
                }
            }
        }
    }

    private func swatch(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Color.mCream.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Системное расширение
    private var sysextSection: some View {
        section("Системное расширение") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Circle().fill(sysextColor).frame(width: 9, height: 9)
                    Text(sysextText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mCream)
                    Spacer()
                }
                Text("Туннель — системное расширение macOS. Один раз разрешите его в «Системные настройки → Конфиденциальность и безопасность».")
                    .font(.system(size: 11))
                    .foregroundColor(.mCream.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if sysext.state != .active {
                    Button("Активировать расширение") { sysext.activate() }
                        .buttonStyle(HoverScaleStyle())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.mTeal)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.mLime))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.mTealD))
        }
    }

    private var sysextColor: Color {
        switch sysext.state {
        case .active: return .mLime
        case .failed: return .red
        default: return .mCream.opacity(0.5)
        }
    }
    private var sysextText: String {
        switch sysext.state {
        case .unknown:      return "не активировано"
        case .installing:   return "устанавливается…"
        case .needsApproval:return "ждёт разрешения в Настройках"
        case .active:       return "активно"
        case .failed(let e):return "ошибка: \(e)"
        }
    }

    // MARK: - О приложении
    private var aboutSection: some View {
        section("О приложении") {
            VStack(spacing: 0) {
                linkRow("Сайт", "matchavpn.space", "https://matchavpn.space")
                divider
                linkRow("Поддержка", "@help_matcha", "https://t.me/help_matcha")
                divider
                linkRow("Исходный код", "GitHub", "https://github.com/Muxa03/MatchaVPN-Desktop")
            }
            .padding(.horizontal, 15).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.mTealD))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.mCream.opacity(0.08)).frame(height: 1)
    }

    private func linkRow(_ title: String, _ value: String, _ url: String) -> some View {
        Button { if let u = URL(string: url) { openURL(u) } } label: {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.mCream)
                Spacer()
                Text(value).font(.mono(11)).foregroundColor(.mLime)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                    .foregroundColor(.mCream.opacity(0.4))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Выход
    private var signOutButton: some View {
        Button {
            if tunnel.isActive { tunnel.toggle(config: nil, excludedRoutes: []) }
            sub.signOut()
            dismiss()
        } label: {
            Text("Отвязать ключ")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.mCream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.mTaro))
        }
        .buttonStyle(HoverScaleStyle())
    }

    // MARK: - Секция
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(title).foregroundColor(.mCream.opacity(0.6))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
