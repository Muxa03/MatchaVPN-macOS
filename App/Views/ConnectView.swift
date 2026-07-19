import SwiftUI

struct ConnectView: View {
    @ObservedObject var sub: SubscriptionStore
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var tunnel = TunnelManager()
    @StateObject private var traffic = TrafficMonitor()
    @ObservedObject private var sysext = SystemExtensionManager.shared

    @State private var showServers = false
    @State private var showSettings = false
    @State private var connectedSince: Date?
    @State private var gearHover = false
    @State private var pendingConnect = false   // достартовать туннель после одобрения расширения

    private var isConnected: Bool { tunnel.isActive }

    var body: some View {
        VStack(spacing: 16) {
            Color.clear.frame(height: 22)          // полоса под «светофор» окна (перетаскивание)
            topBar
            hero
            serverCard
            trafficCard
            if !tunnel.isInApplications {
                banner("Переместите MatchaVPN в «Программы» (перетащите в окне установки) и запустите оттуда — иначе защита не включится.")
            } else if sysext.state == .installing || sysext.state == .needsApproval {
                approvalBanner
            } else if let e = sysextFailure {
                banner("Не удалось включить защиту: \(e)")
            } else if let err = tunnel.lastError {
                banner(err)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showServers) { ServersView(sub: sub) }
        .sheet(isPresented: $showSettings) { SettingsView(sub: sub, tunnel: tunnel) }
        .task { await sub.refreshCatalog() }
        .onAppear {
            if isConnected { beginSession() }
            traffic.start(tunnel)
        }
        .onDisappear { traffic.stop() }
        .onChange(of: isConnected) { on in
            if on { beginSession() } else { connectedSince = nil }
        }
        .onChange(of: sub.selectedServerID) { _ in reconnectIfActive() }
        .onChange(of: sysext.state) { st in
            // расширение только что одобрили — доводим включение до конца автоматически
            if st == .active && pendingConnect { pendingConnect = false; onPower() }
        }
    }

    private var sysextFailure: String? {
        if case .failed(let e) = sysext.state { return e }
        return nil
    }

    // MARK: - Верхняя панель
    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                (Text("MAT").foregroundColor(.mCream) + Text("CHA").foregroundColor(.mLime))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Text("macos 1.0.3")
                    .font(.mono(9)).tracking(2)
                    .foregroundColor(.mCream.opacity(0.5))
            }
            Spacer()
            Button { showSettings = true } label: {
                VStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(Color.mTeal).frame(width: 16, height: 3)
                    }
                }
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.mLime))
                .scaleEffect(gearHover ? 1.06 : 1)
            }
            .buttonStyle(.plain)
            .onHover { h in withAnimation(.spring(response: 0.25)) { gearHover = h } }
        }
    }

    // MARK: - Hero
    private var hero: some View {
        Card(style: .teal, padding: 22) {
            VStack(spacing: 4) {
                HStack {
                    StatusPill(active: isConnected)
                    Spacer()
                    uptime
                }

                Text("stay green")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .italic()
                    .foregroundColor(.mLime)
                    .rotationEffect(.degrees(-4))
                    .padding(.top, 10)

                ZStack(alignment: .topTrailing) {
                    PowerButton(isOn: isConnected, action: onPower)
                    VStack(spacing: 0) {
                        Text("жми")
                            .font(.system(size: 17, weight: .bold, design: .rounded)).italic()
                            .foregroundColor(isConnected ? .mCream : .mLime)
                        ArrowShape()
                            .stroke(isConnected ? Color.mCream : Color.mLime,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 50, height: 34)
                    }
                    .rotationEffect(.degrees(-6))
                    .offset(x: 4, y: 40)
                    .allowsHitTesting(false)
                }
                .padding(.top, 2)

                headline
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var headline: Text {
        isConnected
            ? Text("ТЫ ").foregroundColor(.mLime) + Text("ПОД ЗАЩИТОЙ").foregroundColor(.mCream)
            : Text("ЗАЩИТА ").foregroundColor(.mCream) + Text("ВЫКЛ").foregroundColor(.mLime)
    }

    // MARK: - Аптайм
    private var uptime: some View {
        Group {
            if isConnected, let since = connectedSince {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(elapsed(since, ctx.date)).monospacedDigit()
                }
            } else {
                Text("--:--:--")
            }
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundColor(.mCream)
    }

    // MARK: - Карточка сервера
    private var serverCard: some View {
        Button { showServers = true } label: {
            Card(style: .cream) {
                HStack(spacing: 13) {
                    Text(sub.selectedServer?.flag ?? "🌐").font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 3) {
                        MonoLabel("Локация")
                        Text(sub.selectedServer?.country ?? "выбери страну")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(sub.selectedServer.map { "\($0.city) · \(sub.selectedProto.chip)" } ?? "нажми, чтобы выбрать")
                            .font(.mono(9.5)).opacity(0.6)
                    }
                    Spacer()
                    Text("СМЕНИТЬ")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.mCream)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.mTeal))
                }
            }
        }
        .buttonStyle(HoverScaleStyle())
    }

    // MARK: - Трафик (реальные счётчики туннеля)
    private var trafficCard: some View {
        Card(style: .teal) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel("Трафик")
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        speedStat("arrow.down", TrafficMonitor.rate(traffic.downBps), accent: true)
                        speedStat("arrow.up", TrafficMonitor.rate(traffic.upBps), accent: false)
                    }
                    Text("сессия · ↓ \(TrafficMonitor.bytes(traffic.rxTotal))  ↑ \(TrafficMonitor.bytes(traffic.txTotal))")
                        .font(.mono(9.5)).foregroundColor(.mCream.opacity(0.45))
                }
                Spacer()
                Sparkline(values: traffic.spark, color: .mLime)
                    .frame(width: 128, height: 44)
            }
        }
    }

    private func speedStat(_ arrow: String, _ value: String, accent: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: arrow).font(.system(size: 11, weight: .black))
                .foregroundColor(accent ? .mLime : .mCream.opacity(0.65))
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.mCream)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    // MARK: - Баннер одобрения системного расширения
    private var approvalBanner: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(Color.mLime).frame(width: 7, height: 7).padding(.top, 5)
                Text(sysext.state == .installing
                     ? "Устанавливаю защиту…"
                     : "Последний шаг: откройте настройки и нажмите «Разрешить» рядом с MatchaVPN.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.mCream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sysext.state == .needsApproval {
                Button { sysext.openSecuritySettings() } label: {
                    Text("Открыть настройки безопасности")
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .foregroundColor(.mTeal)
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .background(Capsule().fill(Color.mLime))
                }
                .buttonStyle(HoverScaleStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.mTaro))
    }

    // MARK: - Баннер ошибки / подсказки
    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color.mLime).frame(width: 7, height: 7).padding(.top, 5)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.mCream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.mTaro))
    }

    private var footer: some View {
        Text("MatchaVPN · обфусцированный WireGuard")
            .font(.mono(9))
            .foregroundColor(.mCream.opacity(0.4))
    }

    // MARK: - Действия
    private func onPower() {
        // Выключение — мгновенно, без сетевых запросов (иначе при мёртвом туннеле off виснет).
        if tunnel.isActive {
            tunnel.toggle(config: nil, excludedRoutes: [])
            return
        }
        // Если нужно сперва активировать системное расширение — запомним намерение,
        // чтобы после одобрения включиться автоматически (см. onChange sysext.state).
        if !tunnel.usePreview, tunnel.isInApplications, SystemExtensionManager.shared.state != .active {
            pendingConnect = true
        }
        Task {
            let cfg = tunnel.usePreview ? nil : await sub.resolveSelected()
            tunnel.toggle(config: cfg, excludedRoutes: [])
        }
    }

    private func reconnectIfActive() {
        guard tunnel.isActive else { return }
        Task {
            let cfg = tunnel.usePreview ? nil : await sub.resolveSelected()
            tunnel.reconnect(config: cfg, excludedRoutes: [])
        }
    }

    private func beginSession() {
        if connectedSince == nil { connectedSince = Date() }
    }

    private func elapsed(_ start: Date, _ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

/// Кнопка, слегка увеличивающаяся при наведении/нажатии (десктопная тактильность).
/// Состояние hover держим во вложенной View — в самом ButtonStyle @State не обновляется.
struct HoverScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }
    struct HoverBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : (hover ? 1.012 : 1))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
                .animation(.spring(response: 0.2), value: configuration.isPressed)
                .onHover { hover = $0 }
        }
    }
}
