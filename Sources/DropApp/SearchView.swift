import QuickLook
import SwiftUI

/// Barre de recherche globale + résultats (EX-02, EF-60, EF-67), type Spotlight. Navigation
/// clavier intégrale (EX-04) : ↑↓ sélection (gérée nativement par `List`), ↵ ouvrir, ⌘↵ révéler
/// dans le Finder, Espace Quick Look, ⌘⌫ retirer, double-clic pour la fiche détaillée
/// (`DocumentDetailView`, EX-03). Recherche en direct : chaque frappe relance
/// `environment.search` après un court débounce (150 ms), sans jamais réordonner sous le focus
/// clavier — `List` conserve la sélection par identifiant, pas par position.
struct SearchView: View {
    let environment: AppEnvironment

    @State private var queryText: String = ""
    @State private var selection: String?
    @State private var quickLookURL: URL?
    @State private var detailResult: DocumentSearchResult?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Rechercher un document…", text: $queryText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFieldFocused)
                if environment.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            if queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Tapez pour rechercher",
                    systemImage: "magnifyingglass",
                    description: Text("« la facture EDF de juillet », « contrats en 2024 »…")
                )
                .frame(maxHeight: .infinity)
            } else if environment.searchResults.isEmpty && !environment.isSearching {
                ContentUnavailableView(
                    "Aucun résultat pertinent",
                    systemImage: "magnifyingglass",
                    description: Text("Essayez une autre formulation.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(environment.searchResults, selection: $selection) { result in
                    DocumentResultRow(result: result)
                        .tag(result.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { detailResult = result }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .task(id: queryText) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await environment.search(queryText)
        }
        .onAppear { isSearchFieldFocused = true }
        // Tous ces raccourcis n'agissent que si le champ de recherche n'a pas le focus — sinon
        // Espace (le plus visible : impossible de taper une requête à plusieurs mots), Retour et
        // ⌘⌫ seraient volés à la saisie de texte normale dès qu'une ligne se trouve sélectionnée.
        .onKeyPress(.return) {
            guard !isSearchFieldFocused else { return .ignored }
            performOnSelection(environment.open)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard !isSearchFieldFocused, press.modifiers.contains(.command) else { return .ignored }
            performOnSelection(environment.reveal)
            return .handled
        }
        .onKeyPress(.space) {
            guard !isSearchFieldFocused else { return .ignored }
            quickLookURL = selectedResult?.previewURL
            return .handled
        }
        .onKeyPress(.deleteForward, phases: .down) { press in
            guard !isSearchFieldFocused, press.modifiers.contains(.command) else { return .ignored }
            performOnSelection(environment.remove)
            return .handled
        }
        .quickLookPreview($quickLookURL)
        .sheet(item: $detailResult) { result in
            DocumentDetailView(
                result: result,
                onOpen: { environment.open(result) },
                onReveal: { environment.reveal(result) },
                onExport: { environment.export(result) },
                onRemove: {
                    environment.remove(result)
                    detailResult = nil
                },
                onCorrectType: { newType in
                    environment.correctType(result, to: newType)
                    detailResult?.docType = newType
                },
                onCorrectIssuer: { newIssuer in
                    environment.correctIssuer(result, to: newIssuer)
                    detailResult?.issuer = newIssuer
                },
                onCorrectEffectiveDate: { newDate in
                    environment.correctEffectiveDate(result, to: newDate)
                    detailResult?.effectiveDate = newDate
                },
                onAddTag: { newTag in
                    environment.addTag(result, name: newTag)
                    let normalized = newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !normalized.isEmpty, detailResult?.tags.contains(normalized) == false {
                        detailResult?.tags.append(normalized)
                        detailResult?.tags.sort()
                    }
                },
                onRemoveTag: { tag in
                    environment.removeTag(result, name: tag)
                    detailResult?.tags.removeAll { $0 == tag }
                }
            )
        }
    }

    private var selectedResult: DocumentSearchResult? {
        environment.searchResults.first { $0.id == selection }
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
                .accessibilityHidden(true)
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
        // EX-09/ENF-40 : une seule annonce cohérente par ligne (nom, type, résumé) plutôt que des
        // éléments disjoints — VoiceOver ajoute déjà la position dans la liste automatiquement.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SearchView(environment: try! AppEnvironment(vaultRoot: FileManager.default.temporaryDirectory.appendingPathComponent("drop-preview")))
}
