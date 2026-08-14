import DropCore
import Foundation

/// Points de coupure couverts par cette suite (§8.4, sous-ensemble applicable à `DropVault` —
/// les points touchant la transaction SQL, la corbeille, les migrations et le GC sont couverts
/// par les suites `DropFeaturesTests` correspondantes).
///
/// Contrairement au `SIGKILL` réel, le point de rupture est ici exact et déterministe : une seule
/// itération suffit pour prouver l'invariant à ce point précis. Le fuzzing par `SIGKILL` sur 100
/// itérations (§8.4) reste un exercice distinct, à mener manuellement ou en CI sur un vrai volume,
/// pour couvrir les incertitudes de timing qu'une injection déterministe ne peut pas révéler.
enum VaultFaultPoint {
    case duringSourceHashing
    case duringTemporaryCopy
    case duringVerificationHashing
    case duringSync
    case duringRename
    case duringMetadataWrite
    case none
}

/// Décore un `FileSystem` réel pour faire échouer une opération précise, à un point choisi de la
/// séquence d'ingestion (§5.1).
final class FaultInjectingFileSystem: FileSystem, @unchecked Sendable {
    private let base: FileSystem
    private let failAt: VaultFaultPoint
    private let lock = NSLock()
    private var chunkCallCount = 0

    init(wrapping base: FileSystem, failAt: VaultFaultPoint) {
        self.base = base
        self.failAt = failAt
    }

    private func fail(_ point: VaultFaultPoint) throws {
        guard point == failAt else { return }
        throw DropError(code: "FAULT-INJECTED", message: "\(point)")
    }

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func fileSize(at url: URL) throws -> Int64 { try base.fileSize(at: url) }
    func modificationDate(at url: URL) throws -> Date { try base.modificationDate(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func removeItem(at url: URL) throws { try base.removeItem(at: url) }
    func read(at url: URL) throws -> Data { try base.read(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try base.contentsOfDirectory(at: url) }

    func moveItem(at source: URL, to destination: URL) throws {
        try fail(.duringRename)
        try base.moveItem(at: source, to: destination)
    }

    func write(_ data: Data, to url: URL) throws {
        try fail(.duringMetadataWrite)
        try base.write(data, to: url)
    }

    func syncFile(at url: URL) throws {
        try fail(.duringSync)
        try base.syncFile(at: url)
    }

    func syncDirectory(at url: URL) throws {
        try base.syncDirectory(at: url)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try fail(.duringTemporaryCopy)
        try base.copyItem(at: source, to: destination)
    }

    /// Le hachage source (1er appel) et la vérification post-copie (2e appel) partagent la même
    /// primitive : on les distingue par ordre d'appel, remis à zéro à chaque instance de test.
    func forEachChunk(at url: URL, chunkSize: Int, _ body: (Data) throws -> Void) throws {
        let callIndex = lock.withLock {
            chunkCallCount += 1
            return chunkCallCount
        }
        try fail(callIndex == 1 ? .duringSourceHashing : .duringVerificationHashing)
        try base.forEachChunk(at: url, chunkSize: chunkSize, body)
    }
}
