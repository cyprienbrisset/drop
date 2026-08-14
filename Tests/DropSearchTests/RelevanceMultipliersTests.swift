import DropSearch
import Testing

@Test func noSignalsMeansNoMultiplier() {
    #expect(RelevanceMultipliers.multiplier(for: RelevanceSignals()) == 1.0)
}

@Test func exactFilenameMatchAppliesOnePointFour() {
    let signals = RelevanceSignals(exactFilenameMatch: true)
    #expect(RelevanceMultipliers.multiplier(for: signals) == 1.4)
}

@Test func exactEntityMatchAppliesOnePointThree() {
    let signals = RelevanceSignals(exactEntityMatch: true)
    #expect(RelevanceMultipliers.multiplier(for: signals) == 1.3)
}

@Test func recencyMultiplierApproachesOnePointFifteenForFreshDocuments() {
    let signals = RelevanceSignals(ageInDays: 0)
    #expect(abs(RelevanceMultipliers.multiplier(for: signals) - 1.15) < 1e-9)
}

@Test func recencyMultiplierApproachesOneForOldDocuments() {
    let signals = RelevanceSignals(ageInDays: 3650) // 10 ans
    #expect(RelevanceMultipliers.multiplier(for: signals) < 1.001)
}

@Test func openedRecentlyAppliesOnePointOne() {
    let signals = RelevanceSignals(openedRecently: true)
    #expect(RelevanceMultipliers.multiplier(for: signals) == 1.10)
}

@Test func lowOCRConfidenceAppliesZeroPointEightFive() {
    let signals = RelevanceSignals(lowOCRConfidenceOnMatchedPage: true)
    #expect(RelevanceMultipliers.multiplier(for: signals) == 0.85)
}

@Test func combinedMultipliersAreCappedAtTwo() {
    let signals = RelevanceSignals(
        exactFilenameMatch: true, exactEntityMatch: true, ageInDays: 0, openedRecently: true
    )
    // 1.4 * 1.3 * 1.15 * 1.10 ≈ 2.30, plafonné à 2.0.
    #expect(RelevanceMultipliers.multiplier(for: signals) == 2.0)
}
