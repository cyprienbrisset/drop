import DropCore
import Foundation
import Testing

/// Double en mémoire : les tests ne doivent jamais toucher le vrai `UserDefaults.standard` de la
/// machine qui les exécute (état partagé entre suites, potentiellement des exécutions passées).
final class InMemoryVaultRegistryStore: VaultRegistryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var descriptors: [VaultDescriptor] = []
    private var activeID: String?

    func loadDescriptors() -> [VaultDescriptor] { lock.withLock { descriptors } }
    func saveDescriptors(_ descriptors: [VaultDescriptor]) { lock.withLock { self.descriptors = descriptors } }
    func loadActiveVaultID() -> String? { lock.withLock { activeID } }
    func saveActiveVaultID(_ id: String?) { lock.withLock { self.activeID = id } }
}

@Test func ensuringTheDefaultVaultRegistersItAndMarksItActiveOnFirstLaunch() {
    let registry = VaultRegistry(store: InMemoryVaultRegistryStore())

    let descriptor = registry.ensureDefaultVaultRegistered(name: "Coffre principal", path: "/tmp/drop-default")

    #expect(registry.listVaults() == [descriptor])
    #expect(registry.activeVaultID == descriptor.id)
}

@Test func ensuringTheDefaultVaultTwiceNeverDuplicatesItOrOverridesAnAlreadyChosenActiveVault() {
    let store = InMemoryVaultRegistryStore()
    let registry = VaultRegistry(store: store)
    let defaultDescriptor = registry.ensureDefaultVaultRegistered(name: "Coffre principal", path: "/tmp/drop-default")
    let otherDescriptor = registry.registerVault(name: "Coffre pro", path: "/tmp/drop-pro")
    registry.setActiveVault(id: otherDescriptor.id)

    let result = registry.ensureDefaultVaultRegistered(name: "Coffre principal", path: "/tmp/drop-default")

    #expect(result.id == defaultDescriptor.id)
    #expect(registry.listVaults().count == 2)
    #expect(registry.activeVaultID == otherDescriptor.id) // jamais écrasé par le second appel.
}

@Test func registeringTheSamePathTwiceReturnsTheExistingDescriptor() {
    let registry = VaultRegistry(store: InMemoryVaultRegistryStore())
    let first = registry.registerVault(name: "Coffre pro", path: "/tmp/drop-pro")

    let second = registry.registerVault(name: "Autre nom", path: "/tmp/drop-pro")

    #expect(second.id == first.id)
    #expect(second.name == "Coffre pro") // le nom d'origine n'est jamais silencieusement remplacé.
    #expect(registry.listVaults().count == 1)
}

@Test func removingTheActiveVaultFallsBackToAnotherKnownVault() {
    let registry = VaultRegistry(store: InMemoryVaultRegistryStore())
    let a = registry.registerVault(name: "A", path: "/tmp/a")
    let b = registry.registerVault(name: "B", path: "/tmp/b")
    registry.setActiveVault(id: a.id)

    registry.removeVault(id: a.id)

    #expect(registry.listVaults() == [b])
    #expect(registry.activeVaultID == b.id)
}

@Test func removingTheOnlyVaultLeavesNoActiveVault() {
    let registry = VaultRegistry(store: InMemoryVaultRegistryStore())
    let only = registry.registerVault(name: "Seul", path: "/tmp/seul")
    registry.setActiveVault(id: only.id)

    registry.removeVault(id: only.id)

    #expect(registry.listVaults().isEmpty)
    #expect(registry.activeVaultID == nil)
}

@Test func renamingAVaultUpdatesItsNameOnly() {
    let registry = VaultRegistry(store: InMemoryVaultRegistryStore())
    let descriptor = registry.registerVault(name: "Ancien nom", path: "/tmp/drop")

    registry.renameVault(id: descriptor.id, name: "Nouveau nom")

    let updated = registry.listVaults().first
    #expect(updated?.name == "Nouveau nom")
    #expect(updated?.path == descriptor.path)
    #expect(updated?.id == descriptor.id)
}
