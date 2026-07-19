import SwiftUI

@main
struct MatchaLabApp: App {
    @StateObject private var sub = SubscriptionStore()
    @ObservedObject private var theme = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            RootView(sub: sub)
                .frame(width: 460, height: 760)
                .background(Color.mTeal.ignoresSafeArea())
                .preferredColorScheme(.dark)
                .environmentObject(theme)
        }
        .windowStyle(.hiddenTitleBar)               // единый тёмный корпус, без серой шапки
        .windowResizability(.contentSize)           // фиксированный размер окна
        .defaultSize(width: 460, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}     // убрать «Новое окно» — приложение одно-оконное
        }
    }
}
