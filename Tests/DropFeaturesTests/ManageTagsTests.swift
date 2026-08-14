import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import GRDB
import Testing

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-tags-test-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

private func insertDocument(_ database: DropIndexDatabase, id: String) async throws {
    try await database.pool.write { db in
        let hash = "hash-\(id)"
        try db.execute(sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, 0, '2026-01-01T00:00:00Z')", arguments: [hash])
        try db.execute(
            sql: "INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source) VALUES (?, ?, ?, ?, 0, '2026-01-01T00:00:00Z', 'drop')",
            arguments: [id, hash, "doc.pdf", "doc.pdf"]
        )
    }
}

@Test func addingATagMakesItRetrievable() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1")
    let tags = ManageTags(database: database)

    try await tags.addTag(documentID: "doc-1", name: "Maison")
    let stored = try await tags.tags(forDocumentID: "doc-1")

    #expect(stored == ["maison"]) // normalisé en minuscules.
}

@Test func addingTheSameTagTwiceDoesNotDuplicateIt() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1")
    let tags = ManageTags(database: database)

    try await tags.addTag(documentID: "doc-1", name: "maison")
    try await tags.addTag(documentID: "doc-1", name: "maison")

    #expect(try await tags.tags(forDocumentID: "doc-1") == ["maison"])
}

@Test func theSameTagCanBeSharedAcrossDocuments() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1")
    try await insertDocument(database, id: "doc-2")
    let tags = ManageTags(database: database)

    try await tags.addTag(documentID: "doc-1", name: "impots")
    try await tags.addTag(documentID: "doc-2", name: "impots")

    #expect(try await tags.tags(forDocumentID: "doc-1") == ["impots"])
    #expect(try await tags.tags(forDocumentID: "doc-2") == ["impots"])

    let tagCount = try await database.pool.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags") ?? -1
    }
    #expect(tagCount == 1) // une seule ligne `tags`, partagée par les deux documents.
}

@Test func removingATagLeavesOtherDocumentsUnaffected() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1")
    try await insertDocument(database, id: "doc-2")
    let tags = ManageTags(database: database)

    try await tags.addTag(documentID: "doc-1", name: "urgent")
    try await tags.addTag(documentID: "doc-2", name: "urgent")

    try await tags.removeTag(documentID: "doc-1", name: "urgent")

    #expect(try await tags.tags(forDocumentID: "doc-1").isEmpty)
    #expect(try await tags.tags(forDocumentID: "doc-2") == ["urgent"])
}

@Test func blankTagNameIsIgnored() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1")
    let tags = ManageTags(database: database)

    try await tags.addTag(documentID: "doc-1", name: "   ")

    #expect(try await tags.tags(forDocumentID: "doc-1").isEmpty)
}
