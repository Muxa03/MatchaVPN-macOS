import NetworkExtension
import WireGuardKit
import Foundation
import Network
import os

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.matcha.lab.tunnel", category: "net")

    private var tunnelConfig: TunnelConfiguration?
    private var excludedRoutes: [NEIPv4Route] = []   // «прямые» сети (РФ) — мимо туннеля
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.matcha.pathmonitor")
    private var currentInterface: NWInterface.InterfaceType?
    private var rebinding = false
    private var stopping = false
    private var focusMode = false                 // локальный контент-блокировщик (без удалённого сервера)

    private var watchdog: DispatchSourceTimer?
    private var lastTx: UInt64 = 0
    private var lastRx: UInt64 = 0
    private var deadTicks = 0
    private var staleTicks = 0                    // тактов подряд с протухшим рукопожатием
    private var watchdogPrimed = false
    private var lastRebindAt = Date.distantPast   // антипетля: не рестартим чаще раза в 20с

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { [weak self] _, message in
            guard let self else { return }
            os_log("%{public}s", log: self.log, type: .default, message)
        }
    }()

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        let providerConf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        // Режим фокуса: локальная блокировка отвлекающих сайтов на устройстве, без сервера.
        if providerConf?["mode"] as? String == "focus" {
            focusMode = true
            startFocus(domains: providerConf?["blockDomains"] as? [String] ?? [],
                       completionHandler: completionHandler)
            return
        }
        guard
            let proto = protocolConfiguration as? NETunnelProviderProtocol,
            let key = proto.providerConfiguration?["key"] as? String,
            let configuration = try? TunnelConfiguration(fromWgQuickConfig: key)
        else {
            completionHandler(TunnelError.badConfig)
            return
        }
        tunnelConfig = configuration
        if let excluded = proto.providerConfiguration?["excludedRoutes"] as? [String] {
            excludedRoutes = excluded.compactMap { PacketTunnelProvider.route(from: $0) }
        }
        adapter.start(tunnelConfiguration: configuration) { [weak self] error in
            guard let self else { completionHandler(error); return }
            if let error {
                os_log("AmneziaWG start error: %{public}@", log: self.log, type: .error, "\(error)")
            }
            completionHandler(error)
            if error == nil { self.beginPathMonitoring() }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        stopping = true
        pathMonitor.cancel()
        watchdog?.cancel()
        watchdog = nil
        if focusMode { completionHandler(); return }   // в фокус-режиме адаптер не поднимался
        adapter.stop { _ in completionHandler() }
    }

    // MARK: - Статистика для приложения
    /// Приложение шлёт "stats" → возвращаем реальные счётчики трафика туннеля (rx/tx в байтах),
    /// прочитанные из runtime-конфигурации amneziawg-go. Никаких выдуманных цифр.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard String(data: messageData, encoding: .utf8) == "stats" else {
            completionHandler?(nil); return
        }
        adapter.getRuntimeConfiguration { cfg in
            var rx: UInt64 = 0, tx: UInt64 = 0
            for line in (cfg ?? "").split(separator: "\n") {
                if line.hasPrefix("rx_bytes=") { rx += UInt64(line.dropFirst("rx_bytes=".count)) ?? 0 }
                else if line.hasPrefix("tx_bytes=") { tx += UInt64(line.dropFirst("tx_bytes=".count)) ?? 0 }
            }
            completionHandler?(try? JSONSerialization.data(withJSONObject: ["rx": rx, "tx": tx]))
        }
    }

    // MARK: - Локальный режим фокуса (контент-блокировщик, не VPN)
    /// Поднимает туннель, в который заведена ТОЛЬКО «дыра» DNS. Запросы к отвлекающим доменам
    /// (matchDomains) уходят на недостижимый DNS внутри туннеля и дропаются — сайты не резолвятся.
    /// Весь остальной трафик идёт напрямую, наружу. Это on-device блокировщик, без удалённого сервера.
    private func startFocus(domains: [String], completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["10.13.37.2"], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: "10.13.37.1", subnetMask: "255.255.255.255")]
        ipv4.excludedRoutes = [NEIPv4Route.default()]   // всё остальное — мимо туннеля
        settings.ipv4Settings = ipv4
        let dns = NEDNSSettings(servers: ["10.13.37.1"])   // недостижимый DNS внутри туннеля
        dns.matchDomains = domains                          // только эти домены идут в «дыру»
        settings.dnsSettings = dns
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error { completionHandler(error); return }
            self?.focusDrain()
            completionHandler(nil)
        }
    }

    /// Читает и дропает пакеты, попавшие в туннель (только запросы к DNS-дыре) — никуда не пересылает.
    private func focusDrain() {
        packetFlow.readPackets { [weak self] _, _ in
            guard let self, self.focusMode, !self.stopping else { return }
            self.focusDrain()
        }
    }

    /// Раздельное туннелирование: адаптер строит includedRoutes из AllowedIPs (у нас 0.0.0.0/0 —
    /// туннель как маршрут по умолчанию, ради роуминга), а мы выводим «прямые» РФ-сети наружу.
    override func setTunnelNetworkSettings(_ tunnelNetworkSettings: NETunnelNetworkSettings?,
                                           completionHandler: ((Error?) -> Void)? = nil) {
        if !excludedRoutes.isEmpty,
           let settings = tunnelNetworkSettings as? NEPacketTunnelNetworkSettings,
           let ipv4 = settings.ipv4Settings {
            ipv4.includedRoutes = [NEIPv4Route.default()]
            ipv4.excludedRoutes = excludedRoutes
            settings.ipv4Settings = ipv4
        }
        super.setTunnelNetworkSettings(tunnelNetworkSettings, completionHandler: completionHandler)
    }

    /// "a.b.c.d/n" → NEIPv4Route (вход из CIDRMath, уже валиден).
    static func route(from cidr: String) -> NEIPv4Route? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let prefix = Int(parts[1]), (0...32).contains(prefix) else { return nil }
        let m: UInt32 = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
        let mask = "\((m >> 24) & 255).\((m >> 16) & 255).\((m >> 8) & 255).\(m & 255)"
        return NEIPv4Route(destinationAddress: String(parts[0]), subnetMask: mask)
    }

    // MARK: - Роуминг: следим за сменой сети (WiFi ↔ сотовый) и перепривязываем туннель

    private func beginPathMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self, path.status == .satisfied else { return }
            let iface = Self.primaryInterface(of: path)
            if self.currentInterface == nil {
                self.currentInterface = iface           // первый заход — просто запоминаем
            } else if let iface, iface != self.currentInterface {
                self.currentInterface = iface           // сеть сменилась (WiFi→LTE и наоборот)
                self.rebindTunnel()
            }
        }
        pathMonitor.start(queue: pathQueue)
        startWatchdog()
    }

    /// Сторож здоровья туннеля: раз в 6с смотрит счётчики трафика. Если мы активно ШЛЁМ,
    /// но НИЧЕГО не приходит два такта подряд — путь мёртв (например, WiFi отвалился, сокет
    /// висит), и iOS смену сети не отдал. Тогда перезапускаем туннель на активной сети.
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: pathQueue)
        timer.schedule(deadline: .now() + 8, repeating: 6)
        timer.setEventHandler { [weak self] in self?.checkHealth() }
        timer.resume()
        watchdog = timer
    }

    private func checkHealth() {
        guard !rebinding, !stopping else { return }
        adapter.getRuntimeConfiguration { [weak self] cfg in
            guard let self, let cfg, !self.rebinding, !self.stopping else { return }
            var rx: UInt64 = 0, tx: UInt64 = 0, hs: UInt64 = 0
            for line in cfg.split(separator: "\n") {
                if line.hasPrefix("rx_bytes=") { rx += UInt64(line.dropFirst("rx_bytes=".count)) ?? 0 }
                else if line.hasPrefix("tx_bytes=") { tx += UInt64(line.dropFirst("tx_bytes=".count)) ?? 0 }
                else if line.hasPrefix("last_handshake_time_sec=") {
                    let v = UInt64(line.dropFirst("last_handshake_time_sec=".count)) ?? 0
                    if v > hs { hs = v }          // самое свежее рукопожатие среди пиров
                }
            }
            if !self.watchdogPrimed {
                self.watchdogPrimed = true
                self.lastTx = tx; self.lastRx = rx
                return
            }
            let txDelta = tx >= self.lastTx ? tx - self.lastTx : 0
            let rxDelta = rx >= self.lastRx ? rx - self.lastRx : 0
            self.lastTx = tx; self.lastRx = rx

            // (1) Мёртвый путь: активно шлём >2КБ, в ответ тишина (WiFi отвалился, сокет висит).
            self.deadTicks = (txDelta > 2000 && rxDelta < 500) ? self.deadTicks + 1 : 0

            // (2) Протухшее рукопожатие: WG на живой сети переустанавливает handshake за ≤120с;
            // если ему >180с (REJECT_AFTER_TIME превышен), а мы при этом активно шлём — сессия
            // зависла. Именно это ломает TikTok/новые соединения при долгом аптайме: старые
            // потоки ещё теплятся, поэтому счётчики байт «здоровы» и триггер (1) молчит.
            let now = UInt64(Date().timeIntervalSince1970)
            let hsAge = (hs > 0 && now >= hs) ? now - hs : 0
            self.staleTicks = (hs > 0 && hsAge > 180 && txDelta > 1500) ? self.staleTicks + 1 : 0

            // Рестарт не чаще раза в 20с — защита от петли, если сервер реально лёг.
            let cooled = Date().timeIntervalSince(self.lastRebindAt) > 20
            if cooled && (self.deadTicks >= 2 || self.staleTicks >= 2) {
                let why = self.staleTicks >= 2 ? "stale handshake (\(hsAge)s)" : "sending but no reply"
                self.deadTicks = 0; self.staleTicks = 0
                os_log("watchdog: %{public}@ → restart tunnel", log: self.log, type: .default, why)
                self.rebindTunnel()
            }
        }
    }

    private static func primaryInterface(of path: Network.NWPath) -> NWInterface.InterfaceType? {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        return path.availableInterfaces.first?.type
    }

    /// Полный рестарт туннеля на новом интерфейсе: рвём старый сокет (привязанный к мёртвому
    /// WiFi) и поднимаем заново — новый сокет биндится к активной сети (LTE и наоборот).
    /// `stop`+`start` не подвисает, в отличие от `update`. iOS видит `reasserting` и держит трафик.
    private func rebindTunnel() {
        guard !rebinding, !stopping, let cfg = tunnelConfig else { return }
        rebinding = true
        reasserting = true
        lastRebindAt = Date()
        os_log("network changed → restarting tunnel", log: log, type: .default)
        adapter.stop { [weak self] _ in
            guard let self, !self.stopping else { self?.rebinding = false; return }
            self.adapter.start(tunnelConfiguration: cfg) { [weak self] error in
                guard let self else { return }
                if let error {
                    os_log("rebind restart error: %{public}@", log: self.log, type: .error, "\(error)")
                }
                self.watchdogPrimed = false   // счётчики трафика обнулились — сбросить сторожа
                self.deadTicks = 0
                self.staleTicks = 0
                self.reasserting = false
                self.rebinding = false
            }
        }
    }
}

