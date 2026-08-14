import DropEmbeddings
import Testing

@Test func frenchEmbeddingModelHasTheExpectedNativeDimension() async throws {
    let embedder = try #require(ContextualEmbedder())
    #expect(await embedder.dimension == 512) // vérifié : aucune projection nécessaire (§5.5).
}

@Test func embedsRealTextAndQuantizesItRoundTrip() async throws {
    let embedder = try #require(ContextualEmbedder())
    guard await embedder.hasAvailableAssets else {
        await withKnownIssue("Assets du modèle d'embeddings non téléchargés sur cette machine") {
            _ = try await embedder.embed("Facture EDF de juillet.")
        }
        return
    }

    let vector = try await embedder.embed("Facture EDF de juillet. Montant à régler 84,20 euros.")
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

@Test func embeddingEmptyTextThrows() async throws {
    let embedder = try #require(ContextualEmbedder())
    await #expect(throws: (any Error).self) {
        try await embedder.embed("   ")
    }
}

/// Régression : `NLContextualEmbedding` n'est pas thread-safe pour des appels concurrents sur la
/// même instance — deux recherches lancées à la volée pendant la frappe (chacune relançant un
/// embedding, la précédente annulée côté Swift sans que l'appel natif déjà en cours ne s'arrête)
/// faisaient crasher tout le processus (`EXC_BAD_ACCESS` dans le moteur E5RT/BNNS d'Apple, pas
/// une erreur Swift rattrapable — observé en conditions réelles dans l'app). `ContextualEmbedder`
/// est un `actor` précisément pour sérialiser ces appels : ce test lance des dizaines d'appels
/// concurrents sur la même instance et vérifie qu'ils aboutissent tous, sans jamais planter.
@Test func manyConcurrentEmbedCallsOnTheSameInstanceNeverCrash() async throws {
    let embedder = try #require(ContextualEmbedder())
    guard await embedder.hasAvailableAssets else {
        withKnownIssue("Assets du modèle d'embeddings non téléchargés sur cette machine") {}
        return
    }

    let texts = (0..<20).map { "Requête de recherche numéro \($0), facture EDF de juillet." }
    let vectors = try await withThrowingTaskGroup(of: [Double].self) { group in
        for text in texts {
            group.addTask { try await embedder.embed(text) }
        }
        var results: [[Double]] = []
        for try await vector in group { results.append(vector) }
        return results
    }

    #expect(vectors.count == texts.count)
    #expect(vectors.allSatisfy { $0.count == 512 })
}
