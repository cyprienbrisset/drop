import DropSearch
import Testing

@Test func thresholdKeepsResultsAboveThirtyFivePercentOfBestScore() {
    let scores = ["a": 1.0, "b": 0.4, "c": 0.2]
    let result = RelevanceThreshold.apply(to: scores, absoluteFloor: 0.0)
    #expect(Set(result.keys) == ["a", "b"])
}

@Test func thresholdDropsEverythingBelowTheAbsoluteFloorEvenIfRelativelyClose() {
    // Deux résultats très faibles mais proches entre eux : le seuil relatif seul les garderait
    // tous, le plancher absolu doit les éliminer.
    let scores = ["a": 0.001, "b": 0.0009]
    let result = RelevanceThreshold.apply(to: scores, absoluteFloor: 0.01)
    #expect(result.isEmpty)
}

@Test func thresholdReturnsNothingWhenAllScoresAreZeroOrNegative() {
    let scores = ["a": 0.0, "b": -1.0]
    let result = RelevanceThreshold.apply(to: scores)
    #expect(result.isEmpty)
}

@Test func thresholdOnEmptyInputReturnsEmpty() {
    #expect(RelevanceThreshold.apply(to: [:]).isEmpty)
}
