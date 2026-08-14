import DropEntities
import Testing

private let dictionary = IssuerDictionary()

@Test func matchesAKnownEnergyProvider() {
    let results = dictionary.match(in: "Facture EDF de juillet 2026, montant à régler 84,20 €.")
    #expect(results.contains { $0.kind == .org && $0.valueText == "EDF" })
}

@Test func matchesCaseInsensitively() {
    let results = dictionary.match(in: "facture orange mobile du mois")
    #expect(results.contains { $0.valueText == "Orange" })
}

@Test func matchesAnAliasToItsCanonicalName() {
    let results = dictionary.match(in: "Attestation Pole Emploi jointe.")
    #expect(results.contains { $0.valueText == "France Travail" })
}

@Test func matchesSeveralOrganizationsInTheSameDocument() {
    let results = dictionary.match(in: "Virement Société Générale suite à remboursement AXA.")
    let names = Set(results.map(\.valueText))
    #expect(names.contains("Société Générale"))
    #expect(names.contains("AXA"))
}

@Test func doesNotMatchUnrelatedText() {
    let results = dictionary.match(in: "Ceci est un simple mémo personnel sans émetteur connu.")
    #expect(results.isEmpty)
}

@Test func matchesOnlyWholeWordsNotSubstrings() {
    // "Orangeade" ne doit pas déclencher un faux positif sur "Orange".
    let results = dictionary.match(in: "Recette : préparer une orangeade fraîche.")
    #expect(!results.contains { $0.valueText == "Orange" })
}
