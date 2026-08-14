import DropCore
import Foundation
import Testing

/// Double en mémoire : les tests ne doivent jamais toucher le vrai trousseau de la machine qui
/// les exécute (comportement partagé, potentiellement soumis à une invite d'autorisation).
final class InMemoryKeyStore: KeychainKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    private func key(service: String, account: String) -> String { "\(service)|\(account)" }

    func loadKey(service: String, account: String) throws -> Data? {
        lock.withLock { storage[key(service: service, account: account)] }
    }

    func storeKey(_ key: Data, service: String, account: String) throws {
        lock.withLock { storage[self.key(service: service, account: account)] = key }
    }

    func deleteKey(service: String, account: String) throws {
        lock.withLock { storage.removeValue(forKey: key(service: service, account: account)) }
    }
}

@Test func getOrCreateGeneratesA256BitKeyOnFirstCall() throws {
    let store = InMemoryKeyStore()
    let key = try VaultEncryptionKey.getOrCreate(store: store, account: "vault-1")
    #expect(key.count == 32)
}

@Test func getOrCreateReturnsTheSameKeyOnSubsequentCalls() throws {
    let store = InMemoryKeyStore()
    let first = try VaultEncryptionKey.getOrCreate(store: store, account: "vault-1")
    let second = try VaultEncryptionKey.getOrCreate(store: store, account: "vault-1")
    #expect(first == second)
}

@Test func getOrCreateGeneratesDistinctKeysForDistinctAccounts() throws {
    let store = InMemoryKeyStore()
    let vaultA = try VaultEncryptionKey.getOrCreate(store: store, account: "vault-a")
    let vaultB = try VaultEncryptionKey.getOrCreate(store: store, account: "vault-b")
    #expect(vaultA != vaultB)
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
