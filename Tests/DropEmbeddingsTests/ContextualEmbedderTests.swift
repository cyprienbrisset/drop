import DropEmbeddings
import Testing

@Test func frenchEmbeddingModelHasTheExpectedNativeDimension() throws {
    let embedder = try #require(ContextualEmbedder())
    #expect(embedder.dimension == 512) // vérifié : aucune projection nécessaire (§5.5).
}

@Test func embedsRealTextAndQuantizesItRoundTrip() throws {
    let embedder = try #require(ContextualEmbedder())
    guard embedder.hasAvailableAssets else {
        withKnownIssue("Assets du modèle d'embeddings non téléchargés sur cette machine") {
            _ = try embedder.embed("Facture EDF de juillet.")
        }
        return
    }

    let vector = try embedder.embed("Facture EDF de juillet. Montant à régler 84,20 euros.")
    #expect(vector.count == 512)

    let quantized = EmbeddingQuantizer.quantize(vector)
    let restored = EmbeddingQuantizer.dequantize(quantized)
    // Similarité cosinus entre l'original et sa version quantifiée : doit rester très proche de 1.
    let dot = zip(vector, restored).map(*).reduce(0, +)
    let normA = (vector.map { $0 * $0 }.reduce(0, +)).squareRoot()
    let normB = (restored.map { $0 * $0 }.reduce(0, +)).squareRoot()
    let cosine = dot / (normA * normB)
    #expect(cosine > 0.99)
}

@Test func embeddingEmptyTextThrows() throws {
    let embedder = try #require(ContextualEmbedder())
    #expect(throws: (any Error).self) {
        try embedder.embed("   ")
    }
}
