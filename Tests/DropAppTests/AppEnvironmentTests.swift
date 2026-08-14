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

/// Preuve réelle que le chemin exact suivi par la vue (`DropZoneView.handle` → `handleDrop`) mène
/// à un document réellement ingéré, analysé et retrouvable — pas seulement que les cas d'usage
/// `DropFeatures` fonctionnent isolément (déjà couvert ailleurs), mais que le bootstrap qui les
/// relie (`AppEnvironment`) le fait correctement contre un vrai coffre chiffré sur disque.
@Test @MainActor func droppingARealFileMakesItSearchableShortlyAfter() async throws {
    let environment = try makeEnvironment()
    let source = try writeSourceFile(named: "facture-edf.txt", contents: "Facture EDF juillet 2026, montant 84,20 euros")

    environment.handleDrop(of: [source])

    // L'ingestion et l'analyse tournent dans une Task détachée par `handleDrop`. La vérification
    // de stabilité EF-11 impose déjà 2 s d'attente interne avant toute écriture — on laisse une
    // marge au-delà plutôt que de coupler ce test à un mécanisme de complétion interne.
    try await Task.sleep(for: .milliseconds(3000))

    // « EDF » plutôt que « facture edf » : « facture » est un mot du dictionnaire de types
    // (EF-65) — le mot serait retiré du texte libre et transformé en filtre `doc_type = facture`,
    // que ce document ne peut pas satisfaire puisque la classification par le modèle de langage
    // n'est pas câblée dans ce pipeline (seul le sous-ensemble déterministe tourne, cf.
    // `AnalyzeDocument`). Un vrai utilisateur tomberait sur la même limite avec ce mot-clé.
    await environment.search("EDF")
    #expect(environment.searchResults.contains { $0.displayName.contains("facture-edf") })
}

@Test @MainActor func droppingTheSameFileTwiceReportsADuplicateWithoutDuplicatingTheDocument() async throws {
    let environment = try makeEnvironment()
    let source = try writeSourceFile(named: "contrat.txt", contents: "Contrat de location signé")

    environment.handleDrop(of: [source])
    try await Task.sleep(for: .milliseconds(3000))

    environment.handleDrop(of: [source])
    try await Task.sleep(for: .milliseconds(3000))

    // « location » plutôt que « contrat » : « contrat » est aussi un mot du dictionnaire de
    // types (EF-65), même limite que ci-dessus.
    await environment.search("location")
    let matches = environment.searchResults.filter { $0.displayName.contains("contrat") }
    #expect(matches.count == 1)
}

@Test @MainActor func searchingWithoutTextClearsResults() async throws {
    let environment = try makeEnvironment()
    let source = try writeSourceFile(named: "releve.txt", contents: "Relevé bancaire janvier")

    environment.handleDrop(of: [source])
    try await Task.sleep(for: .milliseconds(3000))

    // « bancaire » plutôt que « relevé » : « relevé »/« relevés » déclenchent le même filtre de
    // type que ci-dessus.
    await environment.search("bancaire")
    #expect(!environment.searchResults.isEmpty)

    await environment.search("")
    #expect(environment.searchResults.isEmpty)
}

@Test @MainActor func computeBudgetReflectsAnIngestedDocument() async throws {
    let environment = try makeEnvironment()
    let source = try writeSourceFile(named: "doc.txt", contents: String(repeating: "contenu ", count: 100))

    environment.handleDrop(of: [source])
    try await Task.sleep(for: .milliseconds(3000))

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
    try await Task.sleep(for: .milliseconds(3000))

    await environment.search("prévisualiser")
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