enum TunnelError: Error { case badConfig }

// MARK: - Вендорнутый парсер awg-quick (MIT © WireGuard LLC / amnezia-vpn)
// Ниже — код из amneziawg-apple (Sources/Shared/Model), т.к. в продукте WireGuardKit
// нет convenience-инициализатора fromWgQuickConfig. Imports убраны (они уже вверху файла).



extension TunnelConfiguration {

    enum ParserState {
        case inInterfaceSection
        case inPeerSection
        case notInASection
    }

    enum ParseError: Error {
        case invalidLine(String.SubSequence)
        case noInterface
        case multipleInterfaces
        case interfaceHasNoPrivateKey
        case interfaceHasInvalidPrivateKey(String)
        case interfaceHasInvalidListenPort(String)
        case interfaceHasInvalidAddress(String)
        case interfaceHasInvalidDNS(String)
        case interfaceHasInvalidMTU(String)
        case interfaceHasUnrecognizedKey(String)
        case interfaceHasInvalidCustomParam(String)
        case peerHasNoPublicKey
        case peerHasInvalidPublicKey(String)
        case peerHasInvalidPreSharedKey(String)
        case peerHasInvalidAllowedIP(String)
        case peerHasInvalidEndpoint(String)
        case peerHasInvalidPersistentKeepAlive(String)
        case peerHasInvalidTransferBytes(String)
        case peerHasInvalidLastHandshakeTime(String)
        case peerHasUnrecognizedKey(String)
        case multiplePeersWithSamePublicKey
        case multipleEntriesForKey(String)
    }

