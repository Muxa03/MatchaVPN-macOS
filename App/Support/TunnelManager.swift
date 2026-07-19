import Foundation
import NetworkExtension
import AppKit

/// Управляет системным VPN-профилем через NETunnelProviderManager.
///
/// Без entitlement / в неподписанной dev-сборке `loadAllFromPreferences` бросает ошибку —
/// тогда работаем в превью-режиме (кнопка переключается «вхолостую»), чтобы можно было
/// смотреть и дорабатывать интерфейс. В подписанной сборке с активным системным
/// расширением поднимается реальный AmneziaWG-туннель.
@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var lastError: String?
    @Published private var previewConnected = false

    private(set) var usePreview = true
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    /// Активен ли VPN (реально или в превью).
    var isActive: Bool {
        if usePreview { return previewConnected }
        return status == .connected || status == .connecting || status == .reasserting
    }

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let session = note.object as? NEVPNConnection else { return }
            Task { @MainActor in
                // Реагируем только на СВОЙ туннель — чужой VPN не должен сбивать статус кнопки.
                if let mgr = self.manager, session !== mgr.connection { return }
                self.status = session.status
            }
        }
        // При возврате фокуса в приложение пересинкаем реальный статус (кнопка не «залипает»).
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.load() }
        }
        Task { await load() }
    }

    deinit {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first
            status = manager?.connection.status ?? .disconnected
            usePreview = false
        } catch {
            // Нет entitlement (неподписанная сборка) — показываем UI в превью-режиме.
            usePreview = true
        }
    }

    /// Переключить состояние по нажатию главной кнопки.
    func toggle(config: String?, excludedRoutes: [String]) {
        if usePreview { previewConnected.toggle(); return }
        if isActive {
            stop()
        } else if let config {
            Task { await start(config: config, excludedRoutes: excludedRoutes) }
        }
    }

    /// Переподключить с новым конфигом (смена региона на лету).
    func reconnect(config: String?, excludedRoutes: [String]) {
        if usePreview {
            Task {
                previewConnected = false
                try? await Task.sleep(nanoseconds: 400_000_000)
                previewConnected = true
            }
            return
        }
        Task {
            stop()
            try? await Task.sleep(nanoseconds: 600_000_000)
            if let config { await start(config: config, excludedRoutes: excludedRoutes) }
        }
    }

    /// Системное расширение загружается только из /Applications — иначе активация падает.
    var isInApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    func start(config: String, excludedRoutes: [String]) async {
        guard isInApplications else {
            lastError = "Переместите MatchaVPN в папку «Программы» и запустите оттуда — из других мест системное расширение не запускается."
            return
        }
        // Одобрение расширения асинхронно: активируем и выходим, экран покажет статус по se.state.
        let se = SystemExtensionManager.shared
        if se.state != .active {
            se.activate()
            return
        }
        lastError = nil
        do {
            let mgr = manager ?? NETunnelProviderManager()
            let split = !excludedRoutes.isEmpty
            let cfg = TunnelManager.ensureMTU(split ? TunnelManager.forceIPv4Full(config) : config)

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = AppIDs.tunnelBundleId
            proto.serverAddress = "MATCHA"
            var providerConf: [String: Any] = ["key": cfg]
            if split { providerConf["excludedRoutes"] = excludedRoutes }
            proto.providerConfiguration = providerConf
            proto.disconnectOnSleep = false

            mgr.protocolConfiguration = proto
            mgr.localizedDescription = "MatchaVPN"
            mgr.isEnabled = true
            mgr.isOnDemandEnabled = false
            mgr.onDemandRules = []

            try await mgr.saveToPreferences()
            try await mgr.loadFromPreferences()
            manager = mgr

            try (mgr.connection as? NETunnelProviderSession)?.startTunnel(options: nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        (manager?.connection as? NETunnelProviderSession)?.stopTunnel()
    }

    /// Реальные счётчики трафика туннеля (байты rx/tx) — запрос в расширение через app-message.
    func fetchStats() async -> (rx: UInt64, tx: UInt64)? {
        guard !usePreview, status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else { return nil }
        return await withCheckedContinuation { cont in
            do {
                try session.sendProviderMessage(Data("stats".utf8)) { reply in
                    guard let reply,
                          let obj = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] else {
                        cont.resume(returning: nil); return
                    }
                    let rx = (obj["rx"] as? NSNumber)?.uint64Value ?? 0
                    let tx = (obj["tx"] as? NSNumber)?.uint64Value ?? 0
                    cont.resume(returning: (rx, tx))
                }
            } catch {
                cont.resume(returning: nil)
            }
        }
    }

    /// В сплите гоним весь IPv4 в туннель (0.0.0.0/0), IPv6 остаётся напрямую.
    static func forceIPv4Full(_ config: String) -> String {
        var lines = config.components(separatedBy: "\n")
        var replaced = false
        for i in lines.indices where lines[i].trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("allowedips") {
            lines[i] = "AllowedIPs = 0.0.0.0/0"
            replaced = true
        }
        if !replaced,
           let peer = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "[peer]" }) {
            lines.insert("AllowedIPs = 0.0.0.0/0", at: peer + 1)
        }
        return lines.joined(separator: "\n")
    }

    /// Добавляет MTU в [Interface], если не задан — лечит «подключилось, но данные не идут».
    static func ensureMTU(_ config: String, mtu: Int = 1280) -> String {
        var lines = config.components(separatedBy: "\n")
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("mtu") }) {
            return config
        }
        if let iface = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "[interface]" }) {
            lines.insert("MTU = \(mtu)", at: iface + 1)
        }
        return lines.joined(separator: "\n")
    }
}
