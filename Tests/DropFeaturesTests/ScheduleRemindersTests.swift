import DropCore
import DropFeatures
import DropIndex
import Foundation
import GRDB
import Testing

/// Double en mémoire : les tests ne doivent jamais dépendre d'une vraie autorisation système
/// (`UNUserNotificationCenter`), absente et non accordable en environnement de test.
final class FakeNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    var authorizationGranted = true
    private(set) var scheduledIdentifiers: [String] = []
    private(set) var cancelledIdentifiers: [String] = []

    func requestAuthorizationIfNeeded() async -> Bool { authorizationGranted }

    func scheduleReminder(identifier: String, title: String, body: String, at date: Date) async {
        lock.withLock { scheduledIdentifiers.append(identifier) }
    }

    func cancelReminder(identifier: String) async {
        lock.withLock { cancelledIdentifiers.append(identifier) }
    }
}

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-reminders-index-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

private func insertDocument(_ database: DropIndexDatabase, id: String, displayName: String, dueDate: String?) async throws {
    try await database.pool.write { db in
        try db.execute(
            sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES ('hash', 10, '2026-01-01T00:00:00Z')"
        )
        try db.execute(
            sql: """
            INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source, due_date)
            VALUES (?, 'hash', ?, ?, 10, '2026-01-01T00:00:00Z', 'ingest', ?)
            """,
            arguments: [id, displayName, displayName, dueDate]
        )
    }
}

@Test func schedulingDoesNothingWhenRemindersAreNotEnabled() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1", displayName: "facture.pdf", dueDate: "2030-01-15")
    let scheduler = FakeNotificationScheduler()
    let reminders = ScheduleReminders(database: database, scheduler: scheduler)

    try await reminders.scheduleIfNeeded(documentID: "doc-1")

    #expect(scheduler.scheduledIdentifiers.isEmpty)
}

@Test func schedulingAFutureDueDateRequestsAuthorizationAndSchedulesOnce() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1", displayName: "facture.pdf", dueDate: "2030-01-15")
    let scheduler = FakeNotificationScheduler()
    let reminders = ScheduleReminders(database: database, scheduler: scheduler)

    try await reminders.setRemindersEnabled(true)
    #expect(try await reminders.remindersEnabled())

    try await reminders.scheduleIfNeeded(documentID: "doc-1")
    #expect(scheduler.scheduledIdentifiers == ["doc-1"])

    let scheduledAt: String? = try await database.pool.read { db in
        try String.fetchOne(db, sql: "SELECT reminder_scheduled_at FROM documents WHERE id = ?", arguments: ["doc-1"])
    }
    #expect(scheduledAt != nil)

    // Une seconde analyse du même document ne doit jamais reposer une seconde notification.
    try await reminders.scheduleIfNeeded(documentID: "doc-1")
    #expect(scheduler.scheduledIdentifiers == ["doc-1"])
}

@Test func schedulingWithoutADueDateDoesNothing() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1", displayName: "facture.pdf", dueDate: nil)
    let scheduler = FakeNotificationScheduler()
    let reminders = ScheduleReminders(database: database, scheduler: scheduler)
    try await reminders.setRemindersEnabled(true)

    try await reminders.scheduleIfNeeded(documentID: "doc-1")

    #expect(scheduler.scheduledIdentifiers.isEmpty)
}

@Test func schedulingADueDateAlreadyInThePastDoesNothing() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1", displayName: "facture.pdf", dueDate: "2000-01-01")
    let scheduler = FakeNotificationScheduler()
    let reminders = ScheduleReminders(database: database, scheduler: scheduler)
    try await reminders.setRemindersEnabled(true)

    try await reminders.scheduleIfNeeded(documentID: "doc-1")

    #expect(scheduler.scheduledIdentifiers.isEmpty)
}

@Test func schedulingWhenAuthorizationIsDeniedNeverMarksAReminderAsScheduled() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1", displayName: "facture.pdf", dueDate: "2030-01-15")
    let scheduler = FakeNotificationScheduler()
    scheduler.authorizationGranted = false
    let reminders = ScheduleReminders(database: database, scheduler: scheduler)
    try await reminders.setRemindersEnabled(true)

    try await reminders.scheduleIfNeeded(documentID: "doc-1")

    #expect(scheduler.scheduledIdentifiers.isEmpty)
    let scheduledAt: String? = try await database.pool.read { db in
        try String.fetchOne(db, sql: "SELECT reminder_scheduled_at FROM documents WHERE id = ?", arguments: ["doc-1"])
    }
    #expect(scheduledAt == nil)
}
