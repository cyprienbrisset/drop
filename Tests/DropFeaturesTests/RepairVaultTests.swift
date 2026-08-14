import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import GRDB
import Testing

private func makeVault() throws -> (VaultService, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drop-repair-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (VaultService(vaultRoot: root), root)
}

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-repair-index-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

private func writeSourceFile(named name: String, contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func repairReconstructsOneDocumentPerBlobFoundOnDisk() async throws {
    let (vault, root) = try makeVault()
    let sourceA = try writeSourceFile(named: "facture-edf.pdf", contents: "facture edf juillet")
    let sourceB = try writeSourceFile(named: "contrat.pdf", contents: "contrat assurance habitation")
    _ = try vault.writeBlob(fromFileAt: sourceA, originalPath: sourceA.path)
    _ = try vault.writeBlob(fromFileAt: sourceB, originalPath: sourceB.path)

    let database = try makeDatabase()
    let repair = RepairVault(vaultRoot: root)
    let report = try await repair.rebuildIndex(into: database)

    #expect(report.reconstructedDocumentCount == 2)
    #expect(report.unreadableBlobCount == 0)

    let displayNames: [String] = try await database.pool.read { db in
        try String.fetchAll(db, sql: "SELECT display_name FROM documents ORDER BY display_name")
    }
    #expect(displayNames.count == 2)
    #expect(displayNames.contains { $0.hasSuffix("contrat.pdf") })
    #expect(displayNames.contains { $0.hasSuffix("facture-edf.pdf") })

    let ftsCount = try await database.pool.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM fts_docs") ?? 0
    }
    #expect(ftsCount == 2)
}

@Test func repairSetsRefCountFromTheReconstructedBlobsTable() async throws {
    let (vault, root) = try makeVault()
    let source = try writeSourceFile(named: "releve.pdf", contents: "relevé bancaire janvier")
    let result = try vault.writeBlob(fromFileAt: source)

    let database = try makeDatabase()
    let repair = RepairVault(vaultRoot: root)
    _ = try await repair.rebuildIndex(into: database)

    let refCount: Int? = try await database.pool.read { db in
        try Int.fetchOne(db, sql: "SELECT ref_count FROM blobs WHERE hash = ?", arguments: [result.hash])
    }
    #expect(refCount == 1)
}

@Test func repairOnAnEmptyVaultReconstructsNothing() async throws {
    let (_, root) = try makeVault()
    let database = try makeDatabase()
    let repair = RepairVault(vaultRoot: root)
    let report = try await repair.rebuildIndex(into: database)

    #expect(report.reconstructedDocumentCount == 0)
    #expect(report.unreadableBlobCount == 0)
}
