/// Fusion par Reciprocal Rank Fusion (§5.7, ADR-04) : `score(d) = Σ_i w_i / (k + rank_i(d))`.
/// RRF ne compare que des rangs — jamais de somme pondérée de scores d'échelles incommensurables.
/// Toute modification des poids ou de `k` passe obligatoirement par le harnais d'évaluation (§8.3).
public struct ReciprocalRankFusion: Sendable {
    public let k: Double
    public let weights: [String: Double]

    public init(
        k: Double = 60,
        weights: [String: Double] = ["lexical": 1.0, "semantic": 1.0, "exact": 0.8, "trigram": 0.4]
    ) {
        self.k = k
        self.weights = weights
    }

    public func fuse(rankedLists: [String: [RankedDocument]]) -> [String: Double] {
        var scores: [String: Double] = [:]
        for (generator, documents) in rankedLists {
            let weight = weights[generator] ?? 1.0
            for document in documents {
                scores[document.documentID, default: 0] += weight / (k + Double(document.rank))
            }
        }
        return scores
    }
}
