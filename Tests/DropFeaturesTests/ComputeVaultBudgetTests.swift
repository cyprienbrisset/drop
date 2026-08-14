import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import Testing

@Test func vaultBudgetReflectsDeduplicationSavings() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let sourceA = URL(fileURLWithPath: "/incoming/facture.pdf")
    let sourceB = URL(fileURLWithPath: "/incoming/facture-copie.pdf")
    let content = Data(repeating: 7, count: 1000)
    fileSystem.seed(sourceA.path, contents: content)
    fileSystem.seed(sourceB.path, contents: content) // même contenu, même hash, même blob.

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-budget-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let database = try DropIndexDatabase(path: dbPath)

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    _ = try await ingest.ingest(fileAt: sourceA)
    _ = try await ingest.ingest(fileAt: sourceB)

    let compute = ComputeVaultBudget(database: database, indexPath: URL(fileURLWithPath: dbPath))
    let budget = try await compute.compute()

    #expect(budget.vaultSizeBytes == 1000) // un seul blob physique de 1000 octets...
    #expect(budget.dedupSavingsBytes == 1000) // ...alors que deux documents de 1000 octets existent.
    #expect(budget.indexSizeBytes > 0) // le fichier index.db existe réellement sur disque.
    #expect(budget.vectorsSizeBytes == 0) // vectors.db n'existe pas encore (Phase 6).
}

@Test func vaultBudgetIsZeroForAnEmptyVault() async throws {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-budget-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let database = try DropIndexDatabase(path: dbPath)

    let compute = ComputeVaultBudget(database: database, indexPath: URL(fileURLWithPath: dbPath))
    let budget = try await compute.compute()

    #expect(budget.vaultSizeBytes == 0)
    #expect(budget.dedupSavingsBytes == 0)
}
