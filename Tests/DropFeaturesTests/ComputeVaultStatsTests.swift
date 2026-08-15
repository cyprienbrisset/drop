import DropCore
import DropFeatures
import DropIndex
import Foundation
import GRDB
import Testing

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-stats-test-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

private func insertDocument(_ database: DropIndexDatabase, id: String, trashed: Bool = false) async throws {
    try await database.pool.write { db in
        let hash = "hash-\(id)"
        try db.execute(sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, 0, '2026-01-01T00:00:00Z')", arguments: [hash])
        try db.execute(
            sql: """
            INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source, trashed_at)
            VALUES (?, ?, ?, ?, 0, '2026-01-01T00:00:00Z', 'drop', ?)
            """,
            arguments: [id, hash, id, id, trashed ? "2026-01-02T00:00:00Z" : nil]
        )
    }
}

@Test func documentCountOnlyCountsActiveNonTrashedDocuments() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1")
    try await insertDocument(database, id: "doc-2")
    try await insertDocument(database, id: "doc-3", trashed: true)

    let stats = try await ComputeVaultStats(database: database).compute()

    #expect(stats.documentCount == 2)
}

@Test func averageAnalysisSecondsIsNilWithoutAnyCompletedJob() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1")
    let queue = JobQueue(database: database)
    try await queue.enqueue(documentID: "doc-1", kind: .extract)

    let stats = try await ComputeVaultStats(database: database).compute()

    #expect(stats.averageAnalysisSeconds == nil)
}

@Test func averageAnalysisSecondsReflectsTheRealDurationBetweenStartedAndDone() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1")
    try await insertDocument(database, id: "doc-2")

    // doc-1 : 10 s de traitement ; doc-2 : 20 s — moyenne attendue 15 s.
    let dequeueAt1 = FixedClock(date: Date(timeIntervalSince1970: 1_000))
    let completeAt1 = FixedClock(date: Date(timeIntervalSince1970: 1_010))
    let dequeueAt2 = FixedClock(date: Date(timeIntervalSince1970: 2_000))
    let completeAt2 = FixedClock(date: Date(timeIntervalSince1970: 2_020))

    try await JobQueue(database: database).enqueue(documentID: "doc-1", kind: .extract)
    try await JobQueue(database: database).enqueue(documentID: "doc-2", kind: .extract)

    let job1 = try await JobQueue(database: database, clock: dequeueAt1).dequeueNext()!
    try await JobQueue(database: database, clock: completeAt1).complete(jobID: job1.id!)

    let job2 = try await JobQueue(database: database, clock: dequeueAt2).dequeueNext()!
    try await JobQueue(database: database, clock: completeAt2).complete(jobID: job2.id!)

    let stats = try await ComputeVaultStats(database: database).compute()

    let average = try #require(stats.averageAnalysisSeconds)
    #expect(abs(average - 15) < 0.5)
}
