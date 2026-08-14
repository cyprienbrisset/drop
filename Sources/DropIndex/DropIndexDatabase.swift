import GRDB

/// Point d'accès unique à `index.db` (§4.4). Un seul écrivain à la fois : `DatabasePool` sérialise
/// les écritures sur une connexion dédiée et autorise des lectures concurrentes via WAL (§4.2 règle 2).
/// Le chiffrement SQLCipher (ADR-05) sera activé en Phase 8 (DRO-51) par substitution de la
/// bibliothèque SQLite sous-jacente, sans changement de cette façade ni des DAO.
public struct DropIndexDatabase: Sendable {
    public let pool: DatabasePool

    public init(path: String) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        pool = try DatabasePool(path: path, configuration: configuration)
        try Self.migrator.migrate(pool)
    }

    /// Migrations GRDB numérotées (§4.6) : jamais rétroactives, jamais modifiées après publication.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_schema") { db in
            try createV1Schema(db)
        }
        return migrator
    }
}