    convenience init(fromWgQuickConfig wgQuickConfig: String, called name: String? = nil) throws {
        var interfaceConfiguration: InterfaceConfiguration?
        var peerConfigurations = [PeerConfiguration]()

        let lines = wgQuickConfig.split { $0.isNewline }

        var parserState = ParserState.notInASection
        var attributes = [String: String]()

        for (lineIndex, line) in lines.enumerated() {
            var trimmedLine: String
            if let commentRange = line.range(of: "#") {
                trimmedLine = String(line[..<commentRange.lowerBound])
            } else {
                trimmedLine = String(line)
            }

            trimmedLine = trimmedLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercasedLine = trimmedLine.lowercased()

            if !trimmedLine.isEmpty {
                if let equalsIndex = trimmedLine.firstIndex(of: "=") {
                    // Line contains an attribute
                    let keyWithCase = trimmedLine[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = keyWithCase.lowercased()
                    let value = trimmedLine[trimmedLine.index(equalsIndex, offsetBy: 1)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    let keysWithMultipleEntriesAllowed: Set<String> = ["address", "allowedips", "dns"]
                    if let presentValue = attributes[key] {
                        if keysWithMultipleEntriesAllowed.contains(key) {
                            attributes[key] = presentValue + "," + value
                        } else {
                            throw ParseError.multipleEntriesForKey(keyWithCase)
                        }
                    } else {
                        attributes[key] = value
                    }
                    let interfaceSectionKeys: Set<String> = [
                        "privatekey",
                        "listenport",
                        "address",
                        "dns",
                        "mtu",
                        "jc",
                        "jmin",
                        "jmax",
                        "s1",
                        "s2",
                        "s3",
                        "s4",
                        "h1",
                        "h2",
                        "h3",
                        "h4",
                        "i1",
                        "i2",
                        "i3",
                        "i4",
                        "i5",
                    ]
                    let peerSectionKeys: Set<String> = ["publickey", "presharedkey", "allowedips", "endpoint", "persistentkeepalive"]
                    if parserState == .inInterfaceSection {
                        guard interfaceSectionKeys.contains(key) else {
                            throw ParseError.interfaceHasUnrecognizedKey(keyWithCase)
                        }
                    } else if parserState == .inPeerSection {
                        guard peerSectionKeys.contains(key) else {
                            throw ParseError.peerHasUnrecognizedKey(keyWithCase)
                        }
                    }
                } else if lowercasedLine != "[interface]" && lowercasedLine != "[peer]" {
                    throw ParseError.invalidLine(line)
                }
            }

            let isLastLine = lineIndex == lines.count - 1

            if isLastLine || lowercasedLine == "[interface]" || lowercasedLine == "[peer]" {
                // Previous section has ended; process the attributes collected so far
                if parserState == .inInterfaceSection {
                    let interface = try TunnelConfiguration.collate(interfaceAttributes: attributes)
                    guard interfaceConfiguration == nil else { throw ParseError.multipleInterfaces }
                    interfaceConfiguration = interface
                } else if parserState == .inPeerSection {
                    let peer = try TunnelConfiguration.collate(peerAttributes: attributes)
                    peerConfigurations.append(peer)
                }
            }

            if lowercasedLine == "[interface]" {
                parserState = .inInterfaceSection
                attributes.removeAll()
            } else if lowercasedLine == "[peer]" {
                parserState = .inPeerSection
                attributes.removeAll()
            }
        }

        let peerPublicKeysArray = peerConfigurations.map { $0.publicKey }
        let peerPublicKeysSet = Set<PublicKey>(peerPublicKeysArray)
        if peerPublicKeysArray.count != peerPublicKeysSet.count {
            throw ParseError.multiplePeersWithSamePublicKey
        }

        if let interfaceConfiguration = interfaceConfiguration {
            self.init(name: name, interface: interfaceConfiguration, peers: peerConfigurations)
        } else {
            throw ParseError.noInterface
        }
    }

    func asWgQuickConfig() -> String {
        var output = "[Interface]\n"
        output.append("PrivateKey = \(interface.privateKey.base64Key)\n")
        if let listenPort = interface.listenPort {
            output.append("ListenPort = \(listenPort)\n")
        }

        if let junkPacketCount = interface.junkPacketCount {
            output.append("Jc = \(junkPacketCount)\n")
        }
        if let junkPacketMinSize = interface.junkPacketMinSize {
            output.append("Jmin = \(junkPacketMinSize)\n")
        }
        if let junkPacketMaxSize = interface.junkPacketMaxSize {
            output.append("Jmax = \(junkPacketMaxSize)\n")
        }
        if let initPacketJunkSize = interface.initPacketJunkSize {
            output.append("S1 = \(initPacketJunkSize)\n")
        }
        if let responsePacketJunkSize = interface.responsePacketJunkSize {
            output.append("S2 = \(responsePacketJunkSize)\n")
        }
        if let cookieReplyPacketJunkSize = interface.cookieReplyPacketJunkSize {
            output.append("S3 = \(cookieReplyPacketJunkSize)\n")
        }
        if let transportPacketJunkSize = interface.transportPacketJunkSize {
            output.append("S4 = \(transportPacketJunkSize)\n")
        }
        if let initPacketMagicHeader = interface.initPacketMagicHeader {
            output.append("H1 = \(initPacketMagicHeader)\n")
        }
        if let responsePacketMagicHeader = interface.responsePacketMagicHeader {
            output.append("H2 = \(responsePacketMagicHeader)\n")
        }
        if let underloadPacketMagicHeader = interface.underloadPacketMagicHeader {
            output.append("H3 = \(underloadPacketMagicHeader)\n")
        }
        if let transportPacketMagicHeader = interface.transportPacketMagicHeader {
            output.append("H4 = \(transportPacketMagicHeader)\n")
        }
        if let specialJunk1 = interface.specialJunk1 {
            output.append("I1 = \(specialJunk1)\n")
        }
        if let specialJunk2 = interface.specialJunk2 {
            output.append("I2 = \(specialJunk2)\n")
        }
        if let specialJunk3 = interface.specialJunk3 {
            output.append("I3 = \(specialJunk3)\n")
        }
        if let specialJunk4 = interface.specialJunk4 {
            output.append("I4 = \(specialJunk4)\n")
        }
        if let specialJunk5 = interface.specialJunk5 {
            output.append("I5 = \(specialJunk5)\n")
        }
        if !interface.addresses.isEmpty {
            let addressString = interface.addresses.map { $0.stringRepresentation }.joined(separator: ", ")
            output.append("Address = \(addressString)\n")
        }
        if !interface.dns.isEmpty || !interface.dnsSearch.isEmpty {
            var dnsLine = interface.dns.map { $0.stringRepresentation }
            dnsLine.append(contentsOf: interface.dnsSearch)
            let dnsString = dnsLine.joined(separator: ", ")
            output.append("DNS = \(dnsString)\n")
        }
        if let mtu = interface.mtu {
            output.append("MTU = \(mtu)\n")
        }

        for peer in peers {
            output.append("\n[Peer]\n")
            output.append("PublicKey = \(peer.publicKey.base64Key)\n")
            if let preSharedKey = peer.preSharedKey?.base64Key {
                output.append("PresharedKey = \(preSharedKey)\n")
            }
            if !peer.allowedIPs.isEmpty {
                let allowedIPsString = peer.allowedIPs.map { $0.stringRepresentation }.joined(separator: ", ")
                output.append("AllowedIPs = \(allowedIPsString)\n")
            }
            if let endpoint = peer.endpoint {
                output.append("Endpoint = \(endpoint.stringRepresentation)\n")
            }
            if let persistentKeepAlive = peer.persistentKeepAlive {
                output.append("PersistentKeepalive = \(persistentKeepAlive)\n")
            }
        }

        return output
    }

    private static func collate(interfaceAttributes attributes: [String: String]) throws -> InterfaceConfiguration {
        guard let privateKeyString = attributes["privatekey"] else {
            throw ParseError.interfaceHasNoPrivateKey
        }
        guard let privateKey = PrivateKey(base64Key: privateKeyString) else {
            throw ParseError.interfaceHasInvalidPrivateKey(privateKeyString)
        }
        var interface = InterfaceConfiguration(privateKey: privateKey)
        if let listenPortString = attributes["listenport"] {
            guard let listenPort = UInt16(listenPortString) else {
                throw ParseError.interfaceHasInvalidListenPort(listenPortString)
            }
            interface.listenPort = listenPort
        }
        if let addressesString = attributes["address"] {
            var addresses = [IPAddressRange]()
            for addressString in addressesString.splitToArray(trimmingCharacters: .whitespacesAndNewlines) {
                guard let address = IPAddressRange(from: addressString) else {
                    throw ParseError.interfaceHasInvalidAddress(addressString)
                }
                addresses.append(address)
            }
            interface.addresses = addresses
        }
        if let dnsString = attributes["dns"] {
            var dnsServers = [DNSServer]()
            var dnsSearch = [String]()
            for dnsServerString in dnsString.splitToArray(trimmingCharacters: .whitespacesAndNewlines) {
                if let dnsServer = DNSServer(from: dnsServerString) {
                    dnsServers.append(dnsServer)
                } else {
                    dnsSearch.append(dnsServerString)
                }
            }
            interface.dns = dnsServers
            interface.dnsSearch = dnsSearch
        }
        if let mtuString = attributes["mtu"] {
            guard let mtu = UInt16(mtuString) else {
                throw ParseError.interfaceHasInvalidMTU(mtuString)
            }
            interface.mtu = mtu
        }
        if let junkPacketCountString = attributes["jc"] {
            guard let junkPacketCount = UInt16(junkPacketCountString) else {
                throw ParseError.interfaceHasInvalidCustomParam(junkPacketCountString)
            }
            interface.junkPacketCount = junkPacketCount
        }
        if let junkPacketMinSizeString = attributes["jmin"] {
            guard let junkPacketMinSize = UInt16(junkPacketMinSizeString) else {
                throw ParseError.interfaceHasInvalidCustomParam(junkPacketMinSizeString)
            }
            interface.junkPacketMinSize = junkPacketMinSize
        }
        if let junkPacketMaxSizeString = attributes["jmax"] {
            guard let junkPacketMaxSize = UInt16(junkPacketMaxSizeString) else {
                throw ParseError.interfaceHasInvalidCustomParam(junkPacketMaxSizeString)
            }
            interface.junkPacketMaxSize = junkPacketMaxSize
        }
        if let initPacketJunkSizeString = attributes["s1"] {
            guard let initPacketJunkSize = UInt16(initPacketJunkSizeString) else {
                throw ParseError.interfaceHasInvalidCustomParam(initPacketJunkSizeString)
            }
            interface.initPacketJunkSize = initPacketJunkSize
        }
        if let responsePacketJunkSizeString = attributes["s2"] {
            guard let responsePacketJunkSize = UInt16(responsePacketJunkSizeString) else {
                throw ParseError.interfaceHasInvalidCustomParam(responsePacketJunkSizeString)
            }
            interface.responsePacketJunkSize = responsePacketJunkSize
        }
        if let cookieReplyPacketJunkSizeString = attributes["s3"] {
            guard let cookieReplyPacketJunkSize = UInt16(cookieReplyPacketJunkSizeString) else {
                throw ParseError.interfaceHasInvalidCustomParam(cookieReplyPacketJunkSizeString)
            }
            interface.cookieReplyPacketJunkSize = cookieReplyPacketJunkSize
        }
        if let transportPacketJunkSizeString = attributes["s4"] {
            guard let transportPacketJunkSize = UInt16(transportPacketJunkSizeString) else {
                throw ParseError.interfaceHasInvalidCustomParam(transportPacketJunkSizeString)
            }
            interface.transportPacketJunkSize = transportPacketJunkSize
        }
        if let initPacketMagicHeaderString = attributes["h1"] {
            interface.initPacketMagicHeader = initPacketMagicHeaderString
        }
        if let responsePacketMagicHeaderString = attributes["h2"] {
            interface.responsePacketMagicHeader = responsePacketMagicHeaderString
        }
        if let underloadPacketMagicHeaderString = attributes["h3"] {
            interface.underloadPacketMagicHeader = underloadPacketMagicHeaderString
        }
        if let transportPacketMagicHeaderString = attributes["h4"] {
            interface.transportPacketMagicHeader = transportPacketMagicHeaderString
        }
        if let specialJunk1String = attributes["i1"] {
            interface.specialJunk1 = specialJunk1String
        }
        if let specialJunk2String = attributes["i2"] {
            interface.specialJunk2 = specialJunk2String
        }
        if let specialJunk3String = attributes["i3"] {
            interface.specialJunk3 = specialJunk3String
        }
        if let specialJunk4String = attributes["i4"] {
            interface.specialJunk4 = specialJunk4String
        }
        if let specialJunk5String = attributes["i5"] {
            interface.specialJunk5 = specialJunk5String
        }
        return interface
    }

    private static func collate(peerAttributes attributes: [String: String]) throws -> PeerConfiguration {
        guard let publicKeyString = attributes["publickey"] else {
            throw ParseError.peerHasNoPublicKey
        }
        guard let publicKey = PublicKey(base64Key: publicKeyString) else {
            throw ParseError.peerHasInvalidPublicKey(publicKeyString)
        }
        var peer = PeerConfiguration(publicKey: publicKey)
        if let preSharedKeyString = attributes["presharedkey"] {
            guard let preSharedKey = PreSharedKey(base64Key: preSharedKeyString) else {
                throw ParseError.peerHasInvalidPreSharedKey(preSharedKeyString)
            }
            peer.preSharedKey = preSharedKey
        }
        if let allowedIPsString = attributes["allowedips"] {
            var allowedIPs = [IPAddressRange]()
            for allowedIPString in allowedIPsString.splitToArray(trimmingCharacters: .whitespacesAndNewlines) {
                guard let allowedIP = IPAddressRange(from: allowedIPString) else {
                    throw ParseError.peerHasInvalidAllowedIP(allowedIPString)
                }
                allowedIPs.append(allowedIP)
            }
            peer.allowedIPs = allowedIPs
        }
        if let endpointString = attributes["endpoint"] {
            guard let endpoint = Endpoint(from: endpointString) else {
                throw ParseError.peerHasInvalidEndpoint(endpointString)
            }
            peer.endpoint = endpoint
        }
        if let persistentKeepAliveString = attributes["persistentkeepalive"] {
            guard let persistentKeepAlive = UInt16(persistentKeepAliveString) else {
                throw ParseError.peerHasInvalidPersistentKeepAlive(persistentKeepAliveString)
            }
            peer.persistentKeepAlive = persistentKeepAlive
        }
        return peer
    }

}



extension String {

    func splitToArray(separator: Character = ",", trimmingCharacters: CharacterSet? = nil) -> [String] {
        return split(separator: separator)
            .map {
                if let charSet = trimmingCharacters {
                    return $0.trimmingCharacters(in: charSet)
                } else {
                    return String($0)
                }
        }
    }

}

extension Optional where Wrapped == String {

    func splitToArray(separator: Character = ",", trimmingCharacters: CharacterSet? = nil) -> [String] {
        switch self {
        case .none:
            return []
        case .some(let wrapped):
            return wrapped.splitToArray(separator: separator, trimmingCharacters: trimmingCharacters)
        }
    }

}
