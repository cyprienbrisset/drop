import DropCore
import DropVault

/// Cas d'usage : ingestion d'un ou plusieurs fichiers. Seul endroit du code où `DropVault` et
/// `DropIndex` sont manipulés ensemble (§4.2 règle 1) — la cohérence blob ↔ base est orchestrée ici.
public struct IngestFiles: Sendable {
    public init() {}
}
