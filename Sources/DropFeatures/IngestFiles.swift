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
/// Résultat de l'ingestion (EF-05) : soit un nouveau document, soit un doublon exact déjà
/// présent (même hash, même nom) — dans ce second cas, rien n'est ajouté.
public enum IngestOutcome: Sendable, Equatable {
    case created(documentID: String)
    case exactDuplicate(existingDocumentID: String)
}

public struct IngestFiles: Sendable {
    private let vault: VaultService
    private let database: DropIndexDatabase
    private let clock: DropClock
    private let sleeper: Sleeper
    private let stabilityWindowSeconds: Double

    public init(
        vault: VaultService, database: DropIndexDatabase, clock: DropClock = SystemClock(),
        sleeper: Sleeper = SystemSleeper(), stabilityWindowSeconds: Double = 2
    ) {
        self.vault = vault
        self.database = database
        self.clock = clock
        self.sleeper = sleeper
        self.stabilityWindowSeconds = stabilityWindowSeconds
    }

    /// Ingère un fichier et retourne son sort (EF-05) : nouveau document, ou doublon exact.
    ///
    /// Note de portée : la coordination `NSFileCoordinator` (§5.1 étape 1) n'est pas encore
    /// câblée ici — elle dépend du contexte d'invocation (glisser-déposer, dossier surveillé...)
    /// et sera ajoutée avec ces intégrations. La vérification de stabilité EF-11 (étape 2), elle,
    /// est appliquée ici : deux relevés taille+date espacés de \(stabilityWindowSeconds) s.
    @discardableResult
    public func ingest(fileAt sourceURL: URL, source: String = "drop") async throws -> IngestOutcome {
        let before = try vault.stabilitySnapshot(fileAt: sourceURL)
        try await sleeper.sleep(seconds: stabilityWindowSeconds)
        let after = try vault.stabilitySnapshot(fileAt: sourceURL)
        guard before == after else { throw IngestionError.lockedOrUnstable }

        let blob = try vault.writeBlob(fromFileAt: sourceURL, originalPath: sourceURL.path)

        let documentID = UUID().uuidString
        let now = Self.isoFormatter.string(from: clock.now())
        let displayName = sourceURL.lastPathComponent
        let originalFilename = sourceURL.lastPathComponent

        let outcome: IngestOutcome
        do {
            outcome = try await database.pool.write { db -> IngestOutcome in
                // EF-05, cas « même nom » : doublon exact déjà présent, on n'ajoute rien.
                if let existingID = try String.fetchOne(
                    db,
                    sql: """
                    SELECT id FROM documents
                    WHERE blob_hash = ? AND original_filename = ? AND trashed_at IS NULL
                    LIMIT 1
                    """,
                    arguments: [blob.hash, originalFilename]
                ) {
                    return .exactDuplicate(existingDocumentID: existingID)
                }

                try db.execute(
                    sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, ?, ?)",
                    arguments: [blob.hash, blob.sizeBytes, now]
                )
                try db.execute(
                    sql: "UPDATE blobs SET ref_count = ref_count + 1 WHERE hash = ?",
                    arguments: [blob.hash]
                )

                // EF-06 : proposition de version_group_id — jamais automatique au sens fusion,
                // seule l'étiquette de groupe est posée pour affichage ultérieur (EX-03).
                let (versionGroupID, versionNumber) = try detectVersionGroup(
                    db, originalFilename: originalFilename, sizeBytes: blob.sizeBytes
                )

                try db.execute(
                    sql: """
                    INSERT INTO documents
                        (id, blob_hash, display_name, original_filename, original_path, size_bytes,
                         added_at, source, version_group_id, version_number)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        documentID, blob.hash, displayName, originalFilename,
                        sourceURL.path, blob.sizeBytes, now, source, versionGroupID, versionNumber,
                    ]
                )

                return .created(documentID: documentID)
            }
        } catch let ingestionError as IngestionError {
            throw ingestionError
        } catch {
            // I5 : la transaction a échoué après l'écriture du blob — celui-ci devient orphelin
            // (ref_count resterait à 0), bénin et éliminé par le nettoyage au démarrage (§5.9, I3).
            throw IngestionError.transactionFailed
        }

        return outcome
    }

    /// Recherche, parmi les documents existants, un radical de nom proche et une taille voisine
    /// (§5.3.4/EF-06). Si un candidat n'a pas encore de groupe, on lui en attribue un — c'est la
    /// seule façon pour que la fiche des deux documents affiche un jour le même groupe (EX-03).
    /// Retourne le groupe à utiliser pour le nouveau document, ou `nil` si aucun candidat trouvé.
    private func detectVersionGroup(
        _ db: Database, originalFilename: String, sizeBytes: Int64
    ) throws -> (groupID: String?, versionNumber: Int) {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, original_filename, size_bytes, version_group_id, version_number
            FROM documents WHERE trashed_at IS NULL
            """
        )
        var bestCandidateID: String?
        var bestGroupID: String?
        var bestVersionNumber = 0

        for row in rows {
            let candidateName: String = row["original_filename"]
            let candidateSize: Int64 = row["size_bytes"]
            guard VersionDetection.isLikelyVersion(
                nameA: originalFilename, sizeA: sizeBytes, nameB: candidateName, sizeB: candidateSize
            ) else { continue }

            let candidateVersionNumber: Int = row["version_number"]
            if candidateVersionNumber > bestVersionNumber {
                bestCandidateID = row["id"]
                bestGroupID = row["version_group_id"]
                bestVersionNumber = candidateVersionNumber
            }
        }

        guard let candidateID = bestCandidateID else { return (nil, 1) }

        if let groupID = bestGroupID {
            return (groupID, bestVersionNumber + 1)
        }

        // Le candidat n'appartenait à aucun groupe : on lui en crée un rétroactivement.
        let newGroupID = UUID().uuidString
        try db.execute(
            sql: "UPDATE documents SET version_group_id = ? WHERE id = ?", arguments: [newGroupID, candidateID]
        )
        return (newGroupID, bestVersionNumber + 1)
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
