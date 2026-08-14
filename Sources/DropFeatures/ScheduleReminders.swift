import DropCore
import DropIndex
import Foundation
import GRDB

/// Programmation des rappels d'échéance (§5, backlog V2, DRO-84). Jamais automatique sans
/// consentement explicite (§CDC) : `scheduleIfNeeded` ne fait rien tant que l'utilisateur n'a pas
/// activé l'option dans les Préférences — l'activer déclenche alors la vraie demande
/// d'autorisation système, jamais avant.
public struct ScheduleReminders: Sendable {
    private let database: DropIndexDatabase
    private let scheduler: NotificationScheduling
    private let clock: DropClock

    private static let remindersEnabledKey = "remindersEnabled"

    public init(database: DropIndexDatabase, scheduler: NotificationScheduling, clock: DropClock = SystemClock()) {
        self.database = database
        self.scheduler = scheduler
        self.clock = clock
    }

    public func remindersEnabled() async throws -> Bool {
        let value: String? = try await database.pool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [Self.remindersEnabledKey])
        }
        return value == "true"
    }

    public func setRemindersEnabled(_ enabled: Bool) async throws {
        try await database.pool.write { db in
            try db.execute(
                sql: "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [Self.remindersEnabledKey, enabled ? "true" : "false"]
            )
        }
    }

    /// Appelé après chaque analyse réussie : programme un rappel pour l'échéance détectée, une
    /// seule fois par document (`reminder_scheduled_at`) — une ré-analyse ne doit jamais reposer
    /// une seconde notification pour la même échéance.
    public func scheduleIfNeeded(documentID: String) async throws {
        guard try await remindersEnabled() else { return }

        struct DocumentRow: Sendable {
            let dueDate: String?
            let alreadyScheduled: String?
            let displayName: String
        }

        let row: DocumentRow? = try await database.pool.read { db in
            guard let record = try Row.fetchOne(
                db, sql: "SELECT due_date, reminder_scheduled_at, display_name FROM documents WHERE id = ?",
                arguments: [documentID]
            ) else { return nil }
            return DocumentRow(dueDate: record["due_date"], alreadyScheduled: record["reminder_scheduled_at"], displayName: record["display_name"])
        }

        guard let row, let dueDateText = row.dueDate, row.alreadyScheduled == nil else { return }
        guard let dueDate = Self.dateOnlyFormatter.date(from: dueDateText), dueDate > clock.now() else { return }
        guard await scheduler.requestAuthorizationIfNeeded() else { return }

        await scheduler.scheduleReminder(
            identifier: documentID, title: "Échéance à venir",
            body: "« \(row.displayName) » arrive à échéance le \(dueDateText).", at: dueDate
        )

        try await database.pool.write { db in
            try db.execute(
                sql: "UPDATE documents SET reminder_scheduled_at = ? WHERE id = ?",
                arguments: [Self.isoFormatter.string(from: clock.now()), documentID]
            )
        }
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // Jamais mutée après construction, seulement lue depuis `Sendable` closures (`pool.write`) —
    // sûr malgré `ISO8601DateFormatter` non `Sendable`.
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()
}
