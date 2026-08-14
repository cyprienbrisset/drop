import DropCore
import DropIndex
import DropVault
import Foundation
import GRDB

public enum ImportVaultError: Error, Sendable, Equatable {
    case notAVault
}

/// Import assisté d'un coffre existant (Q-08, décision V2 : « un vrai import est un chantier
/// V2 » — la V1 documente une simple copie manuelle). Contrairement à `RepairVault`, qui
/// reconstruit un coffre entier depuis zéro, celui-ci fusionne dans un coffre déjà actif : ne
/// recrée jamais un document pour un blob déjà connu (déduplication par hash, comme toute
/// écriture de blob, EF-05) — jamais de doublon en important deux fois le même coffre source, ou
/// un coffre qui partage des documents avec celui-ci.
public struct ImportVault: Sendable {
    public struct Report: Sendable, Equatable {
        public let importedDocumentIDs: [String]
        public let skippedAlreadyPresentCount: Int
    }

    private let vault: VaultService
    private let database: DropIndexDatabase

    public init(vault: VaultService, database: DropIndexDatabase) {
        self.vault = vault
        self.database = database
    }

    public func importVault(from sourceVaultRoot: URL) async throws -> Report {
        let sourceBlobsDirectory = sourceVaultRoot.appendingPathComponent("vault")
        guard FileManager.default.fileExists(atPath: sourceBlobsDirectory.path) else {
            throw ImportVaultError.notAVault
        }

        var importedDocumentIDs: [String] = []
        var skipped = 0

        for blobFileURL in try Self.findBlobFiles(in: sourceBlobsDirectory) {
            let hash = blobFileURL.deletingPathExtension().lastPathComponent

            let alreadyKnown = try await database.pool.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM blobs WHERE hash = ?", arguments: [hash]) ?? 0
            } > 0
            guard !alreadyKnown else {
                skipped += 1
                continue
            }

            guard let sourceData = try? Data(contentsOf: blobFileURL) else {
                skipped += 1
                continue
            }

            let (destBlobURL, destMetadataURL) = vault.paths(forHash: hash)
            try FileManager.default.createDirectory(at: destBlobURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Jamais de réécriture d'un blob existant (I4) : on vient de vérifier son absence.
            try sourceData.write(to: destBlobURL)

            let metadataURL = blobFileURL.deletingPathExtension().appendingPathExtension("json")
            let metadata: BlobMetadata? = (try? Data(contentsOf: metadataURL)).flatMap { try? JSONDecoder().decode(BlobMetadata.self, from: $0) }
            if let metadataData = try? JSONEncoder().encode(metadata) {
                try? metadataData.write(to: destMetadataURL)
            }

            let sizeBytes = Int64(sourceData.count)
            let addedAt = metadata?.addedAt ?? Self.isoString(from: Date())
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
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'import', ?, ?)
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
            importedDocumentIDs.append(documentID)
        }

        return Report(importedDocumentIDs: importedDocumentIDs, skippedAlreadyPresentCount: skipped)
    }

    /// Parcourt `vault/<préfixe1>/<préfixe2>/*.blob` du coffre source (§4.3) — toujours sur le
    /// vrai système de fichiers : le coffre source n'est jamais celui, potentiellement virtualisé
    /// en test, de `VaultService` lui-même.
    private static func findBlobFiles(in vaultDirectory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []
        guard let prefix1Directories = try? fileManager.contentsOfDirectory(at: vaultDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        for prefix1 in prefix1Directories {
            guard let prefix2Directories = try? fileManager.contentsOfDirectory(at: prefix1, includingPropertiesForKeys: nil) else { continue }
            for prefix2 in prefix2Directories {
                guard let entries = try? fileManager.contentsOfDirectory(at: prefix2, includingPropertiesForKeys: nil) else { continue }
                result.append(contentsOf: entries.filter { $0.pathExtension == "blob" })
            }
        }
        return result
    }

    private static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
