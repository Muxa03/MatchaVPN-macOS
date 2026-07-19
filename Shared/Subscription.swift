import Foundation

/// Сервер из каталога (без секретов — только страна/город/протоколы).
struct CatalogServer: Codable, Identifiable, Equatable {
    let id: String
    let country: String
    let city: String
    let flag: String
    let protocols: [String]

    var vpnProtocols: [VPNProtocol] { protocols.compactMap { VPNProtocol(apiID: $0) } }
}

/// Подписка: клиент держит ТОЛЬКО непрозрачный токен. По нему тянет каталог
/// и резолвит конфиг для выбранного сервера+протокола. Сырые ключи в приложении не хранятся.
@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var servers: [CatalogServer] = []
    @Published private(set) var selectedServerID: String?
    @Published private(set) var selectedProtoID: String
    @Published var lastError: String?

    // Control plane (отдельная нода, HTTPS через Let's Encrypt).
    private let base = "https://matchavpn.space"
    private let kToken = "matcha.sub.token"
    private let kServer = "matcha.sub.server"
    private let kProto = "matcha.sub.proto"

    init() {
        let d = UserDefaults.standard
        // Токен теперь в Keychain. Разовая миграция со старой версии,
        // где он лежал в UserDefaults открытым текстом.
        if let legacy = d.string(forKey: kToken) {
            Keychain.set(legacy, for: kToken)
            d.removeObject(forKey: kToken)
        }
        token = Keychain.get(kToken)
        selectedServerID = d.string(forKey: kServer)
        selectedProtoID = d.string(forKey: kProto) ?? VPNProtocol.amneziaWG.apiID
    }

    var selectedServer: CatalogServer? {
        servers.first { $0.id == selectedServerID } ?? servers.first
    }
    var selectedProto: VPNProtocol { VPNProtocol(apiID: selectedProtoID) ?? .amneziaWG }

    // MARK: - токен
    func setToken(_ raw: String) {
        let t = extractToken(raw)
        guard !t.isEmpty else { return }
        token = t
        Keychain.set(t, for: kToken)
        Task { await refreshCatalog() }
    }

    func signOut() {
        token = nil; servers = []
        Keychain.remove(kToken)
    }

    func selectServer(_ id: String) {
        selectedServerID = id
        UserDefaults.standard.set(id, forKey: kServer)
        // если у нового сервера нет текущего протокола — берём первый доступный
        if let s = selectedServer, !s.protocols.contains(selectedProtoID) {
            selectProto(s.protocols.first ?? VPNProtocol.amneziaWG.apiID)
        }
    }

    func selectProto(_ apiID: String) {
        selectedProtoID = apiID
        UserDefaults.standard.set(apiID, forKey: kProto)
    }

    // MARK: - сеть
    func refreshCatalog() async {
        guard let token, let url = URL(string: "\(base)/catalog") else { return }
        // Токен уходит заголовком X-Token, а не в URL — чтобы не оседал
        // в серверных access-логах и кешах прокси.
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "X-Token")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard Self.ok(resp) else { lastError = "Ключ недействителен или срок истёк"; return }
            let cat = try JSONDecoder().decode(Catalog.self, from: data)
            servers = cat.servers
            if selectedServerID == nil { selectedServerID = servers.first?.id }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Резолвит рабочий конфиг для выбранного сервера+протокола (per-user — в control plane).
    func resolveSelected() async -> String? {
        guard let token, let sid = selectedServer?.id,
              let url = URL(string: "\(base)/resolve") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "X-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["server": sid, "proto": selectedProtoID])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard Self.ok(resp) else { lastError = "Ключ недействителен или срок истёк"; return nil }
            return try JSONDecoder().decode(ResolveResp.self, from: data).config
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// HTTP-статус 2xx? (иначе — просроченный/битый ключ, отдаём внятную ошибку).
    private static func ok(_ resp: URLResponse) -> Bool {
        (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
    }

    private func extractToken(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c = URLComponents(string: t), c.scheme == "matcha",
           let tok = c.queryItems?.first(where: { $0.name == "token" })?.value {
            return tok
        }
        return t
    }

    private struct Catalog: Codable { let version: Int; let servers: [CatalogServer] }
    private struct ResolveResp: Codable { let server: String; let proto: String; let config: String }
}
