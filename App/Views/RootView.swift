import SwiftUI

/// Корень окна: если ключа нет — экран ввода ключа, иначе — главный экран подключения.
struct RootView: View {
    @ObservedObject var sub: SubscriptionStore
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            Color.mTeal.ignoresSafeArea()

            // Огромная бледная «M» на фоне — фирменный акцент.
            Text("M")
                .font(.system(size: 300, weight: .black, design: .rounded))
                .foregroundColor(Color.mCream.opacity(0.05))
                .rotationEffect(.degrees(8))
                .offset(x: 150, y: -170)
                .allowsHitTesting(false)

            if sub.token == nil {
                KeyView(sub: sub)
                    .transition(.asymmetric(insertion: .opacity,
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                ConnectView(sub: sub)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: sub.token)
    }
}
