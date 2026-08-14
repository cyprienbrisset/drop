import Foundation
import Security

/// Abstraction du trousseau (§5.11, ADR-05) : la clé de chiffrement de `index.db` (mode Standard)
/// vit exclusivement dans le Keychain de cette machine, jamais synchronisée iCloud, jamais
/// écrite en clair sur disque. Protocole injectable pour permettre des doubles de test sans
/// toucher au vrai trousseau de la machine qui exécute les tests.
public protocol KeychainKeyStore: Sendable {
    func loadKey(service: String, account: String) throws -> Data?
    func storeKey(_ key: Data, service: String, account: String) throws
    func deleteKey(service: String, account: String) throws
}

public enum KeychainKeyStoreError: Error, Sendable, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Implémentation réelle via `Security.framework`. `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// (§5.11) : jamais exportable vers un autre appareil, même via une sauvegarde iCloud Keychain.
public struct SecKeychainKeyStore: KeychainKeyStore {
    public init() {}

    public func loadKey(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainKeyStoreError.unexpectedStatus(status) }
        return item as? Data
    }

    public func storeKey(_ key: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var attributes = query
        attributes[kSecValueData as String] = key
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: key] as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainKeyStoreError.unexpectedStatus(status) }
    }

    public func deleteKey(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainKeyStoreError.unexpectedStatus(status)
        }
    }
}

/// Clé de chiffrement du coffre (§5.11, ADR-05) : 256 bits, générée une seule fois puis
/// persistée au Keychain — jamais régénérée silencieusement (une régénération rendrait `index.db`
/// illisible, équivalent à une perte de données).
public enum VaultEncryptionKey {
    public static let defaultService = "com.wakastellar.drop.vault-key"

    public static func getOrCreate(
        store: KeychainKeyStore, service: String = defaultService, account: String
    ) throws -> Data {
        if let existing = try store.loadKey(service: service, account: account) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else { throw KeychainKeyStoreError.unexpectedStatus(result) }
        let key = Data(bytes)
        try store.storeKey(key, service: service, account: account)
        return key
    }
}
