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
    let documentID = try await ingest.ingest(fileAt: source)

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
