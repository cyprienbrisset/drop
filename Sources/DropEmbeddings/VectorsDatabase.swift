import GRDB

/// Point d'accès à `vectors.db` (§4.5), base séparée et non chiffrée (§4.3) : régénérer les
/// vecteurs ne doit jamais toucher l'index métier. La table `chunks` est créée ici ; la table
/// virtuelle `vec_chunks` (extension `sqlite-vec`) est ajoutée en Phase 6 (DRO-43) lors de
/// l'intégration effective du moteur vectoriel.
public struct VectorsDatabase: Sendable {
    public let pool: DatabasePool

    public init(path: String) throws {
        let configuration = Configuration()
        pool = try DatabasePool(path: path, configuration: configuration)
        try Self.migrator.migrate(pool)
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
        return migrator
    }
}
