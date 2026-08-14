import QuickLook
import SwiftUI

/// Fiche document (EX-03) : aperçu, nom, type, émetteur, dates, montants, mots-clés, résumé,
/// tags, chemin d'origine, taille, hash abrégé, actions (ouvrir, révéler l'original, exporter,
/// corriger, retirer). Le vocabulaire reflète partout la propriété (EX-05) : jamais « supprimer »
/// pour une action réversible.
struct DocumentDetailView: View {
    let result: DocumentSearchResult
    var onOpen: () -> Void = {}
    var onReveal: () -> Void = {}
    var onExport: () -> Void = {}
    var onRemove: () -> Void = {}

    @State private var quickLookURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                fields
                Divider()
                actions
            }
            .padding(20)
        }
        .frame(minWidth: 380, minHeight: 420)
        .quickLookPreview($quickLookURL)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.displayName)
                .font(.title3.bold())
            if let summary = result.summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            field("Type", result.docType ?? "non déterminé")
            field("Émetteur", result.issuer ?? "inconnu")
            if let date = result.effectiveDate {
                field("Date", date.formatted(date: .long, time: .omitted))
            }
            if let amount = result.amount {
                field("Montant", amount.formatted(.currency(code: "EUR")))
            }
            if !result.keywords.isEmpty {
                field("Mots-clés", result.keywords.joined(separator: ", "))
            }
            if !result.tags.isEmpty {
                field("Tags", result.tags.joined(separator: ", "))
            }
            field("Chemin d'origine", result.originalPath ?? "non conservé")
            field("Taille", DocumentSearchResult.formattedSize(result.sizeBytes))
            field("Empreinte", result.shortHash)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.callout)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Ouvrir") { onOpen() }
            Button("Aperçu") { quickLookURL = result.previewURL }
                .disabled(result.previewURL == nil)
            Button("Révéler dans le Finder") { onReveal() }
            Button("Exporter…") { onExport() }
            Spacer()
            Button("Retirer du coffre", role: .destructive) { onRemove() }
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    DocumentDetailView(
        result: DocumentSearchResult(
            id: "1", displayName: "Facture EDF juillet.pdf", docType: "facture", issuer: "EDF",
            effectiveDate: .now, amount: 84.20, keywords: ["électricité", "facture"], summary: "Facture d'électricité de juillet.",
            tags: ["maison"], originalPath: "/Users/exemple/Downloads/facture.pdf", sizeBytes: 245_000,
            hash: "abcdef0123456789", previewURL: nil
        )
    )
}
