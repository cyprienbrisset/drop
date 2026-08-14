import QuickLook
import SwiftUI

/// Barre de recherche globale + résultats (EX-02, EF-60, EF-67). Navigation clavier intégrale
/// (EX-04) : ↑↓ sélection (gérée nativement par `List`), ↵ ouvrir, ⌘↵ révéler dans le Finder,
/// Espace Quick Look, ⌘⌫ retirer.
///
/// Note de portée : reçoit ses résultats en paramètre plutôt que d'interroger un moteur de
/// recherche vivant — le bootstrap applicatif reliant cette vue à `DropFeatures.LexicalSearch`
/// n'existe pas encore (même limite que `PreferencesView`). L'affichage progressif (lexical
/// d'abord, sémantique fusionné ensuite, sans déplacer l'élément sous le focus) est la
/// responsabilité de l'appelant qui met à jour `results` au fil de l'eau : cette vue se contente
/// de ne jamais réordonner silencieusement sous la sélection courante.
struct SearchView: View {
    @State private var queryText: String = ""
    @State private var selection: String?
    @State private var quickLookURL: URL?

    let results: [DocumentSearchResult]
    var onOpen: (DocumentSearchResult) -> Void = { _ in }
    var onReveal: (DocumentSearchResult) -> Void = { _ in }
    var onRemove: (DocumentSearchResult) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Rechercher un document…", text: $queryText)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)

            Divider()

            if results.isEmpty {
                ContentUnavailableView(
                    "Aucun résultat pertinent",
                    systemImage: "magnifyingglass",
                    description: Text("Essayez une autre formulation.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(results, selection: $selection) { result in
                    DocumentResultRow(result: result)
                        .tag(result.id)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .onKeyPress(.return) {
            performOnSelection(onOpen)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            performOnSelection(onReveal)
            return .handled
        }
        .onKeyPress(.space) {
            quickLookURL = selectedResult?.previewURL
            return .handled
        }
        .onKeyPress(.deleteForward, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            performOnSelection(onRemove)
            return .handled
        }
        .quickLookPreview($quickLookURL)
    }

    private var selectedResult: DocumentSearchResult? {
        results.first { $0.id == selection }
    }

    private func performOnSelection(_ action: (DocumentSearchResult) -> Void) {
        guard let result = selectedResult else { return }
        action(result)
    }
}

private struct DocumentResultRow: View {
    let result: DocumentSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .font(.body)
                if let summary = result.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let docType = result.docType {
                Text(docType)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SearchView(results: [
        DocumentSearchResult(
            id: "1", displayName: "Facture EDF juillet.pdf", docType: "facture", issuer: "EDF",
            effectiveDate: .now, amount: 84.20, keywords: ["électricité"], summary: "Facture d'électricité de juillet.",
            tags: [], originalPath: "/Users/exemple/Downloads/facture.pdf", sizeBytes: 245_000,
            hash: "abcdef0123456789", previewURL: nil
        )
    ])
}
