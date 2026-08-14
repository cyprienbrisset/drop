import DropCore
import DropIndex
import DropVault
import Foundation
import GRDB

/// Budget disque affiché en permanence dans les préférences (EF-26) : taille du coffre, économie
/// réalisée par déduplication, taille de l'index, taille des vecteurs.
public struct VaultBudget: Sendable, Equatable {
    public let vaultSizeBytes: Int64
    public let dedupSavingsBytes: Int64
    public let indexSizeBytes: Int64
    public let vectorsSizeBytes: Int64

    public init(vaultSizeBytes: Int64, dedupSavingsBytes: Int64, indexSizeBytes: Int64, vectorsSizeBytes: Int64) {
        self.vaultSizeBytes = vaultSizeBytes
        self.dedupSavingsBytes = dedupSavingsBytes
        self.indexSizeBytes = indexSizeBytes
        self.vectorsSizeBytes = vectorsSizeBytes
    }
}

/// Cas d'usage : calcule le budget disque à partir de la base et des fichiers réels d'index.
/// `vectorsPath` est optionnel : `vectors.db` n'existe qu'à partir de l'intégration sqlite-vec
/// (Phase 6, DRO-43). `index.db`/`vectors.db` sont toujours de vrais fichiers sur disque, gérés
/// par GRDB en dehors de l'abstraction `FileSystem` du coffre — leur taille est donc mesurée avec
/// un `FileSystem` indépendant de celui, potentiellement virtualisé en test, de `VaultService`.
public struct ComputeVaultBudget: Sendable {
    private let database: DropIndexDatabase
    private let indexPath: URL
    private let vectorsPath: URL?
    private let fileSystem: FileSystem

    public init(
        database: DropIndexDatabase, indexPath: URL, vectorsPath: URL? = nil, fileSystem: FileSystem = LiveFileSystem()
    ) {
        self.database = database
        self.indexPath = indexPath
        self.vectorsPath = vectorsPath
        self.fileSystem = fileSystem
    }

    public func compute() async throws -> VaultBudget {
        let (vaultSizeBytes, documentsTotalBytes): (Int64, Int64) = try await database.pool.read { db in
            let vaultSize = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(size_bytes), 0) FROM blobs") ?? 0
            let documentsTotal = try Int64.fetchOne(
                db, sql: "SELECT COALESCE(SUM(size_bytes), 0) FROM documents WHERE trashed_at IS NULL"
            ) ?? 0
            return (vaultSize, documentsTotal)
        }

        // L'économie de déduplication est la différence entre ce que pèseraient les documents
        // s'ils étaient tous des copies distinctes, et ce que pèsent réellement les blobs partagés.
        let dedupSavingsBytes = max(documentsTotalBytes - vaultSizeBytes, 0)
        let indexSizeBytes = existingFileSize(at: indexPath)
        let vectorsSizeBytes = vectorsPath.map(existingFileSize) ?? 0

        return VaultBudget(
            vaultSizeBytes: vaultSizeBytes, dedupSavingsBytes: dedupSavingsBytes,
            indexSizeBytes: indexSizeBytes, vectorsSizeBytes: vectorsSizeBytes
        )
    }

    private func existingFileSize(at url: URL) -> Int64 {
        guard fileSystem.fileExists(at: url) else { return 0 }
        return (try? fileSystem.fileSize(at: url)) ?? 0
    }
}
