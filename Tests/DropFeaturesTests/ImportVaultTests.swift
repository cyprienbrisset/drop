import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import GRDB
import Testing

private func makeVault() throws -> (VaultService, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drop-import-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (VaultService(vaultRoot: root), root)
}

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-import-index-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

private func writeSourceFile(named name: String, contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func importingAFreshVaultAddsOneDocumentPerBlobFound() async throws {
    let (sourceVault, sourceRoot) = try makeVault()
    let fileA = try writeSourceFile(named: "facture-edf.pdf", contents: "facture edf juillet")
    let fileB = try writeSourceFile(named: "contrat.pdf", contents: "contrat assurance habitation")
    _ = try sourceVault.writeBlob(fromFileAt: fileA, originalPath: fileA.path)
    _ = try sourceVault.writeBlob(fromFileAt: fileB, originalPath: fileB.path)

    let (destVault, destRoot) = try makeVault()
    let destDatabase = try makeDatabase()

    let importer = ImportVault(vault: destVault, database: destDatabase)
    let report = try await importer.importVault(from: sourceRoot)

    #expect(report.importedDocumentIDs.count == 2)
    #expect(report.skippedAlreadyPresentCount == 0)

    let displayNames: [String] = try await destDatabase.pool.read { db in
        try String.fetchAll(db, sql: "SELECT display_name FROM documents ORDER BY display_name")
    }
    #expect(displayNames.contains { $0.hasSuffix("contrat.pdf") })
    #expect(displayNames.contains { $0.hasSuffix("facture-edf.pdf") })

    for documentID in report.importedDocumentIDs {
        let blobHash: String? = try await destDatabase.pool.read { db in
            try String.fetchOne(db, sql: "SELECT blob_hash FROM documents WHERE id = ?", arguments: [documentID])
        }
        let hash = try #require(blobHash)
        let (blobURL, _) = destVault.paths(forHash: hash)
        #expect(FileManager.default.fileExists(atPath: blobURL.path))
    }

    _ = destRoot // keep root alive for FileManager checks above
}

@Test func importingBlobsAlreadyPresentInTheDestinationVaultAreSkippedWithoutDuplicating() async throws {
    let (sourceVault, sourceRoot) = try makeVault()
    let sharedFile = try writeSourceFile(named: "releve.pdf", contents: "relevé bancaire janvier")
    let sharedResult = try sourceVault.writeBlob(fromFileAt: sharedFile, originalPath: sharedFile.path)

    let (destVault, _) = try makeVault()
    let destDatabase = try makeDatabase()
    // Le même contenu est déjà connu du coffre de destination (même hash, EF-05).
    _ = try destVault.writeBlob(fromFileAt: sharedFile, originalPath: sharedFile.path)
    try await destDatabase.pool.write { db in
        try db.execute(
            sql: "INSERT INTO blobs (hash, size_bytes, stored_at, ref_count) VALUES (?, ?, ?, 1)",
            arguments: [sharedResult.hash, sharedResult.sizeBytes, "2026-01-01T00:00:00Z"]
        )
    }

    let importer = ImportVault(vault: destVault, database: destDatabase)
    let report = try await importer.importVault(from: sourceRoot)

    #expect(report.importedDocumentIDs.isEmpty)
    #expect(report.skippedAlreadyPresentCount == 1)

    let documentCount = try await destDatabase.pool.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
    }
    #expect(documentCount == 0)
}

@Test func importingFromAFolderThatIsNotARealVaultThrowsNotAVault() async throws {
    let notAVault = FileManager.default.temporaryDirectory.appendingPathComponent("drop-not-a-vault-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: notAVault, withIntermediateDirectories: true)

    let (destVault, _) = try makeVault()
    let destDatabase = try makeDatabase()
    let importer = ImportVault(vault: destVault, database: destDatabase)

    await #expect(throws: ImportVaultError.notAVault) {
        _ = try await importer.importVault(from: notAVault)
    }
}
