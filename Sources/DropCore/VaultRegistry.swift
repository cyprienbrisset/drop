import Foundation

/// Un coffre connu (§5, backlog V3 — « coffres multiples chiffrés séparément »). Ne porte que des
/// métadonnées non sensibles : jamais une clé, jamais un extrait de contenu — chaque coffre garde
/// sa propre clé Keychain (DRO-51), totalement indépendante de celle des autres coffres.
public struct VaultDescriptor: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public let path: String

    public init(id: String = UUID().uuidString, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

/// Persistance du registre, injectable pour les tests — jamais le vrai `UserDefaults.standard`
/// partagé de la machine qui exécute la suite.
public protocol VaultRegistryStore: Sendable {
    func loadDescriptors() -> [VaultDescriptor]
    func saveDescriptors(_ descriptors: [VaultDescriptor])
    func loadActiveVaultID() -> String?
    func saveActiveVaultID(_ id: String?)
}

public final class UserDefaultsVaultRegistryStore: VaultRegistryStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let descriptorsKey = "dropVaultRegistry.descriptors"
    private let activeIDKey = "dropVaultRegistry.activeID"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadDescriptors() -> [VaultDescriptor] {
        guard let data = defaults.data(forKey: descriptorsKey) else { return [] }
        return (try? JSONDecoder().decode([VaultDescriptor].self, from: data)) ?? []
    }

    public func saveDescriptors(_ descriptors: [VaultDescriptor]) {
        guard let data = try? JSONEncoder().encode(descriptors) else { return }
        defaults.set(data, forKey: descriptorsKey)
    }

    public func loadActiveVaultID() -> String? {
        defaults.string(forKey: activeIDKey)
    }

    public func saveActiveVaultID(_ id: String?) {
        if let id { defaults.set(id, forKey: activeIDKey) } else { defaults.removeObject(forKey: activeIDKey) }
    }
}

/// Registre des coffres connus par cette machine (§5, backlog V3). Ce registre lui-même vit hors de
/// tout coffre (dans les préférences de l'application) : il doit être lisible avant même qu'un
/// premier coffre ne soit ouvert, pour savoir lequel ouvrir.
public struct VaultRegistry: Sendable {
    private let store: VaultRegistryStore

    public init(store: VaultRegistryStore = UserDefaultsVaultRegistryStore()) {
        self.store = store
    }

    public func listVaults() -> [VaultDescriptor] {
        store.loadDescriptors()
    }

    public var activeVaultID: String? {
        store.loadActiveVaultID()
    }

    /// Un chemin déjà connu n'est jamais dupliqué — retourne le descripteur existant plutôt que
    /// d'en créer un second pour le même dossier.
    @discardableResult
    public func registerVault(name: String, path: String) -> VaultDescriptor {
        var descriptors = store.loadDescriptors()
        if let existing = descriptors.first(where: { $0.path == path }) {
            return existing
        }
        let descriptor = VaultDescriptor(name: name, path: path)
        descriptors.append(descriptor)
        store.saveDescriptors(descriptors)
        return descriptor
    }

    public func setActiveVault(id: String) {
        store.saveActiveVaultID(id)
    }

    /// Retire un coffre du registre — ne touche jamais au dossier ni à son contenu sur disque
    /// (§principe de non-enfermement) : seule la trace applicative disparaît.
    public func removeVault(id: String) {
        var descriptors = store.loadDescriptors()
        descriptors.removeAll { $0.id == id }
        store.saveDescriptors(descriptors)
        if store.loadActiveVaultID() == id {
            store.saveActiveVaultID(descriptors.first?.id)
        }
    }

    public func renameVault(id: String, name: String) {
        var descriptors = store.loadDescriptors()
        guard let index = descriptors.firstIndex(where: { $0.id == id }) else { return }
        descriptors[index].name = name
        store.saveDescriptors(descriptors)
    }

    /// Appelé une seule fois, au lancement : garantit qu'un coffre par défaut existe dans le
    /// registre et qu'un coffre actif est défini, sans jamais écraser un choix déjà fait par
    /// l'utilisateur (basculer vers un autre coffre lors d'une session précédente).
    @discardableResult
    public func ensureDefaultVaultRegistered(name: String, path: String) -> VaultDescriptor {
        if let existing = listVaults().first(where: { $0.path == path }) {
            if activeVaultID == nil { setActiveVault(id: existing.id) }
            return existing
        }
        let descriptor = registerVault(name: name, path: path)
        setActiveVault(id: descriptor.id)
        return descriptor
    }
}
