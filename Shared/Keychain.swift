import Foundation
import Security

/// Минимальное безопасное хранилище для ключа-подписки.
/// Токен — единственный секрет доступа, поэтому он лежит в Keychain
/// (а не в UserDefaults): не попадает в незашифрованные бэкапы и недоступен
/// другим приложениям. Класс — обычный generic password, привязка к устройству
/// (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly): работает в фоне после
/// первой разблокировки, но не переносится на новое устройство и не бэкапится.
enum Keychain {
    private static let service = "com.matcha.lab.secret"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            // data-protection keychain (как на iOS): доступ тихий, без диалога логин-связки,
            // элемент привязан к app-id приложения. Подписанное приложение имеет keychain-access-group.
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // upsert: сначала пробуем обновить, если нет — добавляем.
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attrs) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            // data-protection keychain (как на iOS): доступ тихий, без диалога логин-связки,
            // элемент привязан к app-id приложения. Подписанное приложение имеет keychain-access-group.
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            // data-protection keychain (как на iOS): доступ тихий, без диалога логин-связки,
            // элемент привязан к app-id приложения. Подписанное приложение имеет keychain-access-group.
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
