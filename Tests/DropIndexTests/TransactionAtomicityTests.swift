import DropIndex
import Foundation
import GRDB
import Testing

/// §8.4, point de coupure « au milieu de la transaction » : si une instruction échoue avant le
/// commit, GRDB annule l'ensemble — aucune écriture partielle. C'est la garantie sur laquelle
/// repose `DropFeatures.IngestFiles` (I2 : jamais de document sans blob correspondant).
@Test func aFailingStatementRollsBackEveryPriorWriteInTheSameTransaction() throws {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-atomicity-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let database = try DropIndexDatabase(path: dbPath)

    #expect(throws: (any Error).self) {
        try database.pool.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, ?, ?)",
                arguments: ["deadbeef", 42, "2026-01-01T00:00:00Z"]
            )
            try db.execute(sql: "UPDATE blobs SET ref_count = ref_count + 1 WHERE hash = ?", arguments: ["deadbeef"])

            // Violation délibérée : `documents.blob_hash` référence une clé de `blobs` qui,
            // dans ce scénario, n'a pas la contrainte NOT NULL respectée sur `display_name`.
            try db.execute(
                sql: "INSERT INTO documents (id, blob_hash, original_filename, size_bytes, added_at, source) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: ["doc-1", "deadbeef", "facture.pdf", 42, "2026-01-01T00:00:00Z", "drop"]
                // `display_name` omis alors qu'il est NOT NULL : l'instruction échoue.
            )
        }
    }

    let (blobCount, documentCount): (Int, Int) = try database.pool.read { db in
        let blobCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM blobs") ?? -1
        let documentCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? -1
        return (blobCount, documentCount)
    }

    #expect(blobCount == 0) // le INSERT + UPDATE précédents ont été annulés avec le reste.
    #expect(documentCount == 0)
}
