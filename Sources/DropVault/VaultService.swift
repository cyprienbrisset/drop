import DropCore
import Foundation

/// Résultat de l'écriture d'un blob (§5.1 étapes 3 à 7). `isNewBlob` indique si le contenu vient
/// d'être copié dans le coffre ou s'il existait déjà (EF-05 : aucune copie dans ce second cas).
public struct BlobWriteResult: Sendable, Equatable {
    public let hash: String
    public let sizeBytes: Int64
    public let blobURL: URL
    public let metadataURL: URL
    public let isNewBlob: Bool
}

/// Instantané taille+date, pour la détection de stabilité EF-11 : un fichier n'est ingéré que si
/// deux relevés espacés de 2 s sont identiques (téléchargements en cours, `.crdownload`, `.part`).
public struct FileStabilitySnapshot: Sendable, Equatable {
    public let sizeBytes: Int64
    public let modificationDate: Date
}

/// Point d'entrée du module coffre : blobs, ingestion atomique, corbeille, GC, intégrité, export (§4.2).
/// `DropVault` ne connaît pas `DropIndex` — la cohérence blob ↔ base est orchestrée par
/// `DropFeatures.IngestFiles`, seul endroit du code où les deux sont manipulés ensemble (§4.2 règle 1).
public struct VaultService: Sendable {
    public let vaultRoot: URL
    private let fileSystem: FileSystem
    private let clock: DropClock
    private let maxFileSizeBytes: Int64

    public init(
        vaultRoot: URL, fileSystem: FileSystem = LiveFileSystem(), clock: DropClock = SystemClock(),
        maxFileSizeBytes: Int64 = 500 * 1024 * 1024
    ) {
        self.vaultRoot = vaultRoot
        self.fileSystem = fileSystem
        self.clock = clock
        self.maxFileSizeBytes = maxFileSizeBytes
    }

    /// Chemin `vault/ab/cd/<hash>.blob` (§4.3) : préfixé sur 2+2 octets pour éviter des
    /// répertoires à plat de centaines de milliers d'entrées.
    public func paths(forHash hash: String) -> (blob: URL, metadata: URL) {
        let prefix1 = String(hash.prefix(2))
        let prefix2 = String(hash.dropFirst(2).prefix(2))
        let directory = vaultRoot.appendingPathComponent("vault/\(prefix1)/\(prefix2)")
        return (directory.appendingPathComponent("\(hash).blob"), directory.appendingPathComponent("\(hash).json"))
    }

    /// Relevé pour la vérification de stabilité EF-11 (§5.1 étape 2). L'appelant compare deux
    /// relevés espacés de 2 s avant d'ingérer.
    public func stabilitySnapshot(fileAt url: URL) throws -> FileStabilitySnapshot {
        guard fileSystem.fileExists(at: url) else { throw IngestionError.unreadable }
        return FileStabilitySnapshot(
            sizeBytes: try fileSystem.fileSize(at: url), modificationDate: try fileSystem.modificationDate(at: url)
        )
    }

    /// Séquence §5.1, étapes 3 à 7. Invariants garantis :
    /// - I1 : rien n'est fait à l'original avant que l'appelant ne committe la transaction DB.
    /// - I4 : un blob n'est jamais modifié en place, jamais réécrit s'il existe déjà.
    /// - I5 : un crash ici laisse au pire un fichier `tmp/*.part` orphelin, jamais de perte.
    public func writeBlob(fromFileAt sourceURL: URL, originalPath: String? = nil) throws -> BlobWriteResult {
        guard fileSystem.fileExists(at: sourceURL) else { throw IngestionError.unreadable }

        let sizeBytes: Int64
        do {
            sizeBytes = try fileSystem.fileSize(at: sourceURL)
        } catch {
            throw IngestionError.unreadable
        }
        guard sizeBytes <= maxFileSizeBytes else { throw IngestionError.tooLarge }

        let hash: String
        do {
            hash = try VaultHashing.sha256(ofFileAt: sourceURL, fileSystem: fileSystem)
        } catch {
            throw IngestionError.unreadable
        }

        let (blobURL, metadataURL) = paths(forHash: hash)

        // EF-05 : le hash existe déjà — on saute directement, sans aucune copie (§5.1 étape 4).
        if fileSystem.fileExists(at: blobURL) {
            return BlobWriteResult(hash: hash, sizeBytes: sizeBytes, blobURL: blobURL, metadataURL: metadataURL, isNewBlob: false)
        }

        let tmpURL = vaultRoot.appendingPathComponent("tmp/\(UUID().uuidString).part")
        try fileSystem.createDirectory(at: tmpURL.deletingLastPathComponent())
        try fileSystem.copyItem(at: sourceURL, to: tmpURL)

        let verifyHash = try VaultHashing.sha256(ofFileAt: tmpURL, fileSystem: fileSystem)
        guard verifyHash == hash else {
            try? fileSystem.removeItem(at: tmpURL)
            throw IngestionError.hashMismatch
        }

        try fileSystem.syncFile(at: tmpURL)
        try fileSystem.createDirectory(at: blobURL.deletingLastPathComponent())
        try fileSystem.moveItem(at: tmpURL, to: blobURL)
        try fileSystem.syncDirectory(at: blobURL.deletingLastPathComponent())

        let metadata = BlobMetadata(
            originalFilename: sourceURL.lastPathComponent, originalPath: originalPath,
            sizeBytes: sizeBytes, addedAt: Self.isoFormatter.string(from: clock.now())
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try fileSystem.write(metadataData, to: metadataURL)

        return BlobWriteResult(hash: hash, sizeBytes: sizeBytes, blobURL: blobURL, metadataURL: metadataURL, isNewBlob: true)
    }

    // Immuable après configuration, jamais mutée — partage sûr entre threads malgré l'absence
    // de conformance `Sendable` de `ISO8601DateFormatter`.
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
