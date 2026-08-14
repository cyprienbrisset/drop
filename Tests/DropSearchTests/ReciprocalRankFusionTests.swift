import DropSearch
import Testing

@Test func rrfFavorsDocumentRankedFirstInMultipleLists() {
    let rrf = ReciprocalRankFusion()
    let scores = rrf.fuse(rankedLists: [
        "lexical": [RankedDocument(documentID: "doc-a", rank: 1), RankedDocument(documentID: "doc-b", rank: 2)],
        "semantic": [RankedDocument(documentID: "doc-a", rank: 1), RankedDocument(documentID: "doc-c", rank: 1)],
    ])

    #expect((scores["doc-a"] ?? 0) > (scores["doc-b"] ?? 0))
    #expect((scores["doc-a"] ?? 0) > (scores["doc-c"] ?? 0))
}

@Test func rrfIgnoresDocumentsAbsentFromAllLists() {
    let rrf = ReciprocalRankFusion()
    let scores = rrf.fuse(rankedLists: ["lexical": [RankedDocument(documentID: "doc-a", rank: 1)]])
    #expect(scores["doc-z"] == nil)
}
