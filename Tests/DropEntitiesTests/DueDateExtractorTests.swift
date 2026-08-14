import DropEntities
import Testing

@Test func extractsADueDateFollowingAnExplicitDeadlinePhrase() throws {
    let text = "Merci de régler cette facture. Date limite de paiement : 15/03/2030. Montant TTC : 120,00 €"
    let entities = DueDateExtractor().extract(from: text)

    #expect(entities.count == 1)
    #expect(entities.first?.kind == .dueDate)
    #expect(entities.first?.valueDate == "2030-03-15")
}

@Test func extractsADueDateFromAnEcheanceKeyword() throws {
    let text = "Échéance le 1 avril 2030, sans quoi des pénalités s'appliquent."
    let entities = DueDateExtractor().extract(from: text)

    #expect(entities.contains { $0.valueDate == "2030-04-01" })
}

@Test func aBareDateWithoutAnyContextKeywordIsNeverReportedAsADueDate() throws {
    let text = "Facture émise le 03/04/2030 pour la période de mars."
    let entities = DueDateExtractor().extract(from: text)

    #expect(entities.isEmpty)
}

@Test func theSameDateMatchedByTwoOverlappingKeywordsIsReportedOnlyOnce() throws {
    // Jour > 12 : lecture jour/mois non ambiguë, une seule date candidate en sortie.
    let text = "Merci de régler avant le 20/05/2030."
    let entities = DueDateExtractor().extract(from: text)

    #expect(entities.count == 1)
    #expect(entities.first?.valueDate == "2030-05-20")
}

@Test func multipleDistinctDueDatesInTheSameDocumentAreAllReported() throws {
    let text = "Premier versement : date limite 15/02/2030. Second versement : échéance le 20/03/2030."
    let entities = DueDateExtractor().extract(from: text)

    let dates = Set(entities.compactMap(\.valueDate))
    #expect(dates == ["2030-02-15", "2030-03-20"])
}
