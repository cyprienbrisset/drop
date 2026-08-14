import Foundation
import GRDB

/// Résultat d'une recherche par plus proches voisins (§5.7) : l'agrégation au niveau document
/// par le meilleur chunk est la responsabilité de l'appelant (DropFeatures, DRO-44/45).
public struct VectorSearchResult: Sendable, Equatable {
    public let chunkID: Int64
    public let distance: Double
}

/// Accès à `vec_chunks` (§4.5, §5.5). Point important trouvé en testant contre la vraie extension
/// `sqlite-vec` : un `BLOB` inséré tel quel est interprété comme un vecteur **float32** par
/// défaut (`vector_from_value` se base sur le sous-type SQLite de la valeur, absent pour un BLOB
/// brut). Pour une colonne déclarée `int8[N]`, chaque valeur doit être explicitement taguée via
/// la fonction SQL `vec_int8(...)` — sans quoi l'insertion échoue avec une erreur de longueur
/// trompeuse (« must be divisible by 4 », le indice float32).
public struct VectorChunkStore: Sendable {
    private let database: VectorsDatabase

    public init(database: VectorsDatabase) {
        self.database = database
    }

    public func insert(chunkID: Int64, quantized: QuantizedVector) async throws {
        try await database.pool.write { db in
            try db.execute(
                sql: "INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, vec_int8(?))",
                arguments: [chunkID, Self.blob(for: quantized)]
            )
        }
    }

    public func nearestNeighbors(to quantized: QuantizedVector, limit: Int) async throws -> [VectorSearchResult] {
        try await database.pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT chunk_id, distance FROM vec_chunks
                WHERE embedding MATCH vec_int8(?) AND k = ?
                ORDER BY distance
                """,
                arguments: [Self.blob(for: quantized), limit]
            )
            return rows.map { VectorSearchResult(chunkID: $0["chunk_id"], distance: $0["distance"]) }
        }
    }

    private static func blob(for quantized: QuantizedVector) -> Data {
        Data(quantized.values.map { UInt8(bitPattern: $0) })
    }
}
