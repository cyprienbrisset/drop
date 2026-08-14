import DropCore
import DropIndex
import DropVault
import Foundation
import GRDB

/// Cas d'usage : ingestion d'un ou plusieurs fichiers. Seul endroit du code où `DropVault` et
/// `DropIndex` sont manipulés ensemble (§4.2 règle 1) — la cohérence blob ↔ base est orchestrée ici.
///
/// Séquence §5.1 étapes 8-9 : une seule transaction SQLite (`INSERT OR IGNORE` sur `blobs`,
/// incrément de `ref_count`, `INSERT` dans `documents`). **C'est ici, et seulement ici, que le
/// document existe** (I2 : une entrée `documents` sans blob correspondant est impossible, car le
/// blob est déjà sur disque — écrit par `VaultService.writeBlob` — avant que cette transaction
/// ne s'ouvre).
public struct IngestFiles: Sendable {
    private let vault: VaultService
    private let database: DropIndexDatabase
    private let clock: DropClock

    public init(vault: VaultService, database: DropIndexDatabase, clock: DropClock = SystemClock()) {
        self.vault = vault
        self.database = database
        self.clock = clock
    }

    /// Ingère un fichier et retourne l'identifiant du document créé.
    @discardableResult
    public func ingest(fileAt sourceURL: URL, source: String = "drop") throws -> String {
        // Étapes 1-2 (coordination, stabilité EF-11) sont à la charge de l'appelant : elles
        // dépendent du contexte d'invocation (glisser-déposer, dossier surveillé...) et ne sont
        // pas encore implémentées ici (suivi séparé).
        let blob = try vault.writeBlob(fromFileAt: sourceURL, originalPath: sourceURL.path)

        let documentID = UUID().uuidString
        let now = Self.isoFormatter.string(from: clock.now())
        let displayName = sourceURL.lastPathComponent

        do {
            try database.pool.write { db in
                try db.execute(
                    sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, ?, ?)",
                    arguments: [blob.hash, blob.sizeBytes, now]
                )
                try db.execute(
                    sql: "UPDATE blobs SET ref_count = ref_count + 1 WHERE hash = ?",
                    arguments: [blob.hash]
                )
                try db.execute(
                    sql: """
                    INSERT INTO documents
                        (id, blob_hash, display_name, original_filename, original_path, size_bytes, added_at, source)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        documentID, blob.hash, displayName, sourceURL.lastPathComponent,
                        sourceURL.path, blob.sizeBytes, now, source,
                    ]
                )
            }
        } catch {
            // I5 : la transaction a échoué après l'écriture du blob — celui-ci devient orphelin
            // (ref_count resterait à 0), bénin et éliminé par le nettoyage au démarrage (§5.9, I3).
            throw IngestionError.transactionFailed
        }

        return documentID
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
