import DropEmbeddings
import Foundation
import GRDB
import Testing

@Test func migratingCreatesChunksTable() throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-vectors-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    let database = try VectorsDatabase(path: path)

    let tableNames: Set<String> = try database.pool.read { db in
        try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
    }
    #expect(tableNames.contains("chunks"))
}
