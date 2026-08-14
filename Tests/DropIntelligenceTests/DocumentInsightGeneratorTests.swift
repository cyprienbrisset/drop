import DropIntelligence
import Testing

/// La disponibilité réelle du modèle dépend du matériel/compte Apple Intelligence de la machine
/// qui exécute ces tests — non garantie dans un environnement virtualisé/CI (cf. §5.4.5, DRO-16).
/// On vérifie ce qu'on peut vérifier sans le modèle (le schéma compile, l'énumération existe) et
/// on documente l'appel réel comme `withKnownIssue` s'il échoue faute de disponibilité.
@Test func documentTypeCoversAllExpectedCases() {
    let rawValues = Set(DocumentType.allCases.map(\.rawValue))
    #expect(rawValues.contains("facture"))
    #expect(rawValues.contains("autre"))
    #expect(DocumentType.allCases.count == 16)
}

@Test func generatorReportsSystemAvailability() {
    let generator = DocumentInsightGenerator()
    // On n'attend rien de précis (dépend de la machine) — seulement que l'appel ne plante pas.
    _ = generator.availability
}

@Test func generatingAnInsightFromRealTextEitherSucceedsOrIsAKnownEnvironmentLimitation() async {
    await withKnownIssue("Apple Intelligence peut être indisponible sur cette machine/CI (§5.4.4)", isIntermittent: true) {
        let generator = DocumentInsightGenerator()
        let insight = try await generator.generate(
            fromText: "Facture EDF. Montant à régler 84,20 euros. Merci de votre confiance."
        )
        #expect(!insight.summary.isEmpty)
        #expect(insight.keywords.count >= 3)
    }
}
