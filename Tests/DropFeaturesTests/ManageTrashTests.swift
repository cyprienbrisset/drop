import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import GRDB
import Testing

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-trash-test-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

@Test func movingADocumentToTrashHidesItButKeepsTheBlob() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let database = try makeDatabase()
    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: source) else {
        Issue.record("expected a created document"); return
    }

    let trash = ManageTrash(vault: vault, database: database)
    try await trash.moveToTrash(documentID: documentID)

    let (trashedAtIsSet, refCount, blobHash): (Bool, Int, String) = try await database.pool.read { db in
        let trashedAt: String? = try String.fetchOne(db, sql: "SELECT trashed_at FROM documents WHERE id = ?", arguments: [documentID])
        let refCount = try Int.fetchOne(db, sql: "SELECT ref_count FROM blobs LIMIT 1") ?? -1
        let blobHash = try String.fetchOne(db, sql: "SELECT blob_hash FROM documents WHERE id = ?", arguments: [documentID]) ?? ""
        return (trashedAt != nil, refCount, blobHash)
    }

    #expect(trashedAtIsSet)
    #expect(refCount == 0)
    let (blobURL, _) = vault.paths(forHash: blobHash)
    #expect(fileSystem.fileExists(at: blobURL)) // le blob reste en place, seul le compteur baisse.
}

@Test func restoringATrashedDocumentMakesItActiveAgain() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let database = try makeDatabase()
    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: source) else {
        Issue.record("expected a created document"); return
    }

    let trash = ManageTrash(vault: vault, database: database)
    try await trash.moveToTrash(documentID: documentID)
    try await trash.restore(documentID: documentID)

    let (trashedAtIsSet, refCount): (Bool, Int) = try await database.pool.read { db in
        let trashedAt: String? = try String.fetchOne(db, sql: "SELECT trashed_at FROM documents WHERE id = ?", arguments: [documentID])
        let refCount = try Int.fetchOne(db, sql: "SELECT ref_count FROM blobs LIMIT 1") ?? -1
        return (trashedAt != nil, refCount)
    }

    #expect(!trashedAtIsSet)
    #expect(refCount == 1)
}

@Test func listTrashedReflectsCurrentTrashStateMostRecentFirst() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let sourceA = URL(fileURLWithPath: "/incoming/a.pdf")
    let sourceB = URL(fileURLWithPath: "/incoming/b.pdf")
    fileSystem.seed(sourceA.path, contents: Data("contenu a".utf8))
    fileSystem.seed(sourceB.path, contents: Data("contenu b".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let database = try makeDatabase()
    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentA) = try await ingest.ingest(fileAt: sourceA),
          case .created(let documentB) = try await ingest.ingest(fileAt: sourceB)
    else {
        Issue.record("expected two created documents"); return
    }

    // Horloges distinctes : deux retraits à la même seconde donneraient un ordre de tri ambigu.
    let trashA = ManageTrash(vault: vault, database: database, clock: FixedClock(date: Date(timeIntervalSince1970: 1_000)))
    let trashB = ManageTrash(vault: vault, database: database, clock: FixedClock(date: Date(timeIntervalSince1970: 2_000)))
    let trash = ManageTrash(vault: vault, database: database)
    #expect(try await trash.listTrashed().isEmpty)

    try await trashA.moveToTrash(documentID: documentA)
    try await trashB.moveToTrash(documentID: documentB)

    let trashed = try await trash.listTrashed()
    #expect(trashed.map(\.id) == [documentB, documentA]) // le plus récemment retiré en premier.

    try await trash.restore(documentID: documentA)
    let afterRestore = try await trash.listTrashed()
    #expect(afterRestore.map(\.id) == [documentB])
}

@Test func purgingExpiredTrashDeletesTheDocumentAndUnreferencedBlob() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let database = try makeDatabase()
    let farPast = Date(timeIntervalSince1970: 0)
    let ingest = IngestFiles(vault: vault, database: database, clock: FixedClock(date: farPast), sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: source) else {
        Issue.record("expected a created document"); return
    }

    let trash = ManageTrash(vault: vault, database: database, clock: FixedClock(date: farPast))
    try await trash.moveToTrash(documentID: documentID)

    // Purge vue depuis "aujourd'hui" : le document trashed_at (epoch 0) a largement dépassé 30 jours.
    let trashToday = ManageTrash(vault: vault, database: database)
    let purgedIDs = try await trashToday.purgeExpired(retentionDays: 30)

    #expect(purgedIDs == [documentID])

    let (documentCount, blobCount): (Int, Int) = try await database.pool.read { db in
        let documentCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? -1
        let blobCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM blobs") ?? -1
        return (documentCount, blobCount)
    }
    #expect(documentCount == 0)
    #expect(blobCount == 0) // plus aucune référence : le blob physique et sa ligne sont purgés.
}

@Test func purgingExpiredTrashKeepsTheBlobIfAnotherDocumentStillReferencesIt() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let sourceA = URL(fileURLWithPath: "/incoming/facture.pdf")
    let sourceB = URL(fileURLWithPath: "/incoming/facture-copie.pdf")
    fileSystem.seed(sourceA.path, contents: Data("contenu partagé".utf8))
    fileSystem.seed(sourceB.path, contents: Data("contenu partagé".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let database = try makeDatabase()
    let farPast = Date(timeIntervalSince1970: 0)
    let ingest = IngestFiles(vault: vault, database: database, clock: FixedClock(date: farPast), sleeper: ImmediateSleeper())
    guard case .created(let trashedID) = try await ingest.ingest(fileAt: sourceA) else {
        Issue.record("expected a created document"); return
    }
    guard case .created = try await ingest.ingest(fileAt: sourceB) else {
        Issue.record("expected a created document"); return
    }

    let trash = ManageTrash(vault: vault, database: database, clock: FixedClock(date: farPast))
    try await trash.moveToTrash(documentID: trashedID)

    let trashToday = ManageTrash(vault: vault, database: database)
    let purgedIDs = try await trashToday.purgeExpired(retentionDays: 30)
    #expect(purgedIDs == [trashedID])

    let (documentCount, blobCount): (Int, Int) = try await database.pool.read { db in
        let documentCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? -1
        let blobCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM blobs") ?? -1
        return (documentCount, blobCount)
    }
    #expect(documentCount == 1) // le second document, jamais trashé, subsiste.
    #expect(blobCount == 1) // ...donc le blob partagé n'est pas purgé.
}

struct FixedClock: DropClock {
    let date: Date
    func now() -> Date { date }
}
