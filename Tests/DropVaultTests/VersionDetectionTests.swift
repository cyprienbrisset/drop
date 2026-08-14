import DropVault
import Testing

@Test func levenshteinDistanceOfIdenticalStringsIsZero() {
    #expect(VersionDetection.levenshteinDistance("facture-edf", "facture-edf") == 0)
}

@Test func levenshteinDistanceCountsEdits() {
    #expect(VersionDetection.levenshteinDistance("facture-edf-v1", "facture-edf-v2") == 1)
    #expect(VersionDetection.levenshteinDistance("kitten", "sitting") == 3)
}

@Test func isLikelyVersionAcceptsCloseNameAndSize() {
    let result = VersionDetection.isLikelyVersion(
        nameA: "facture-edf-v1.pdf", sizeA: 100_000,
        nameB: "facture-edf-v2.pdf", sizeB: 110_000
    )
    #expect(result)
}

@Test func isLikelyVersionRejectsDistantNames() {
    let result = VersionDetection.isLikelyVersion(
        nameA: "facture-edf.pdf", sizeA: 100_000,
        nameB: "contrat-location.pdf", sizeB: 100_000
    )
    #expect(!result)
}

@Test func isLikelyVersionRejectsSizeBeyondTolerance() {
    let result = VersionDetection.isLikelyVersion(
        nameA: "facture.pdf", sizeA: 100_000,
        nameB: "facture.pdf", sizeB: 200_000
    )
    #expect(!result) // même radical (distance 0), mais +100 % de taille : hors tolérance ±25 %.
}
