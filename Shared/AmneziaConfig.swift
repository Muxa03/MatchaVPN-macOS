import Foundation

/// Конфигурация AmneziaWG — обфусцированного WireGuard.
/// От обычного WireGuard отличается параметрами обфускации (Jc/Jmin/Jmax, S1/S2, H1..H4),
/// которые делают каждый сервер «уникальным диалектом» и мешают DPI ловить туннель по сигнатуре.
struct AmneziaConfig: Codable, Equatable {
    // [Interface]
    var privateKey: String
    var address: String              // напр. "10.8.1.2/32"
    var dns: String                  // напр. "1.1.1.1"

    // Обфускация AmneziaWG
    var junkPacketCount: Int         // Jc  — сколько «мусорных» пакетов слать перед handshake
    var junkPacketMinSize: Int       // Jmin
    var junkPacketMaxSize: Int       // Jmax
    var initPacketJunkSize: Int      // S1  — паддинг init-пакета
    var responsePacketJunkSize: Int  // S2  — паддинг response-пакета
    var h1: UInt32                   // H1..H4 — подменённые типы заголовков (уникальны на сервер)
    var h2: UInt32
    var h3: UInt32
    var h4: UInt32

    // [Peer]
    var peerPublicKey: String
    var presharedKey: String?
    var endpoint: String             // "host:port"
    var allowedIPs: String           // "0.0.0.0/0, ::/0"
    var persistentKeepalive: Int

    /// Строка в формате awg-quick — её понимает бэкенд amneziawg-go в расширении.
    func quickConfigString() -> String {
        var s = "[Interface]\n"
        s += "PrivateKey = \(privateKey)\n"
        s += "Address = \(address)\n"
        s += "DNS = \(dns)\n"
        s += "Jc = \(junkPacketCount)\n"
        s += "Jmin = \(junkPacketMinSize)\n"
        s += "Jmax = \(junkPacketMaxSize)\n"
        s += "S1 = \(initPacketJunkSize)\n"
        s += "S2 = \(responsePacketJunkSize)\n"
        s += "H1 = \(h1)\nH2 = \(h2)\nH3 = \(h3)\nH4 = \(h4)\n\n"
        s += "[Peer]\n"
        s += "PublicKey = \(peerPublicKey)\n"
        if let psk = presharedKey, !psk.isEmpty { s += "PresharedKey = \(psk)\n" }
        s += "AllowedIPs = \(allowedIPs)\n"
        s += "Endpoint = \(endpoint)\n"
        s += "PersistentKeepalive = \(persistentKeepalive)\n"
        return s
    }
}

extension AmneziaConfig {
    /// Пример-заглушка (ключи невалидны). Заменить конфигом с реального сервера MATCHA.
    static let placeholder = AmneziaConfig(
        privateKey: "PLACEHOLDER_PRIVATE_KEY=",
        address: "10.8.1.2/32",
        dns: "1.1.1.1",
        junkPacketCount: 4, junkPacketMinSize: 40, junkPacketMaxSize: 70,
        initPacketJunkSize: 50, responsePacketJunkSize: 100,
        h1: 1_500_000_001, h2: 1_500_000_002, h3: 1_500_000_003, h4: 1_500_000_004,
        peerPublicKey: "PLACEHOLDER_SERVER_PUBLIC_KEY=",
        presharedKey: nil,
        endpoint: "ams-01.matcha.lab:51820",
        allowedIPs: "0.0.0.0/0, ::/0",
        persistentKeepalive: 25
    )
}

/// Общие идентификаторы приложения и расширения (macOS-таргет).
enum AppIDs {
    /// bundle id системного расширения-туннеля. Должен совпадать с id, под которым
    /// оно активируется через OSSystemExtensionRequest и указано как провайдер в NETunnelProviderProtocol.
    static let tunnelBundleId = "space.matchavpn.mac.tunnel"
}

/// Транспорт приложения: AmneziaWG — обфусцированный WireGuard, устойчив к DPI/ТСПУ.
enum VPNProtocol: String, CaseIterable, Identifiable, Codable {
    case amneziaWG = "AmneziaWG"

    var id: String { rawValue }
    /// Ярлык для пользователя. Под капотом остаётся AmneziaWG (см. apiID).
    var displayName: String { "Матча" }
    var chip: String { "Матча" }
    var apiID: String { "amneziaWG" }

    init?(apiID: String) {
        guard apiID == "amneziaWG" else { return nil }
        self = .amneziaWG
    }
}
