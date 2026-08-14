import DropCore
import DropFeatures
import DropIndex
import DropJobs
import Foundation
import GRDB
import Testing

private func makeQueue(clock: DropClock = SystemClock()) throws -> (queue: JobQueue, database: DropIndexDatabase) {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-jobs-test-\(UUID().uuidString).sqlite").path
    let database = try DropIndexDatabase(path: dbPath)
    return (JobQueue(database: database, clock: clock), database)
}

/// `jobs.document_id` référence `documents(id)` (§4.4) : un travail ne peut exister que pour un
/// document réel. On insère ici le minimum requis (blob + document) plutôt que de passer par
/// l'ingestion complète, hors sujet pour ces tests.
private func insertDocument(_ documentID: String, into database: DropIndexDatabase) async throws {
    try await database.pool.write { db in
        let hash = "hash-\(documentID)"
        try db.execute(
            sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, 0, '2026-01-01T00:00:00Z')",
            arguments: [hash]
        )
        try db.execute(
            sql: """
            INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source)
            VALUES (?, ?, ?, ?, 0, '2026-01-01T00:00:00Z', 'drop')
            """,
            arguments: [documentID, hash, documentID, documentID]
        )
    }
}

@Test func enqueueingTheSameJobTwiceIsIdempotent() async throws {
    let (queue, database) = try makeQueue()
    try await insertDocument("doc-1", into: database)

    let first = try await queue.enqueue(documentID: "doc-1", kind: .extract)
    let second = try await queue.enqueue(documentID: "doc-1", kind: .extract)

    #expect(first)
    #expect(!second) // UNIQUE (document_id, kind) : pas de doublon.
}

@Test func dequeuePicksTheHighestPriorityJobFirst() async throws {
    let (queue, database) = try makeQueue()
    try await insertDocument("doc-1", into: database)
    try await insertDocument("doc-2", into: database)
    try await queue.enqueue(documentID: "doc-1", kind: .embed) // priorité 60
    try await queue.enqueue(documentID: "doc-2", kind: .extract) // priorité 10, plus prioritaire

    let job = try await queue.dequeueNext()

    #expect(job?.documentID == "doc-2")
    #expect(job?.kind == .extract)
    #expect(job?.state == .running)
}

@Test func dequeueCanBeRestrictedToSpecificKinds() async throws {
    let (queue, database) = try makeQueue()
    try await insertDocument("doc-1", into: database)
    try await insertDocument("doc-2", into: database)
    try await queue.enqueue(documentID: "doc-1", kind: .ocr)
    try await queue.enqueue(documentID: "doc-2", kind: .extract)

    let job = try await queue.dequeueNext(kinds: [.ocr])
    #expect(job?.kind == .ocr)
}

@Test func reprioritizingAConsultedDocumentBumpsItToZero() async throws {
    let (queue, database) = try makeQueue()
    try await insertDocument("doc-1", into: database)
    try await queue.enqueue(documentID: "doc-1", kind: .embed) // priorité 60

    try await queue.reprioritizeToForeground(documentID: "doc-1")
    let job = try await queue.dequeueNext()

    #expect(job?.priority == 0)
}

@Test func failingBelowMaxAttemptsRequeuesWithBackoff() async throws {
    let now = Date(timeIntervalSince1970: 0)
    let (queue, database) = try makeQueue(clock: FixedClock(date: now))
    try await insertDocument("doc-1", into: database)
    try await queue.enqueue(documentID: "doc-1", kind: .extract)
    let job = try await queue.dequeueNext()!

    try await queue.fail(jobID: job.id!, error: "boom")

    // Immédiatement après l'échec, le prochain essai n'est pas encore dû (backoff en cours) :
    // aucun travail ne doit être repris tout de suite.
    let immediateRetry = try await queue.dequeueNext()
    #expect(immediateRetry == nil)
}

@Test func failingMaxAttemptsTimesMarksTheJobPermanentlyFailed() async throws {
    let (queue, database) = try makeQueue()
    try await insertDocument("doc-1", into: database)
    try await queue.enqueue(documentID: "doc-1", kind: .extract)
    let job = try await queue.dequeueNext()!

    // On appelle `fail` directement sur le même identifiant, sans redéquer entre chaque tentative
    // (le backoff empêcherait une reprise immédiate) — ce qui teste la même logique de comptage.
    for _ in 0..<BackoffPolicy.maxAttempts {
        try await queue.fail(jobID: job.id!, error: "boom")
    }

    let (state, attempts): (String, Int) = try await database.pool.read { db in
        let state = try String.fetchOne(db, sql: "SELECT state FROM jobs WHERE id = ?", arguments: [job.id!]) ?? ""
        let attempts = try Int.fetchOne(db, sql: "SELECT attempts FROM jobs WHERE id = ?", arguments: [job.id!]) ?? -1
        return (state, attempts)
    }

    #expect(state == "failed")
    #expect(attempts == BackoffPolicy.maxAttempts)
}

@Test func completingAJobMarksItDone() async throws {
    let (queue, database) = try makeQueue()
    try await insertDocument("doc-1", into: database)
    try await queue.enqueue(documentID: "doc-1", kind: .extract)
    let job = try await queue.dequeueNext()!

    try await queue.complete(jobID: job.id!)

    let nothingLeft = try await queue.dequeueNext()
    #expect(nothingLeft == nil)
}
