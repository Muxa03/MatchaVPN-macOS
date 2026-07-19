import SwiftUI
import AppKit

struct KeyView: View {
    @ObservedObject var sub: SubscriptionStore
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.openURL) private var openURL

    @State private var key = ""
    @State private var connecting = false

    private var botURL: URL { URL(string: "https://t.me/MatchaVPN_bot")! }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 22)
            Spacer(minLength: 0)

            // Лого-венчик
            WhiskIcon(color: .mLime, size: 76)
                .padding(.bottom, 18)

            (Text("MAT").foregroundColor(.mCream) + Text("CHA").foregroundColor(.mLime))
                .font(.system(size: 42, weight: .black, design: .rounded))

            Text("VPN, который для DPI\nне выглядит как VPN")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.mCream.opacity(0.6))
                .padding(.top, 8)
                .padding(.bottom, 30)

            // Поле ключа
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("Ключ доступа")
                    .foregroundColor(.mCream.opacity(0.7))
                HStack(spacing: 8) {
                    TextField("tg-…", text: $key)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.mCream)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.22)))
                        .overlay(RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(Color.mCream.opacity(0.14), lineWidth: 1))
                        .onSubmit(connect)

                    Button {
                        if let s = NSPasteboard.general.string(forType: .string) { key = s }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.mTeal)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 13).fill(Color.mCream))
                    }
                    .buttonStyle(HoverScaleStyle())
                    .help("Вставить из буфера обмена")
                }

                if let err = sub.lastError {
                    Text(err).font(.system(size: 11, weight: .semibold)).foregroundColor(.mLime)
                }
            }
            .padding(.horizontal, 4)

            // Подключить
            Button(action: connect) {
                Text(connecting ? "ПОДКЛЮЧАЮ…" : "ПОДКЛЮЧИТЬ")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundColor(.mTeal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.mLime))
                    .opacity(key.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
            .buttonStyle(HoverScaleStyle())
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
            .padding(.top, 16)

            // Получить ключ
            Button { openURL(botURL) } label: {
                Text("Нет ключа? Получить в Telegram →")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.mCream.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            Spacer(minLength: 0)
            Text("Регистрация и личные данные не нужны")
                .font(.mono(9)).foregroundColor(.mCream.opacity(0.4))
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connect() {
        let t = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        connecting = true
        sub.setToken(t)
        // setToken сам дёргает refreshCatalog; как только токен проставится, RootView переключит экран.
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            connecting = false
        }
    }
}
