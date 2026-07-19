import SwiftUI

struct ServersView: View {
    @ObservedObject var sub: SubscriptionStore
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Локация")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.mCream)
                Spacer()
                CloseButton { dismiss() }
            }
            .padding(20)

            if sub.servers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView().tint(.mLime)
                    Text("Загружаю серверы…")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.mCream.opacity(0.6))
                    Button("Обновить") { Task { await sub.refreshCatalog() } }
                        .buttonStyle(.plain)
                        .foregroundColor(.mLime)
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(sub.servers) { server in
                            row(server)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 430, height: 560)
        .background(Color.mTeal.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { if sub.servers.isEmpty { await sub.refreshCatalog() } }
    }

    private func row(_ server: CatalogServer) -> some View {
        let selected = server.id == (sub.selectedServer?.id)
        return Button {
            withAnimation(.spring(response: 0.3)) { sub.selectServer(server.id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { dismiss() }
        } label: {
            HStack(spacing: 13) {
                Text(server.flag).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.country)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(selected ? .mTeal : .mCream)
                    Text(server.city)
                        .font(.mono(10))
                        .foregroundColor((selected ? Color.mTeal : Color.mCream).opacity(0.6))
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.mTeal)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(selected ? Color.mLime : Color.mTealD))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.mCream.opacity(selected ? 0 : 0.1), lineWidth: 1.5))
        }
        .buttonStyle(HoverScaleStyle())
    }
}

struct CloseButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.mCream)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(HoverScaleStyle())
    }
}
