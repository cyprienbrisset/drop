import DropIntelligence
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
    var onCorrectType: (String) -> Void = { _ in }
    var onCorrectIssuer: (String) -> Void = { _ in }
    var onCorrectEffectiveDate: (Date) -> Void = { _ in }

    @State private var quickLookURL: URL?
    @State private var isCorrecting = false
    @State private var editedTypeRawValue: String = DocumentType.autre.rawValue
    @State private var editedIssuer: String = ""
    @State private var editedDate: Date = .now

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                fields
                if isCorrecting {
                    Divider()
                    correctionForm
                }
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
        // EX-09/ENF-40 : « Type, facture » plutôt que deux éléments VoiceOver disjoints.
        .accessibilityElement(children: .combine)
    }

    /// EF-48 : une correction verrouille définitivement le champ contre toute réécriture
    /// automatique ultérieure — jamais discrète, toujours un geste explicite de l'utilisateur.
    private var correctionForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Corriger")
                .font(.headline)

            Picker("Type", selection: $editedTypeRawValue) {
                ForEach(DocumentType.allCases, id: \.rawValue) { type in
                    Text(type.rawValue).tag(type.rawValue)
                }
            }
            TextField("Émetteur", text: $editedIssuer)
                .textFieldStyle(.roundedBorder)
            DatePicker("Date", selection: $editedDate, displayedComponents: .date)

            HStack {
                Spacer()
                Button("Annuler") { isCorrecting = false }
                Button("Valider") {
                    onCorrectType(editedTypeRawValue)
                    if !editedIssuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onCorrectIssuer(editedIssuer)
                    }
                    onCorrectEffectiveDate(editedDate)
                    isCorrecting = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            editedTypeRawValue = result.docType ?? DocumentType.autre.rawValue
            editedIssuer = result.issuer ?? ""
            editedDate = result.effectiveDate ?? .now
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Ouvrir") { onOpen() }
            Button("Aperçu") { quickLookURL = result.previewURL }
                .disabled(result.previewURL == nil)
            Button("Révéler dans le Finder") { onReveal() }
            Button("Exporter…") { onExport() }
            Button(isCorrecting ? "Fermer la correction" : "Corriger…") { isCorrecting.toggle() }
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
