import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import GRDB
import Testing

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-jobworker-test-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

private func insertDocument(_ database: DropIndexDatabase, id: String, blobHash: String) async throws {
    try await database.pool.write { db in
        try db.execute(sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, 0, '2026-01-01T00:00:00Z')", arguments: [blobHash])
        try db.execute(
            sql: """
            INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source)
            VALUES (?, ?, ?, ?, 0, '2026-01-01T00:00:00Z', 'drop')
            """,
            arguments: [id, blobHash, "doc.txt", "doc.txt"]
        )
        try db.execute(sql: "INSERT INTO fts_docs (display_name, body, issuer, keywords, document_id) VALUES ('doc.txt', '', '', '', ?)", arguments: [id])
    }
}

@Test func processNextReturnsFalseWhenTheQueueIsEmpty() async throws {
    let database = try makeDatabase()
    let vault = VaultService(vaultRoot: FileManager.default.temporaryDirectory.appendingPathComponent("drop-jobworker-vault-\(UUID().uuidString)"))
    let worker = JobWorker(
        jobQueue: JobQueue(database: database), analyzeDocument: AnalyzeDocument(vault: vault, database: database),
        sleeper: ImmediateSleeper()
    )

    let processed = await worker.processNext()
    #expect(!processed)
}

@Test func processNextRunsAnalysisAndMarksTheJobDone() async throws {
    let database = try makeDatabase()
    let vaultRoot = FileManager.default.temporaryDirectory.appendingPathComponent("drop-jobworker-vault-\(UUID().uuidString)")
    let vault = VaultService(vaultRoot: vaultRoot, fileSystem: LiveFileSystem())

    // Un blob réel et lisible : `AnalyzeDocument` lit toujours le vrai système de fichiers
    // (PDFKit/NSAttributedString), pas l'abstraction `FileSystem` injectée dans `VaultService`.
    let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
    try "Contenu à indexer".write(to: sourceURL, atomically: true, encoding: .utf8)
    let blob = try vault.writeBlob(fromFileAt: sourceURL)

    let documentID = UUID().uuidString
    try await insertDocument(database, id: documentID, blobHash: blob.hash)

    let jobQueue = JobQueue(database: database)
    try await jobQueue.enqueue(documentID: documentID, kind: .extract)

    let worker = JobWorker(jobQueue: jobQueue, analyzeDocument: AnalyzeDocument(vault: vault, database: database), sleeper: ImmediateSleeper())
    let processed = await worker.processNext()
    #expect(processed)

    let (jobState, ftsBody): (String, String) = try await database.pool.read { db in
        let state: String = try String.fetchOne(db, sql: "SELECT state FROM jobs WHERE document_id = ?", arguments: [documentID]) ?? ""
        let body: String = try String.fetchOne(db, sql: "SELECT body FROM fts_docs WHERE document_id = ?", arguments: [documentID]) ?? ""
        return (state, body)
    }
    #expect(jobState == "done")
    #expect(ftsBody.contains("Contenu"))
}

@Test func startAndStopRunTheLoopWithoutLeavingItRunningForever() async throws {
    let database = try makeDatabase()
    let vault = VaultService(vaultRoot: FileManager.default.temporaryDirectory.appendingPathComponent("drop-jobworker-vault-\(UUID().uuidString)"))
    let worker = JobWorker(
        jobQueue: JobQueue(database: database), analyzeDocument: AnalyzeDocument(vault: vault, database: database),
        sleeper: ImmediateSleeper(), idlePollSeconds: 0
    )

    await worker.start()
    // Un second `start()` ne doit pas empiler une seconde boucle.
    await worker.start()
    try await Task.sleep(for: .milliseconds(50))
    await worker.stop()
}
