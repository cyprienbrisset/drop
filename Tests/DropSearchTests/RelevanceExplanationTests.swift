import DropSearch
import Testing

@Test func explanationMentionsExactFilenameMatchFirst() {
    let signals = RelevanceSignals(exactFilenameMatch: true)
    let reasons = RelevanceExplanation.describe(signals: signals, matchedGenerators: ["lexical"])
    #expect(reasons.first == "Le nom du fichier correspond exactement à la recherche")
}

@Test func explanationMentionsLexicalMatchOverSemanticWhenBothPresent() {
    let reasons = RelevanceExplanation.describe(signals: RelevanceSignals(), matchedGenerators: ["lexical", "semantic"])
    #expect(reasons.contains("Contient les mots recherchés"))
    #expect(!reasons.contains("Le contenu correspond au sens de la recherche"))
}

@Test func explanationMentionsSemanticOnlyWhenLexicalAbsent() {
    let reasons = RelevanceExplanation.describe(signals: RelevanceSignals(), matchedGenerators: ["semantic"])
    #expect(reasons.contains("Le contenu correspond au sens de la recherche"))
}

@Test func explanationMentionsRecencyForFreshDocuments() {
    let reasons = RelevanceExplanation.describe(signals: RelevanceSignals(ageInDays: 2), matchedGenerators: [])
    #expect(reasons.contains("Document récent"))
}

@Test func explanationFallsBackToGenericReasonWhenNoSignalMatches() {
    let reasons = RelevanceExplanation.describe(signals: RelevanceSignals(), matchedGenerators: [])
    #expect(reasons == ["Correspond à la recherche"])
}
