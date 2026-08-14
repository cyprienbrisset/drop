import DropCore
import DropIndex
import DropVault
import Foundation
import GRDB

/// Vérification périodique par échantillonnage (§5.9, EF-27) : ne recalcule jamais le hash de
/// tous les blobs (coût prohibitif à 100 000 documents), mais échantillonne un sous-ensemble à
/// chaque exécution, en priorisant les blobs jamais vérifiés ou vérifiés depuis le plus longtemps
/// — garantissant qu'à terme chaque blob passe par le contrôle.
public struct VerifyVaultIntegrity: Sendable {
    public struct Report: Sendable, Equatable {
        public let sampledCount: Int
        public let corruptHashes: [String]
        public let missingHashes: [String]
    }

    private let database: DropIndexDatabase
    private let vault: VaultService
    private let now: @Sendable () -> Date

    public init(database: DropIndexDatabase, vault: VaultService, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.vault = vault
        self.now = now
    }

    /// Taille d'échantillon (EF-27) : 2 % du total, plancher 20, plafond 500 — jamais plus que le
    /// nombre de blobs réellement référencés.
    public static func sampleSize(forTotal total: Int, ratio: Double = 0.02, minimum: Int = 20, maximum: Int = 500) -> Int {
        guard total > 0 else { return 0 }
        let raw = Int((Double(total) * ratio).rounded(.up))
        return min(max(raw, minimum), min(maximum, total))
    }

    public func run() async throws -> Report {
        let candidates = try await database.pool.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT hash FROM blobs WHERE ref_count > 0
                ORDER BY (last_verified_at IS NOT NULL), last_verified_at ASC
                """
            )
        }
        let sampleCount = Self.sampleSize(forTotal: candidates.count)
        let sampled = Array(candidates.prefix(sampleCount))

        var corruptHashes: [String] = []
        var missingHashes: [String] = []
        let verifiedAt = Self.isoString(from: now())

        for hash in sampled {
            let status = vault.verifyBlob(hash: hash)
            try await database.pool.write { db in
                try db.execute(
                    sql: "UPDATE blobs SET last_verified_at = ?, verify_status = ? WHERE hash = ?",
                    arguments: [verifiedAt, status.rawValue, hash]
                )
            }
            switch status {
            case .corrupt: corruptHashes.append(hash)
            case .missing: missingHashes.append(hash)
            case .ok: break
            }
        }

        return Report(sampledCount: sampled.count, corruptHashes: corruptHashes, missingHashes: missingHashes)
    }

    private static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
