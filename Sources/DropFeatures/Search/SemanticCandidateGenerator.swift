import DropEmbeddings
import DropSearch
import Foundation
import GRDB

/// Générateur de candidats sémantiques (§5.7) : k plus proches voisins sur `vec_chunks`,
/// agrégation au niveau document par le meilleur chunk (plus petite distance).
public struct SemanticCandidateGenerator: CandidateGenerator {
    private let vectorsDatabase: VectorsDatabase
    private let chunkStore: VectorChunkStore
    private let embedder: ContextualEmbedder

    /// `nil` si aucun modèle d'embedding contextuel n'est disponible pour le français sur cette
    /// machine (§5.4.4 : le produit reste fonctionnel sans lui — recherche lexicale seule).
    public init?(vectorsDatabase: VectorsDatabase) {
        guard let embedder = ContextualEmbedder() else { return nil }
        self.vectorsDatabase = vectorsDatabase
        self.chunkStore = VectorChunkStore(database: vectorsDatabase)
        self.embedder = embedder
    }

    public func candidates(for query: ParsedQuery, limit: Int) async throws -> [RankedDocument] {
        let text = query.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, await embedder.hasAvailableAssets else { return [] }

        let vector = try await embedder.embed(text)
        let quantized = EmbeddingQuantizer.quantize(vector)
        // Sur-échantillonnage : plusieurs chunks du même document peuvent apparaître parmi les
        // voisins les plus proches, l'agrégation par document réduit ensuite ce nombre.
        let neighbors = try await chunkStore.nearestNeighbors(to: quantized, limit: limit * 5)
        guard !neighbors.isEmpty else { return [] }

        let documentIDsByChunk = try await documentIDs(forChunkIDs: neighbors.map(\.chunkID))

        var bestDistance: [String: Double] = [:]
        for neighbor in neighbors {
            guard let documentID = documentIDsByChunk[neighbor.chunkID] else { continue }
            if let existing = bestDistance[documentID] {
                bestDistance[documentID] = min(existing, neighbor.distance)
            } else {
                bestDistance[documentID] = neighbor.distance
            }
        }

        let ranked = bestDistance.sorted { $0.value < $1.value }.prefix(limit)
        return ranked.enumerated().map { index, entry in RankedDocument(documentID: entry.key, rank: index + 1) }
    }

    private func documentIDs(forChunkIDs chunkIDs: [Int64]) async throws -> [Int64: String] {
        try await vectorsDatabase.pool.read { db in
            let placeholders = chunkIDs.map { _ in "?" }.joined(separator: ", ")
            let rows = try Row.fetchAll(
                db, sql: "SELECT id, document_id FROM chunks WHERE id IN (\(placeholders))",
                arguments: StatementArguments(chunkIDs)
            )
            var map: [Int64: String] = [:]
            for row in rows { map[row["id"]] = row["document_id"] }
            return map
        }
    }
}
