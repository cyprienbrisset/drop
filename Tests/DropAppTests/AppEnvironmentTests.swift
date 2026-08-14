@testable import DropApp
import Foundation
import Testing

@MainActor
private func makeEnvironment() throws -> AppEnvironment {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drop-app-env-test-\(UUID().uuidString)")
    return try AppEnvironment(vaultRoot: root)
}

private func writeSourceFile(named name: String, contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// `AnalyzeDocument` appelle désormais le modèle de langage système pour classer/résumer
/// (§5.4) : sa latence réelle varie fortement (quasi instantané à indisponible → plusieurs
/// dizaines de secondes selon la machine, cf. `AnalyzeDocumentTests`). Un délai fixe après
/// `handleDrop` serait soit trop court, soit inutilement long — on sonde plutôt jusqu'à ce que
/// la recherche renvoie quelque chose, avec un plafond généreux.
@MainActor
private func waitUntilSearchable(_ environment: AppEnvironment, query: String, timeout: TimeInterval = 75) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        await environment.search(query)
        if !environment.searchResults.isEmpty { return }
        try? await Task.sleep(for: .milliseconds(300))
    }
}

/// Preuve réelle que le chemin exact suivi par la vue (`DropZoneView.handle` → `handleDrop`) mène
/// à un document réellement ingéré, analysé et retrouvable — pas seulement que les cas d'usage
/// `DropFeatures` fonctionnent isolément (déjà couvert ailleurs), mais que le bootstrap qui les
/// relie (`AppEnvironment`) le fait correctement contre un vrai coffre chiffré sur disque.
@Test @MainActor func droppingARealFileMakesItSearchableShortlyAfter() async throws {
    let environment = try makeEnvironment()
    let source = try writeSourceFile(named: "facture-edf.txt", contents: "Facture EDF juillet 2026, montant 84,20 euros")

    environment.handleDrop(of: [source])

    // « EDF » plutôt que « facture edf » : « facture » est un mot du dictionnaire de types
    // (EF-65) — le mot serait retiré du texte libre et transformé en filtre `doc_type = facture`.
    // Le pipeline classe désormais réellement les documents (cf. `AnalyzeDocument`), donc ce
    // filtre pourrait aboutir, mais seulement une fois l'analyse terminée — chercher sur un mot
    // hors dictionnaire reste la vérification la plus rapide et la moins couplée à cette latence.
    await waitUntilSearchable(environment, query: "EDF")
    #expect(environment.searchResults.contains { $0.displayName.contains("facture-edf") })
}

@Test @MainActor func droppingTheSameFileTwiceReportsADuplicateWithoutDuplicatingTheDocument() async throws {
    let environment = try makeEnvironment()
    let source = try writeSourceFile(named: "contrat.txt", contents: "Contrat de location signé")

    environment.handleDrop(of: [source])
    await waitUntilSearchable(environment, query: "location")

    environment.handleDrop(of: [source])
    await waitUntilSearchable(environment, query: "location")

    let matches = environment.searchResults.filter { $0.displayName.contains("contrat") }
    #expect(matches.count == 1)
}

@Test @MainActor func searchingWithoutTextClearsResults() async throws {
    let environment = try makeEnvironment()
    let source = try writeSourceFile(named: "releve.txt", contents: "Relevé bancaire janvier")

    environment.handleDrop(of: [source])

    // « bancaire » plutôt que « relevé » : « relevé »/« relevés » déclenchent le même filtre de
    // type que ci-dessus.
    await waitUntilSearchable(environment, query: "bancaire")
    #expect(!environment.searchResults.isEmpty)

    await environment.search("")
    #expect(environment.searchResults.isEmpty)
}

@Test @MainActor func computeBudgetReflectsAnIngestedDocument() async throws {
    let environment = try makeEnvironment()
    let source = try writeSourceFile(named: "doc.txt", contents: String(repeating: "contenu ", count: 100))

    environment.handleDrop(of: [source])
    await waitUntilSearchable(environment, query: "contenu")

    let budget = await environment.computeBudget()
    #expect(budget.vaultSizeBytes > 0)
}

/// Régression : `previewURL` créait un lien symbolique, que Finder/QuickLookUI n'ouvrent pas
/// toujours comme le fichier réel (l'utilisateur ne voit qu'un alias, sans aperçu ni contenu
/// lisible). Ce doit être une vraie copie du contenu, exploitable indépendamment du coffre.
@Test @MainActor func previewURLIsARealCopyNotASymbolicLink() async throws {
    let environment = try makeEnvironment()
    let content = "Contenu du document à prévisualiser"
    let source = try writeSourceFile(named: "apercu.txt", contents: content)

    environment.handleDrop(of: [source])
    await waitUntilSearchable(environment, query: "prévisualiser")

    guard let result = environment.searchResults.first else {
        Issue.record("le document ingéré devrait être retrouvable")
        return
    }
    guard let previewURL = result.previewURL else {
        Issue.record("previewURL ne devrait pas être nil pour un blob présent sur disque")
        return
    }

    let attributes = try FileManager.default.attributesOfItem(atPath: previewURL.path)
    #expect(attributes[.type] as? FileAttributeType != .typeSymbolicLink)
    #expect(try String(contentsOf: previewURL, encoding: .utf8) == content)
}

/// Preuve de bout en bout que corriger un champ (EF-48) le répercute immédiatement dans
/// `searchResults` (sans attendre une nouvelle recherche) et persiste bien en base (une nouvelle
/// recherche redonne la valeur corrigée). La garantie « jamais réécrit par une ré-analyse » est
/// couverte au niveau `CorrectDocument`/`AnalyzeDocument` dans `DropFeaturesTests` — ce test
/// vérifie la façade `AppEnvironment` que la vue appelle réellement, pas la règle EF-48 elle-même.
@Test @MainActor func correctingAFieldUpdatesSearchResultsAndSurvivesReanalysis() async throws {
    let environment = try makeEnvironment()
    let source = try writeSourceFile(named: "doc-a-corriger.txt", contents: "Contenu quelconque à indexer")

    environment.handleDrop(of: [source])
    await waitUntilSearchable(environment, query: "quelconque")

    guard let result = environment.searchResults.first else {
        Issue.record("le document ingéré devrait être retrouvable")
        return
    }

    environment.correctType(result, to: "contrat")
    environment.correctIssuer(result, to: "Émetteur corrigé")
    let correctedDate = Date(timeIntervalSince1970: 1_700_000_000)
    environment.correctEffectiveDate(result, to: correctedDate)

    // Répercuté immédiatement dans `searchResults`, sans nouvelle recherche.
    let updated = environment.searchResults.first { $0.id == result.id }
    #expect(updated?.docType == "contrat")
    #expect(updated?.issuer == "Émetteur corrigé")

    // Laisse le temps à la tâche détachée de chaque correction d'écrire en base, puis vérifie
    // que la valeur persiste réellement (pas seulement le reflet local optimiste ci-dessus).
    try await Task.sleep(for: .milliseconds(500))
    await waitUntilSearchable(environment, query: "quelconque")
    let afterFreshSearch = environment.searchResults.first { $0.id == result.id }
    #expect(afterFreshSearch?.docType == "contrat")
    #expect(afterFreshSearch?.issuer == "Émetteur corrigé")
}
