import DropEntities
import Testing

private let extractor = AmountExtractor()

@Test func extractsAmountWithThousandsSeparatorAndSuffixSymbol() {
    let results = extractor.extract(from: "Montant total : 1 234,56 €")
    #expect(results.contains { $0.valueNum == 1234.56 && $0.currency == "EUR" })
}

@Test func extractsAmountWithDotThousandsSeparatorAndISOCode() {
    let results = extractor.extract(from: "Montant : 1.234,56 EUR")
    #expect(results.contains { $0.valueNum == 1234.56 })
}

@Test func extractsAmountWithPrefixSymbolAndDotDecimal() {
    let results = extractor.extract(from: "Prix: €1234.56")
    #expect(results.contains { $0.valueNum == 1234.56 })
}

@Test func extractsBareAmountNearAKeyword() {
    let results = extractor.extract(from: "Net à payer 89,90")
    #expect(results.contains { $0.valueNum == 89.90 })
}

@Test func rejectsAQuantityFollowedByANonMonetaryUnit() {
    let results = extractor.extract(from: "Total 12 kg de marchandises")
    #expect(!results.contains { $0.valueNum == 12 })
}

@Test func doesNotMistakeAPhoneNumberOrPostalCodeForAnAmount() {
    let results = extractor.extract(from: "Téléphone : 01 23 45 67 89. Code postal 75000.")
    #expect(results.isEmpty)
}

@Test func doesNotMistakeAnIsolatedYearForAnAmount() {
    let results = extractor.extract(from: "Document daté de 2024, référence 2024-001.")
    #expect(results.isEmpty)
}

@Test func principalAmountPrefersTheKeywordAnchoredOne() {
    let results = extractor.extract(from: "Sous-total 50,00 €. Net à payer 89,90 €.")
    let principal = extractor.principalAmount(among: results)
    #expect(principal?.valueNum == 89.90)
}

@Test func normalizesFrenchAndAnglicizedSeparatorsIdentically() {
    #expect(AmountExtractor.normalizeAmount("1 234,56") == 1234.56)
    #expect(AmountExtractor.normalizeAmount("1.234,56") == 1234.56)
    #expect(AmountExtractor.normalizeAmount("1234.56") == 1234.56)
    #expect(AmountExtractor.normalizeAmount("1234,56") == 1234.56)
}
