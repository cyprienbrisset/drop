import DropCore
import DropIndex
import DropVault
import Foundation
import GRDB

/// Cas d'usage : retrait vers la corbeille, restauration, purge à échéance (EF-23, §5.9).
/// Comme `IngestFiles`, seul endroit du code qui manipule `DropVault` et `DropIndex` ensemble.
///
/// Un blob n'est jamais copié dans `trash/` : il reste adressé par son hash dans `vault/` tant
/// qu'au moins un document (actif ou en corbeille, hors rétention dépassée) le référence. Le
/// retrait décrémente `ref_count` (le document n'est plus une référence active) ; la purge, elle,
/// supprime définitivement la ligne `documents` et, seulement si plus aucune ligne ne référence
/// le hash, les fichiers physiques du blob.
public struct ManageTrash: Sendable {
    private let vault: VaultService
    private let database: DropIndexDatabase
    private let clock: DropClock

    public init(vault: VaultService, database: DropIndexDatabase, clock: DropClock = SystemClock()) {
        self.vault = vault
        self.database = database
        self.clock = clock
    }

    /// Retire un document : il devient invisible des recherches actives, restaurable jusqu'à la
    /// purge. Le blob n'est pas touché.
    public func moveToTrash(documentID: String) async throws {
        let now = Self.isoFormatter.string(from: clock.now())

        try await database.pool.write { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT * FROM documents WHERE id = ? AND trashed_at IS NULL", arguments: [documentID]
            ) else {
                throw IngestionError.transactionFailed
            }

            let blobHash: String = row["blob_hash"]
            var fields: [String: String?] = [:]
            for (column, value) in row {
                fields[column] = value.isNull ? nil : value.description
            }

            try db.execute(sql: "UPDATE documents SET trashed_at = ? WHERE id = ?", arguments: [now, documentID])
            try db.execute(
                sql: "UPDATE blobs SET ref_count = MAX(ref_count - 1, 0) WHERE hash = ?", arguments: [blobHash]
            )

            let record = TrashRecord(documentID: documentID, blobHash: blobHash, trashedAt: now, documentFields: fields)
            try self.vault.writeTrashRecord(record)
        }
    }

    /// Restaure un document retiré, tant que la corbeille n'a pas encore été purgée.
    public func restore(documentID: String) async throws {
        try await database.pool.write { db in
            guard let blobHash = try String.fetchOne(
                db, sql: "SELECT blob_hash FROM documents WHERE id = ? AND trashed_at IS NOT NULL", arguments: [documentID]
            ) else {
                throw IngestionError.transactionFailed
            }

            try db.execute(sql: "UPDATE documents SET trashed_at = NULL WHERE id = ?", arguments: [documentID])
            try db.execute(sql: "UPDATE blobs SET ref_count = ref_count + 1 WHERE hash = ?", arguments: [blobHash])
        }
        try? vault.removeTrashRecord(documentID: documentID)
    }

    /// Purge les documents dont la rétention est écoulée (EF-23, défaut 30 jours, configurable
    /// 7-365 — Q-09). Retourne les identifiants purgés.
    @discardableResult
    public func purgeExpired(retentionDays: Int = 30) async throws -> [String] {
        let cutoff = Self.isoFormatter.string(from: clock.now().addingTimeInterval(-Double(retentionDays) * 86400))

        let purgedIDs: [String] = try await database.pool.write { db in
            let expired = try Row.fetchAll(
                db, sql: "SELECT id, blob_hash FROM documents WHERE trashed_at IS NOT NULL AND trashed_at <= ?",
                arguments: [cutoff]
            )

            var purged: [String] = []
            for row in expired {
                let documentID: String = row["id"]
                let blobHash: String = row["blob_hash"]

                try db.execute(sql: "DELETE FROM documents WHERE id = ?", arguments: [documentID])

                let remainingReferences = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM documents WHERE blob_hash = ?", arguments: [blobHash]
                ) ?? 0
                if remainingReferences == 0 {
                    try self.vault.deleteBlobFiles(hash: blobHash)
                    try db.execute(sql: "DELETE FROM blobs WHERE hash = ?", arguments: [blobHash])
                }

                purged.append(documentID)
            }
            return purged
        }

        for documentID in purgedIDs {
            try? vault.removeTrashRecord(documentID: documentID)
        }
        return purgedIDs
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
