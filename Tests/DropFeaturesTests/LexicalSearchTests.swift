import DropCore
import DropFeatures
import DropIndex
import DropSearch
import DropVault
import Foundation
import Testing

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-search-test-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

@Test func lexicalSearchFindsDocumentByDisplayName() async throws {
    let fileSystem = InMemoryFileSystem()
    let vault = VaultService(vaultRoot: URL(fileURLWithPath: "/vault-root"), fileSystem: fileSystem)
    let database = try makeDatabase()

    // Nom à espaces plutôt qu'à tirets : le tokenizer FTS5 (`tokenchars '-_@.'`, §4.4) garde les
    // tirets à l'intérieur d'un token, préservant des références comme "FA-2024-001" — un nom de
    // fichier à tirets devient donc un seul token insécable, non prévu pour ce test-ci.
    let sourceA = URL(fileURLWithPath: "/incoming/facture edf juillet.pdf")
    let sourceB = URL(fileURLWithPath: "/incoming/contrat location.pdf")
    fileSystem.seed(sourceA.path, contents: Data("A".utf8))
    fileSystem.seed(sourceB.path, contents: Data("B".utf8))

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: sourceA) else {
        Issue.record("expected a created document"); return
    }
    _ = try await ingest.ingest(fileAt: sourceB)

    var query = ParsedQuery()
    query.freeText = "EDF"
    let generator = LexicalCandidateGenerator(database: database)
    let results = try await generator.candidates(for: query, limit: 10)

    #expect(results.map(\.documentID) == [documentID])
}

@Test func lexicalSearchExcludesTrashedDocuments() async throws {
    let fileSystem = InMemoryFileSystem()
    let vault = VaultService(vaultRoot: URL(fileURLWithPath: "/vault-root"), fileSystem: fileSystem)
    let database = try makeDatabase()
    let source = URL(fileURLWithPath: "/incoming/facture edf.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: source) else {
        Issue.record("expected a created document"); return
    }

    let trash = ManageTrash(vault: vault, database: database)
    try await trash.moveToTrash(documentID: documentID)

    var query = ParsedQuery()
    query.freeText = "EDF"
    let generator = LexicalCandidateGenerator(database: database)
    let results = try await generator.candidates(for: query, limit: 10)

    #expect(results.isEmpty)
}

@Test func trigramSearchToleratesATypo() async throws {
    let fileSystem = InMemoryFileSystem()
    let vault = VaultService(vaultRoot: URL(fileURLWithPath: "/vault-root"), fileSystem: fileSystem)
    let database = try makeDatabase()
    let source = URL(fileURLWithPath: "/incoming/facture-electricite.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: source) else {
        Issue.record("expected a created document"); return
    }

    var query = ParsedQuery()
    query.freeText = "electricit" // radical partiel, sans le lexical exact.
    let generator = TrigramCandidateGenerator(database: database)
    let results = try await generator.candidates(for: query, limit: 10)

    #expect(results.map(\.documentID) == [documentID])
}

@Test func purgingExpiredTrashRemovesFtsEntries() async throws {
    let fileSystem = InMemoryFileSystem()
    let vault = VaultService(vaultRoot: URL(fileURLWithPath: "/vault-root"), fileSystem: fileSystem)
    let database = try makeDatabase()
    let source = URL(fileURLWithPath: "/incoming/facture edf.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let farPast = Date(timeIntervalSince1970: 0)
    let ingest = IngestFiles(vault: vault, database: database, clock: FixedClock(date: farPast), sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: source) else {
        Issue.record("expected a created document"); return
    }

    var query = ParsedQuery()
    query.freeText = "EDF"
    let generator = LexicalCandidateGenerator(database: database)

    let beforePurge = try await generator.candidates(for: query, limit: 10)
    #expect(beforePurge.map(\.documentID) == [documentID]) // trouvable avant la purge...

    let trash = ManageTrash(vault: vault, database: database, clock: FixedClock(date: farPast))
    try await trash.moveToTrash(documentID: documentID)
    _ = try await trash.purgeExpired(retentionDays: 30)

    let afterPurge = try await generator.candidates(for: query, limit: 10)
    #expect(afterPurge.isEmpty) // ...plus du tout après (ligne fts_docs réellement supprimée).
}
