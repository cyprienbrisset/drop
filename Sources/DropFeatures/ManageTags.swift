import DropCore
import DropIndex
import DropVault
import Foundation
import GRDB

/// Cas d'usage : tags manuels (§5.6, EF-66 — le filtre `#tag` existait déjà côté `QueryParser`
/// sans qu'aucune interface ne permette jamais d'en créer un). Toujours en minuscules, jamais de
/// doublon (`tags.name` est `UNIQUE`, `document_tags` a une clé primaire composite).
public struct ManageTags: Sendable {
    private let database: DropIndexDatabase

    public init(database: DropIndexDatabase) {
        self.database = database
    }

    public func addTag(documentID: String, name: String) async throws {
        let normalized = Self.normalize(name)
        guard !normalized.isEmpty else { return }

        try await database.pool.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO tags (name, kind) VALUES (?, 'user')", arguments: [normalized])
            guard let tagID = try Int64.fetchOne(db, sql: "SELECT id FROM tags WHERE name = ?", arguments: [normalized]) else {
                throw IngestionError.transactionFailed
            }
            try db.execute(
                sql: "INSERT OR IGNORE INTO document_tags (document_id, tag_id) VALUES (?, ?)",
                arguments: [documentID, tagID]
            )
        }
    }

    public func removeTag(documentID: String, name: String) async throws {
        let normalized = Self.normalize(name)
        try await database.pool.write { db in
            try db.execute(
                sql: """
                DELETE FROM document_tags WHERE document_id = ?
                AND tag_id = (SELECT id FROM tags WHERE name = ?)
                """,
                arguments: [documentID, normalized]
            )
        }
    }

    public func tags(forDocumentID documentID: String) async throws -> [String] {
        try await database.pool.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT tags.name FROM tags
                JOIN document_tags ON document_tags.tag_id = tags.id
                WHERE document_tags.document_id = ?
                ORDER BY tags.name
                """,
                arguments: [documentID]
            )
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
