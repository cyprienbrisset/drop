import DropEmbeddings
import Testing

@Test func chunksShortTextIntoASingleChunk() {
    let chunker = TextChunker()
    let chunks = chunker.chunks(forPage: 0, text: "Un texte court qui tient largement dans un seul segment.")
    #expect(chunks.count == 1)
    #expect(chunks[0].pageNumber == 0)
}

@Test func chunksLongTextIntoMultipleOverlappingSegments() {
    let chunker = TextChunker(tokensPerChunk: 10, tokenOverlap: 2) // 40 car./segment, 8 car. de recouvrement
    let text = String(repeating: "a", count: 200)
    let chunks = chunker.chunks(forPage: 0, text: text)

    #expect(chunks.count > 1)
    // Le second segment doit démarrer avant la fin du premier (recouvrement).
    #expect(chunks[1].charFrom < chunks[0].charTo)
}

@Test func breaksAtASentenceBoundaryWhenOneIsNearby() {
    let chunker = TextChunker(tokensPerChunk: 10, tokenOverlap: 0) // fenêtre de 40 caractères
    let text = "Première phrase courte. " + String(repeating: "b", count: 60)
    let chunks = chunker.chunks(forPage: 0, text: text)

    // La coupure doit tomber juste après le point de la première phrase, pas au milieu d'un mot.
    #expect(chunks[0].text.hasSuffix("."))
}

@Test func returnsNoChunksForEmptyText() {
    let chunker = TextChunker()
    #expect(chunker.chunks(forPage: 0, text: "").isEmpty)
}
