import DropCore
import DropIndex
import DropJobs
import Foundation
import GRDB

/// File de travaux persistante (§5.8) : une analyse interrompue reprend au redémarrage, elle ne
/// se perd jamais — c'est la table `jobs` de `index.db` qui porte l'état, pas la mémoire.
public struct JobQueue: Sendable {
    private let database: DropIndexDatabase
    private let clock: DropClock

    public init(database: DropIndexDatabase, clock: DropClock = SystemClock()) {
        self.database = database
        self.clock = clock
    }

    /// Ajoute un travail. Idempotent : `UNIQUE (document_id, kind)` dans le schéma (§4.4) — un
    /// second appel pour le même couple ne crée pas de doublon. Retourne `true` si un nouveau
    /// travail a été créé, `false` s'il existait déjà.
    @discardableResult
    public func enqueue(documentID: String, kind: JobKind, priority: Int? = nil) async throws -> Bool {
        let now = Self.isoFormatter.string(from: clock.now())
        let effectivePriority = priority ?? Job.defaultPriority[kind] ?? 100

        return try await database.pool.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO jobs (document_id, kind, priority, state, attempts, created_at, updated_at)
                VALUES (?, ?, ?, 'queued', 0, ?, ?)
                """,
                arguments: [documentID, kind.rawValue, effectivePriority, now, now]
            )
            return db.changesCount > 0
        }
    }

    /// Retire et marque « en cours » le travail le plus prioritaire parmi les types demandés
    /// (ou tous types si `kinds` est `nil`), en respectant le backoff (`next_attempt_at`).
    public func dequeueNext(kinds: [JobKind]? = nil) async throws -> Job? {
        let now = Self.isoFormatter.string(from: clock.now())

        return try await database.pool.write { db in
            var arguments: [any DatabaseValueConvertible] = [now]
            var sql = "SELECT * FROM jobs WHERE state = 'queued' AND (next_attempt_at IS NULL OR next_attempt_at <= ?)"
            if let kinds, !kinds.isEmpty {
                let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
                sql += " AND kind IN (\(placeholders))"
                arguments.append(contentsOf: kinds.map(\.rawValue))
            }
            sql += " ORDER BY priority ASC, created_at ASC LIMIT 1"

            guard let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(arguments)) else {
                return nil
            }
            let jobID: Int64 = row["id"]
            try db.execute(sql: "UPDATE jobs SET state = 'running', updated_at = ? WHERE id = ?", arguments: [now, jobID])
            return Self.job(fromRow: row, overridingState: .running)
        }
    }

    public func complete(jobID: Int64) async throws {
        let now = Self.isoFormatter.string(from: clock.now())
        _ = try await database.pool.write { db in
            try db.execute(sql: "UPDATE jobs SET state = 'done', updated_at = ? WHERE id = ?", arguments: [now, jobID])
        }
    }

    /// Échec d'un travail : backoff exponentiel avec gigue jusqu'à `BackoffPolicy.maxAttempts`
    /// tentatives, puis `failed` définitif (§5.8).
    public func fail(jobID: Int64, error: String) async throws {
        let now = clock.now()
        let nowString = Self.isoFormatter.string(from: now)

        _ = try await database.pool.write { db in
            guard let attempts = try Int.fetchOne(db, sql: "SELECT attempts FROM jobs WHERE id = ?", arguments: [jobID]) else {
                return
            }
            let newAttempts = attempts + 1
            if newAttempts >= BackoffPolicy.maxAttempts {
                try db.execute(
                    sql: "UPDATE jobs SET state = 'failed', attempts = ?, last_error = ?, updated_at = ? WHERE id = ?",
                    arguments: [newAttempts, error, nowString, jobID]
                )
            } else {
                let delay = BackoffPolicy.delaySeconds(forAttempt: newAttempts)
                let nextAttempt = Self.isoFormatter.string(from: now.addingTimeInterval(delay))
                try db.execute(
                    sql: """
                    UPDATE jobs SET state = 'queued', attempts = ?, last_error = ?, next_attempt_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    arguments: [newAttempts, error, nextAttempt, nowString, jobID]
                )
            }
        }
    }

    /// Un document consulté par l'utilisateur voit tous ses travaux repriorisés à 0 (§5.8).
    public func reprioritizeToForeground(documentID: String) async throws {
        let now = Self.isoFormatter.string(from: clock.now())
        _ = try await database.pool.write { db in
            try db.execute(
                sql: "UPDATE jobs SET priority = 0, updated_at = ? WHERE document_id = ? AND state = 'queued'",
                arguments: [now, documentID]
            )
        }
    }

    /// Nombre de travaux pas encore terminés (§5.8, EX-08) : sert à signaler à l'utilisateur
    /// qu'une analyse est encore en cours après un dépôt massif — jamais l'inverse, un compte de
    /// travaux déjà `done`/`failed` ne doit jamais compter comme « encore en attente ».
    public func pendingCount() async throws -> Int {
        try await database.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs WHERE state IN ('queued', 'running')") ?? 0
        }
    }

    private static func job(fromRow row: Row, overridingState: JobState? = nil) -> Job {
        let stateRaw: String = row["state"]
        return Job(
            id: row["id"], documentID: row["document_id"],
            kind: JobKind(rawValue: row["kind"]) ?? .extract,
            priority: row["priority"], state: overridingState ?? (JobState(rawValue: stateRaw) ?? .queued),
            attempts: row["attempts"], lastError: row["last_error"]
        )
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
