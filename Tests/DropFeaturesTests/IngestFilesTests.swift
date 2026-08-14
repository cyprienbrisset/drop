import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import GRDB
import Testing

@Test func ingestingAFileCreatesBlobAndDocumentInOneTransaction() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture-edf.pdf")
    fileSystem.seed(source.path, contents: Data("facture EDF juillet".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-ingest-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let database = try DropIndexDatabase(path: dbPath)

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: source) else {
        Issue.record("expected a newly created document")
        return
    }

    let (blobCount, refCount, documentCount): (Int, Int, Int) = try await database.pool.read { db in
        let blobCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM blobs") ?? 0
        let refCount = try Int.fetchOne(db, sql: "SELECT ref_count FROM blobs LIMIT 1") ?? 0
        let documentCount = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM documents WHERE id = ?", arguments: [documentID]
        ) ?? 0
        return (blobCount, refCount, documentCount)
    }

    #expect(blobCount == 1)
    #expect(refCount == 1)
    #expect(documentCount == 1) // I2 : le document existe, et son blob existe déjà sur disque.
}

@Test func ingestingTwoFilesWithIdenticalContentSharesOneBlob() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let sourceA = URL(fileURLWithPath: "/incoming/facture.pdf")
    let sourceB = URL(fileURLWithPath: "/incoming/facture-copie.pdf")
    fileSystem.seed(sourceA.path, contents: Data("même contenu".utf8))
    fileSystem.seed(sourceB.path, contents: Data("même contenu".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-ingest-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let database = try DropIndexDatabase(path: dbPath)

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    _ = try await ingest.ingest(fileAt: sourceA)
    _ = try await ingest.ingest(fileAt: sourceB)

    let (blobCount, refCount, documentCount): (Int, Int, Int) = try await database.pool.read { db in
        let blobCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM blobs") ?? 0
        let refCount = try Int.fetchOne(db, sql: "SELECT ref_count FROM blobs LIMIT 1") ?? 0
        let documentCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
        return (blobCount, refCount, documentCount)
    }

    #expect(blobCount == 1) // EF-05 : un seul blob physique.
    #expect(refCount == 2) // ...référencé par deux documents.
    #expect(documentCount == 2)
}

@Test func ingestingAFileTooLargeThrowsAndTouchesNeitherBlobNorDatabase() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/huge.bin")
    fileSystem.seed(source.path, contents: Data(repeating: 0, count: 4096))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, maxFileSizeBytes: 1024)
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-ingest-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let database = try DropIndexDatabase(path: dbPath)

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())

    await #expect(throws: IngestionError.tooLarge) {
        try await ingest.ingest(fileAt: source)
    }

    let documentCount = try await database.pool.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
    }
    #expect(documentCount == 0)
}

@Test func reingestingTheExactSameFileIsSkippedAsADuplicate() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("contenu identique".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-ingest-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let database = try DropIndexDatabase(path: dbPath)
    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())

    guard case .created(let firstID) = try await ingest.ingest(fileAt: source) else {
        Issue.record("expected first ingest to create a document")
        return
    }
    let second = try await ingest.ingest(fileAt: source)

    guard case .exactDuplicate(let existingID) = second else {
        Issue.record("expected the second ingest of an identical file+name to be a duplicate")
        return
    }
    #expect(existingID == firstID)

    let (documentCount, refCount): (Int, Int) = try await database.pool.read { db in
        let documentCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
        let refCount = try Int.fetchOne(db, sql: "SELECT ref_count FROM blobs LIMIT 1") ?? 0
        return (documentCount, refCount)
    }
    #expect(documentCount == 1) // EF-05 : doublon exact, non ajouté.
    #expect(refCount == 1)
}

@Test func ingestingASimilarlyNamedFileProposesASharedVersionGroup() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let sourceV1 = URL(fileURLWithPath: "/incoming/rapport-annuel-v1.pdf")
    let sourceV2 = URL(fileURLWithPath: "/incoming/rapport-annuel-v2.pdf")
    fileSystem.seed(sourceV1.path, contents: Data(repeating: 1, count: 10_000))
    fileSystem.seed(sourceV2.path, contents: Data(repeating: 2, count: 11_000)) // même radical, +10 % de taille, contenu différent → hash différent

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-ingest-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let database = try DropIndexDatabase(path: dbPath)
    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())

    guard case .created(let firstID) = try await ingest.ingest(fileAt: sourceV1) else {
        Issue.record("expected first ingest to create a document")
        return
    }
    guard case .created(let secondID) = try await ingest.ingest(fileAt: sourceV2) else {
        Issue.record("expected second ingest to create a document")
        return
    }

    let rows: [(id: String, groupID: String?, versionNumber: Int)] = try await database.pool.read { db in
        try Row.fetchAll(db, sql: "SELECT id, version_group_id, version_number FROM documents ORDER BY added_at")
            .map { ($0["id"], $0["version_group_id"], $0["version_number"]) }
    }

    let first = rows.first { $0.id == firstID }
    let second = rows.first { $0.id == secondID }
    #expect(first?.groupID != nil)
    #expect(first?.groupID == second?.groupID) // EF-06 : proposition de groupe partagé.
    #expect(second?.versionNumber ?? 0 > first?.versionNumber ?? 0)
}
