import DropEmbeddings
import Foundation
import GRDB
import Testing

private func makeDatabase() throws -> VectorsDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-vectors-test-\(UUID().uuidString).sqlite").path
    return try VectorsDatabase(path: path)
}

@Test func migratingCreatesChunksTable() throws {
    let database = try makeDatabase()

    let tableNames: Set<String> = try database.pool.read { db in
        try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
    }
    #expect(tableNames.contains("chunks"))
}

@Test func sqliteVecExtensionIsRegisteredAndVecChunksTableExists() throws {
    let database = try makeDatabase()

    let tableNames: Set<String> = try database.pool.read { db in
        try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
    }
    #expect(tableNames.contains("vec_chunks")) // preuve que `sqlite3_vec_init` a bien enregistré `vec0`.
}
