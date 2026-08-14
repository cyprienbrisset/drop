import DropCore
import DropIndex
import DropVault
import Foundation
import GRDB

/// Reconstruction complète de `index.db` depuis `meta.json` et les blobs (§4.3, EF-28) : la
/// garantie de dernier recours du coffre. Déclenchée quand le schéma de la base est illisible —
/// la décision de déclenchement automatique appartient au bootstrap applicatif, pas à ce type.
///
/// Limite assumée : un document est recréé par blob retrouvé. Les regroupements de versions et
/// les analyses (entités, résumé, embeddings) antérieurs sont perdus — cette reconstruction
/// restaure l'accès aux fichiers, pas l'état d'enrichissement, qu'un job de ré-analyse referait.
public struct RepairVault: Sendable {
    public struct Report: Sendable, Equatable {
        public let reconstructedDocumentCount: Int
        public let unreadableBlobCount: Int
    }

    private let vaultRoot: URL
    private let fileSystem: FileSystem

    public init(vaultRoot: URL, fileSystem: FileSystem = LiveFileSystem()) {
        self.vaultRoot = vaultRoot
        self.fileSystem = fileSystem
    }

    public func rebuildIndex(into database: DropIndexDatabase, now: @escaping @Sendable () -> Date = { Date() }) async throws -> Report {
        let blobFiles = try findBlobFiles()
        var reconstructed = 0
        var unreadable = 0
        let fallbackNow = Self.isoString(from: now())

        for blobURL in blobFiles {
            let hash = blobURL.deletingPathExtension().lastPathComponent
            guard let sizeBytes = try? fileSystem.fileSize(at: blobURL) else {
                unreadable += 1
                continue
            }

            let metadataURL = blobURL.deletingPathExtension().appendingPathExtension("json")
            let metadata: BlobMetadata? = (try? fileSystem.read(at: metadataURL))
                .flatMap { try? JSONDecoder().decode(BlobMetadata.self, from: $0) }

            let addedAt = metadata?.addedAt ?? fallbackNow
            let displayName = metadata?.originalFilename ?? hash
            let documentID = UUID().uuidString

            try await database.pool.write { db in
                try db.execute(
                    sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at, ref_count) VALUES (?, ?, ?, 0)",
                    arguments: [hash, sizeBytes, addedAt]
                )
                try db.execute(sql: "UPDATE blobs SET ref_count = ref_count + 1 WHERE hash = ?", arguments: [hash])
                try db.execute(
                    sql: """
                    INSERT INTO documents (
                      id, blob_hash, display_name, original_filename, original_path, size_bytes,
                      added_at, source, doc_type, issuer
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'repair', ?, ?)
                    """,
                    arguments: [
                        documentID, hash, displayName, metadata?.originalFilename ?? displayName,
                        metadata?.originalPath, sizeBytes, addedAt, metadata?.docType, metadata?.issuer,
                    ]
                )
                try db.execute(
                    sql: "INSERT INTO fts_docs (display_name, body, issuer, keywords, document_id) VALUES (?, '', ?, '', ?)",
                    arguments: [displayName, metadata?.issuer ?? "", documentID]
                )
            }
            reconstructed += 1
        }

        return Report(reconstructedDocumentCount: reconstructed, unreadableBlobCount: unreadable)
    }

    /// Parcourt `vault/<préfixe1>/<préfixe2>/*.blob` (§4.3) — la seule structure garantie à
    /// exister indépendamment de tout état de la base.
    private func findBlobFiles() throws -> [URL] {
        let vaultDirectory = vaultRoot.appendingPathComponent("vault")
        guard fileSystem.fileExists(at: vaultDirectory) else { return [] }

        var result: [URL] = []
        for prefix1Directory in try fileSystem.contentsOfDirectory(at: vaultDirectory) {
            guard let prefix2Directories = try? fileSystem.contentsOfDirectory(at: prefix1Directory) else { continue }
            for prefix2Directory in prefix2Directories {
                guard let entries = try? fileSystem.contentsOfDirectory(at: prefix2Directory) else { continue }
                result.append(contentsOf: entries.filter { $0.pathExtension == "blob" })
            }
        }
        return result
    }

    private static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
