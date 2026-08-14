import Foundation
import GRDB

/// Point d'accès unique à `index.db` (§4.4). Un seul écrivain à la fois : `DatabasePool` sérialise
/// les écritures sur une connexion dédiée et autorise des lectures concurrentes via WAL (§4.2 règle 2).
///
/// Chiffrement SQLCipher (ADR-05, DRO-51) : `passphrase` est optionnelle pour ne pas casser les
/// tests et les usages qui ouvrent volontairement une base non chiffrée (ex. `vectors.db`, exclu
/// du chiffrement par exception documentée, §4.3) — en mode Standard, l'appelant doit toujours
/// fournir la clé issue du Keychain (`VaultEncryptionKey.getOrCreate`) pour `index.db`. Le moteur
/// SQLite sous-jacent est SQLCipher que la base soit chiffrée ou non (fork vendorisé de GRDB, voir
/// `Vendor/GRDB.swift`) : une base ouverte sans passphrase reste un fichier SQLite standard.
public struct DropIndexDatabase: Sendable {
    public let pool: DatabasePool

    public init(path: String, passphrase: Data? = nil) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            if let passphrase {
                try db.usePassphrase(passphrase)
            }
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
        migrator.registerMigration("v2_add_due_date") { db in
            try createV2AddDueDate(db)
        }
        return migrator
    }
}
