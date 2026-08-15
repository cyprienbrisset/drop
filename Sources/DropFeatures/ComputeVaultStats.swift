import DropCore
import DropIndex
import Foundation
import GRDB

/// Statistiques d'usage affichées dans les Préférences — nombre de documents et temps de
/// traitement réel, jamais une estimation : la durée vient de `jobs.started_at`/`updated_at`,
/// posés respectivement au moment où `JobWorker` prend le travail (§JobQueue.dequeueNext) et au
/// moment où il le termine (§JobQueue.complete).
public struct VaultStats: Sendable, Equatable {
    public let documentCount: Int
    /// `nil` tant qu'aucune analyse n'est encore allée à son terme (coffre tout juste créé).
    public let averageAnalysisSeconds: Double?

    public init(documentCount: Int, averageAnalysisSeconds: Double?) {
        self.documentCount = documentCount
        self.averageAnalysisSeconds = averageAnalysisSeconds
    }
}

public struct ComputeVaultStats: Sendable {
    private let database: DropIndexDatabase

    public init(database: DropIndexDatabase) {
        self.database = database
    }

    public func compute() async throws -> VaultStats {
        try await database.pool.read { db in
            let documentCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM documents WHERE trashed_at IS NULL"
            ) ?? 0

            // `julianday` lit directement le format ISO 8601 posé par `JobQueue` — la différence
            // en jours, multipliée par 86 400, donne des secondes sans avoir à reparser les dates
            // côté Swift.
            let averageSeconds = try Double.fetchOne(
                db,
                sql: """
                SELECT AVG((julianday(updated_at) - julianday(started_at)) * 86400.0)
                FROM jobs WHERE state = 'done' AND started_at IS NOT NULL
                """
            )

            return VaultStats(documentCount: documentCount, averageAnalysisSeconds: averageSeconds)
        }
    }
}
