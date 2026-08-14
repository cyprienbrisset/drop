import DropCore
import Foundation

/// Point d'entrée du module coffre : blobs, ingestion atomique, corbeille, GC, intégrité, export (§4.2).
/// `DropVault` ne connaît pas `DropIndex` — la cohérence blob ↔ base est orchestrée par
/// `DropFeatures.IngestFiles`, seul endroit du code où les deux sont manipulés ensemble (§4.2 règle 1).
public struct VaultService: Sendable {
    private let fileSystem: FileSystem
    private let clock: DropClock
    private let vaultRoot: URL

    public init(vaultRoot: URL, fileSystem: FileSystem = LiveFileSystem(), clock: DropClock = SystemClock()) {
        self.vaultRoot = vaultRoot
        self.fileSystem = fileSystem
        self.clock = clock
    }
}
