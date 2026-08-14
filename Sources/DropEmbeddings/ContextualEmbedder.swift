import NaturalLanguage

/// Version du modèle d'embeddings, écrite sur chaque chunk (§4.5) : non négociable — sans elle,
/// un changement de moteur rend l'index silencieusement incohérent, la panne la plus coûteuse à
/// diagnostiquer du projet. Ce module reste seul responsable de sa définition.
public let embeddingModelVersion = "nlcontextual-fr-v1"

public enum ContextualEmbedderError: Error, Sendable, Equatable {
    case modelUnavailable
    case assetsNotDownloaded
    case textTooShort
}

/// Embeddings via `NLContextualEmbedding` français, dimension 512 (native, aucune projection
/// nécessaire — vérifié : `NLContextualEmbedding(language: .french).dimension == 512`), moyenne
/// des vecteurs de sous-mots (§5.5). Documents de moins de 30 tokens utiles : pas d'embedding
/// (contrôle à la charge de l'appelant, avant même d'atteindre ce type).
///
/// `actor`, pas `struct` : `NLContextualEmbedding` n'est pas thread-safe pour des appels
/// concurrents sur la même instance — deux recherches lancées à la volée pendant la frappe (une
/// requête par debounce, la précédente annulée côté Swift sans que l'appel `embeddingResultForString:`
/// déjà en cours ne s'arrête pour autant) pouvaient faire chevaucher deux `load()`/`embeddingResultForString:`
/// sur le moteur E5RT/BNNS sous-jacent, provoquant un vrai crash natif (`EXC_BAD_ACCESS`, pas une
/// erreur Swift rattrapable). L'acteur sérialise tous les appels, y compris entre document
/// et requête de recherche : plus jamais deux appels concurrents sur la même instance.
public actor ContextualEmbedder {
    private let embedding: NLContextualEmbedding

    public init?() {
        guard let embedding = NLContextualEmbedding(language: .french) else { return nil }
        self.embedding = embedding
    }

    public var dimension: Int { embedding.dimension }
    public var hasAvailableAssets: Bool { embedding.hasAvailableAssets }

    public func embed(_ text: String) throws -> [Double] {
        guard hasAvailableAssets else { throw ContextualEmbedderError.assetsNotDownloaded }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ContextualEmbedderError.textTooShort }

        try embedding.load()
        defer { embedding.unload() }

        let result = try embedding.embeddingResult(for: text, language: .french)
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for index in 0..<min(vector.count, sum.count) {
                sum[index] += vector[index]
            }
            count += 1
            return true
        }
        guard count > 0 else { throw ContextualEmbedderError.textTooShort }
        return sum.map { $0 / Double(count) }
    }
}
