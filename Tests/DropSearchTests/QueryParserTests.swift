import DropCore
import DropSearch
import Foundation
import Testing

private struct FixedClock: DropClock {
    let date: Date
    func now() -> Date { date }
}

// "Aujourd'hui" fixé au 14 août 2026 pour des tests de dates relatives déterministes.
private let referenceDate = ISO8601DateFormatter().date(from: "2026-08-14T10:00:00Z")!
private let parser = QueryParser(clock: FixedClock(date: referenceDate))

@Test func parsesExactPhrases() {
    let result = parser.parse("\"attestation de vigilance\" URSSAF")
    #expect(result.phrases == ["attestation de vigilance"])
    #expect(result.freeText == "URSSAF")
}

@Test func parsesExclusionAndDocType() {
    let result = parser.parse("relevé banque -crédit agricole")
    #expect(result.docTypes == ["releveBancaire"])
    #expect(result.excluded == ["crédit"])
    #expect(result.freeText.contains("banque"))
}

@Test func parsesTagsAndExplicitTypeFilter() {
    let result = parser.parse("#urgent type:pdf rapport")
    #expect(result.tags == ["urgent"])
    #expect(result.fileKinds == ["pdf"])
    #expect(result.freeText == "rapport")
}

@Test func parsesExplicitDateBoundary() {
    let result = parser.parse("avant:2025-03-01 contrat")
    #expect(result.dateRange?.end == ISO8601DateFormatter().date(from: "2025-03-01T00:00:00Z"))
    #expect(result.docTypes == ["contrat"])
}

@Test func parsesAmountGreaterThan() {
    let result = parser.parse("factures de plus de 500 € signées")
    #expect(result.amountRange?.lowerBound == 500)
    #expect(result.currency == "EUR")
    #expect(result.docTypes == ["facture"])
}

@Test func parsesAmountLessThan() {
    let result = parser.parse("moins de 100")
    #expect(result.amountRange == 0...100)
}

@Test func parsesAmountBetween() {
    let result = parser.parse("entre 100 et 300 €")
    #expect(result.amountRange == 100...300)
    #expect(result.currency == "EUR")
}

@Test func parsesApproximateAmountWithTenPercentTolerance() {
    let result = parser.parse("environ 50 €")
    #expect(result.amountRange?.lowerBound == 45)
    #expect(result.amountRange?.upperBound == 55)
}

@Test func parsesFactureEDFDeJuillet() {
    let result = parser.parse("facture EDF de juillet")
    #expect(result.docTypes == ["facture"])
    #expect(result.freeText == "EDF")

    let expectedStart = referenceCalendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
    let expectedEnd = referenceCalendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
    #expect(result.dateRange?.start == expectedStart)
    #expect(result.dateRange?.end == expectedEnd)
}

@Test func parsesContractsAboveAmountInYear() {
    let result = parser.parse("contrats de plus de 500 € signés en 2024")
    #expect(result.docTypes == ["contrat"])
    #expect(result.amountRange?.lowerBound == 500)
    let expectedStart = referenceCalendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    let expectedEnd = referenceCalendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
    #expect(result.dateRange == DateInterval(start: expectedStart, end: expectedEnd))
    #expect(result.freeText.contains("signés"))
}

@Test func parsesToday() {
    let result = parser.parse("aujourd'hui")
    #expect(result.dateRange?.start == referenceCalendar.startOfDay(for: referenceDate))
}

@Test func parsesYesterday() {
    let result = parser.parse("hier")
    let yesterday = referenceCalendar.date(byAdding: .day, value: -1, to: referenceDate)!
    #expect(result.dateRange?.start == referenceCalendar.startOfDay(for: yesterday))
}

@Test func parsesLastMonth() {
    let result = parser.parse("le mois dernier")
    // Référence : 14 août 2026 → le mois dernier est juillet 2026.
    let expectedStart = referenceCalendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
    #expect(result.dateRange?.start == expectedStart)
}

@Test func parsesMonthsAgo() {
    let result = parser.parse("il y a 3 mois")
    // Référence : août 2026 → il y a 3 mois = mai 2026.
    let expectedStart = referenceCalendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
    #expect(result.dateRange?.start == expectedStart)
}

@Test func parsesBareYear() {
    let result = parser.parse("2025")
    let expectedStart = referenceCalendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
    let expectedEnd = referenceCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    #expect(result.dateRange == DateInterval(start: expectedStart, end: expectedEnd))
}

@Test func parsesBeforeYear() {
    let result = parser.parse("avant 2024")
    let expectedEnd = referenceCalendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    #expect(result.dateRange?.end == expectedEnd)
}

@Test func parsesMonthRange() {
    let result = parser.parse("entre mars et juin")
    let expectedStart = referenceCalendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
    #expect(result.dateRange?.start == expectedStart)
    // La borne de fin doit couvrir tout le mois de juin.
    let juneEnd = referenceCalendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
    #expect(result.dateRange?.end == juneEnd)
}

private var referenceCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}
