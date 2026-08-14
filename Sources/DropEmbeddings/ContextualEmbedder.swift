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
public struct ContextualEmbedder: Sendable {
    // `NLContextualEmbedding` n'est pas `Sendable`, mais cette instance n'est jamais partagée
    // en écriture concurrente au sein d'un même appel — `embed` est synchrone de bout en bout.
    nonisolated(unsafe) private let embedding: NLContextualEmbedding

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
