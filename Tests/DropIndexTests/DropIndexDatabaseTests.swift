import DropIndex
import Foundation
import GRDB
import Testing

@Test func migratingCreatesAllExpectedTables() throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-index-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    let database = try DropIndexDatabase(path: path)

    let tableNames: Set<String> = try database.pool.read { db in
        try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"))
    }

    let expected = [
        "blobs", "documents", "page_texts", "entities", "tags", "document_tags",
        "fts_docs", "fts_trigram", "jobs", "document_opens", "settings",
    ]
    for table in expected {
        #expect(tableNames.contains(table), "table manquante: \(table)")
    }
}

@Test func insertingDocumentRequiresExistingBlob() throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-index-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    let database = try DropIndexDatabase(path: path)

    try database.pool.write { db in
        try db.execute(
            sql: "INSERT INTO blobs (hash, size_bytes, stored_at) VALUES (?, ?, ?)",
            arguments: ["abc123", 1024, "2026-08-14T08:00:00Z"]
        )
        try db.execute(
            sql: """
            INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: ["doc-1", "abc123", "Facture EDF", "facture.pdf", 1024, "2026-08-14T08:00:00Z", "drop"]
        )
    }

    let count = try database.pool.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
    }
    #expect(count == 1)
}
