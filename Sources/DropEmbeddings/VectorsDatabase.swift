import CSQLiteVec
import GRDB

public enum VectorsDatabaseError: Error, Sendable {
    case extensionRegistrationFailed(String)
}

/// Point d'accès à `vectors.db` (§4.5), base séparée et non chiffrée (§4.3) : régénérer les
/// vecteurs ne doit jamais toucher l'index métier. `sqlite-vec` (`vec0`) est enregistré sur
/// chaque connexion via `sqlite3_vec_init`, appelé statiquement (§4.1 — pas d'extension chargée
/// dynamiquement, le module est lié directement dans le binaire).
public struct VectorsDatabase: Sendable {
    public let pool: DatabasePool

    public init(path: String) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try Self.registerSQLiteVec(on: db)
        }
        pool = try DatabasePool(path: path, configuration: configuration)
        try Self.migrator.migrate(pool)
    }

    private static func registerSQLiteVec(on db: Database) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_vec_init(db.sqliteConnection, &errorMessage, nil)
        guard code == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "code \(code)"
            throw VectorsDatabaseError.extensionRegistrationFailed(message)
        }
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_chunks") { db in
            try db.execute(sql: """
                CREATE TABLE chunks (
                  id            INTEGER PRIMARY KEY AUTOINCREMENT,
                  document_id   TEXT    NOT NULL,
                  page_from     INTEGER NOT NULL,
                  page_to       INTEGER NOT NULL,
                  char_from     INTEGER NOT NULL,
                  char_to       INTEGER NOT NULL,
                  token_count   INTEGER NOT NULL,
                  model_version TEXT    NOT NULL,
                  created_at    TEXT    NOT NULL
                );
                """)
            try db.execute(sql: "CREATE INDEX idx_chunks_doc ON chunks(document_id)")
            try db.execute(sql: "CREATE INDEX idx_chunks_model ON chunks(model_version)")
        }
        migrator.registerMigration("v2_create_vec_chunks") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE vec_chunks USING vec0(
                  chunk_id INTEGER PRIMARY KEY,
                  embedding int8[512]
                );
                """)
        }
        return migrator
    }
}
