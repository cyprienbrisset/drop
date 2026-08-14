import DropEntities
import Testing

private let extractor = DateExtractor()

@Test func readsSlashDateAsDayMonthYearWhenUnambiguous() {
    // 13 ne peut pas être un mois : lecture jour/mois/année sans ambiguïté.
    let results = extractor.extract(from: "Facture du 13/02/2025")
    #expect(results.contains { $0.valueDate == "2025-02-13" && $0.confidence == 1.0 })
}

@Test func readsAmbiguousSlashDateAsDayFirstPerFrenchConvention() {
    // 03/04/2025 : les deux lectures sont valides (3 avril ou 4 mars) — fr_FR lit jour/mois.
    let results = extractor.extract(from: "Le 03/04/2025")
    let readings = results.filter { $0.valueDate != nil }
    #expect(readings.count == 2) // les deux lectures sont indexées...
    #expect(readings.contains { $0.valueDate == "2025-04-03" && $0.confidence == 0.6 })
    #expect(readings.contains { $0.valueDate == "2025-03-04" && $0.confidence == 0.6 })
}

@Test func readsISODateWithoutAmbiguity() {
    let results = extractor.extract(from: "Créé le 2025-07-14")
    #expect(results.contains { $0.valueDate == "2025-07-14" && $0.confidence == 1.0 })
}

@Test func readsDottedDateFormat() {
    let results = extractor.extract(from: "Le 25.12.2025")
    #expect(results.contains { $0.valueDate == "2025-12-25" && $0.confidence == 1.0 })
}

@Test func readsFullTextualDate() {
    let results = extractor.extract(from: "Signé le 12 mars 2025")
    #expect(results.contains { $0.valueDate == "2025-03-12" })
}

@Test func readsMonthAndYearOnly() {
    let results = extractor.extract(from: "Facture de mars 2025")
    #expect(results.contains { $0.valueDate == "2025-03-01" })
}

@Test func rejectsAnInvalidCalendarDate() {
    let results = extractor.extract(from: "Le 31/02/2025") // février n'a jamais 31 jours.
    #expect(results.isEmpty)
}
