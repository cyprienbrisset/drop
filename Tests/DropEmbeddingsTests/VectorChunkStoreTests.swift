import DropEmbeddings
import Foundation
import Testing

private func makeDatabase() throws -> VectorsDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-vecstore-test-\(UUID().uuidString).sqlite").path
    return try VectorsDatabase(path: path)
}

@Test func insertsAndFindsTheNearestNeighborAmongInt8Vectors() async throws {
    let database = try makeDatabase()
    let store = VectorChunkStore(database: database)

    // Deux vecteurs bien distincts sur 512 dimensions (la table réelle du schéma, §4.5).
    var closeToQuery = [Double](repeating: 0, count: 512)
    closeToQuery[0] = 1.0
    var farFromQuery = [Double](repeating: 0, count: 512)
    farFromQuery[1] = 1.0

    try await store.insert(chunkID: 1, quantized: EmbeddingQuantizer.quantize(closeToQuery))
    try await store.insert(chunkID: 2, quantized: EmbeddingQuantizer.quantize(farFromQuery))

    let query = EmbeddingQuantizer.quantize(closeToQuery)
    let results = try await store.nearestNeighbors(to: query, limit: 2)

    #expect(results.first?.chunkID == 1)
    #expect((results.first?.distance ?? .infinity) < (results.last?.distance ?? 0))
}

@Test func nearestNeighborsRespectsTheRequestedLimit() async throws {
    let database = try makeDatabase()
    let store = VectorChunkStore(database: database)

    for chunkID in 1...5 {
        var vector = [Double](repeating: 0, count: 512)
        vector[chunkID] = 1.0
        try await store.insert(chunkID: Int64(chunkID), quantized: EmbeddingQuantizer.quantize(vector))
    }

    var query = [Double](repeating: 0, count: 512)
    query[1] = 1.0
    let results = try await store.nearestNeighbors(to: EmbeddingQuantizer.quantize(query), limit: 3)

    #expect(results.count == 3)
}
