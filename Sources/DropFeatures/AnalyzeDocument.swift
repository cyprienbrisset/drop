import DropCore
import DropEntities
import DropExtraction
import DropIndex
import DropIntelligence
import DropVault
import Foundation
import GRDB

/// Cas d'usage : analyse d'un document déjà ingéré (§4.2 `RunAnalysis`) — extraction de texte,
/// entités déterministes (EF-41, texte → OCR conditionnel → regex), puis classification/résumé
/// par le modèle de langage système quand disponible (§5.4, ADR-09 : le modèle ne décide jamais
/// d'un type déjà classé de façon déterministe pour un champ verrouillé par l'utilisateur, et son
/// émetteur suggéré ne sert que de repli si le dictionnaire déterministe n'a rien trouvé).
///
/// Persiste `page_texts`, `entities`, met à jour `documents` (type, émetteur, date effective,
/// résumé) et `fts_docs` (corps, émetteur, mots-clés) — un document reste cherchable dès
/// l'ingestion (EF-40), enrichi ensuite par ce passage. Sans Apple Intelligence disponible
/// (§5.4.4), l'analyse déterministe seule s'applique déjà et reste pleinement cherchable —
/// seuls le type fin, le résumé et les mots-clés manquent.
public struct AnalyzeDocument: Sendable {
    private let vault: VaultService
    private let database: DropIndexDatabase
    private let extractor = DocumentTextExtractor()
    private let amountExtractor = AmountExtractor()
    private let dateExtractor = DateExtractor()
    private let dueDateExtractor = DueDateExtractor()
    private let identifierExtractor = IdentifierExtractor()
    private let issuerDictionary = IssuerDictionary()
    private let insightGenerator: DocumentInsightGenerator
    private let contextSelector = ContextSelector()

    public init(vault: VaultService, database: DropIndexDatabase, insightGenerator: DocumentInsightGenerator = DocumentInsightGenerator()) {
        self.vault = vault
        self.database = database
        self.insightGenerator = insightGenerator
    }

    public func analyze(documentID: String) async throws {
        let (blobHash, originalFilename, addedAt): (String, String, String) = try await database.pool.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT blob_hash, original_filename, added_at FROM documents WHERE id = ?", arguments: [documentID]
            ) else {
                throw IngestionError.transactionFailed
            }
            return (row["blob_hash"], row["original_filename"], row["added_at"])
        }

        let (blobURL, _) = vault.paths(forHash: blobHash)
        let originalExtension = (originalFilename as NSString).pathExtension
        // Un format non supporté ou illisible ne fait pas échouer l'analyse : le document reste
        // cherchable sur ses seules métadonnées (EF-07).
        let extracted = try? extractor.extract(fileAt: blobURL, extensionHint: originalExtension)
        let pages = extracted?.pages ?? []
        let fullText = pages.map(\.content).joined(separator: "\n")

        let entities: [ExtractedEntity] = pages.flatMap { page in
            amountExtractor.extract(from: page.content, pageNo: page.pageNumber)
                + dateExtractor.extract(from: page.content, pageNo: page.pageNumber)
                + dueDateExtractor.extract(from: page.content, pageNo: page.pageNumber)
                + identifierExtractor.extract(from: page.content, pageNo: page.pageNumber)
                + issuerDictionary.match(in: page.content)
        }

        let deterministicIssuer = entities.first { $0.kind == .org }?.valueText
        let effectiveDate = Self.resolveEffectiveDate(entities: entities, addedAt: addedAt)
        // Première échéance trouvée, par ordre d'apparition dans le document (§5.3.3, même
        // prudence que la date effective : jamais de choix "le plus probable" plus élaboré ici).
        let dueDate = entities.first { $0.kind == .dueDate }?.valueDate

        let context = contextSelector.select(
            pages: pages.map { PageContent(pageNumber: $0.pageNumber, text: $0.content) },
            filename: originalFilename
        )
        let insight = await Self.generateInsight(text: context, generator: insightGenerator)

        // ADR-09 : le modèle ne fournit un émetteur que si le dictionnaire déterministe n'a rien
        // trouvé — jamais l'inverse, jamais une valeur numérique ou temporelle (hors du schéma
        // `DocumentInsight`, qui ne les expose pas).
        let issuer = deterministicIssuer ?? insight?.issuer

        try await database.pool.write { db in
            try db.execute(sql: "DELETE FROM page_texts WHERE document_id = ?", arguments: [documentID])
            try db.execute(sql: "DELETE FROM entities WHERE document_id = ?", arguments: [documentID])

            for page in pages {
                try db.execute(
                    sql: """
                    INSERT INTO page_texts (document_id, page_no, source, content, char_count, ocr_confidence)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        documentID, page.pageNumber, page.source.rawValue, page.content, page.content.count,
                        page.ocrConfidence,
                    ]
                )
            }

            for entity in entities {
                try db.execute(
                    sql: """
                    INSERT INTO entities (document_id, kind, value_text, raw_text, value_num, value_date, currency, page_no, extractor, confidence)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        documentID, entity.kind.rawValue, entity.valueText, entity.rawText, entity.valueNum,
                        entity.valueDate, entity.currency, entity.pageNo, entity.extractor.rawValue, entity.confidence,
                    ]
                )
            }

            // EF-48 : un champ dont le bit `user_verified` est posé n'est plus jamais réécrit par
            // le pipeline (§4.4 — masque type=1, issuer=2, effectiveDate=4). `COALESCE` sur le
            // type/résumé : sans modèle disponible (§5.4.4), `insight` est `nil` et une analyse
            // antérieure plus riche ne doit pas être effacée par une réanalyse dégradée.
            try db.execute(
                sql: """
                UPDATE documents SET
                    doc_type = CASE WHEN (user_verified & 1) = 0 THEN COALESCE(?, doc_type) ELSE doc_type END,
                    doc_type_conf = CASE WHEN (user_verified & 1) = 0 THEN COALESCE(?, doc_type_conf) ELSE doc_type_conf END,
                    issuer = CASE WHEN (user_verified & 2) = 0 THEN ? ELSE issuer END,
                    effective_date = CASE WHEN (user_verified & 4) = 0 THEN ? ELSE effective_date END,
                    effective_date_src = CASE WHEN (user_verified & 4) = 0 THEN ? ELSE effective_date_src END,
                    summary = COALESCE(?, summary),
                    due_date = COALESCE(?, due_date),
                    analysis_state = 'done'
                WHERE id = ?
                """,
                arguments: [
                    insight?.type.rawValue, insight?.confidence, issuer, effectiveDate?.date,
                    effectiveDate?.source.rawValue, insight?.summary, dueDate, documentID,
                ]
            )

            // Reflète les valeurs réellement retenues (celles du pipeline, ou celles conservées si
            // l'utilisateur les a corrigées) — jamais une valeur qu'EF-48 vient d'écarter ci-dessus.
            let retained = try Row.fetchOne(db, sql: "SELECT issuer FROM documents WHERE id = ?", arguments: [documentID])
            let retainedIssuer: String? = retained?["issuer"]
            let keywords = insight?.keywords.joined(separator: " ") ?? ""
            try db.execute(
                sql: "UPDATE fts_docs SET body = ?, issuer = ?, keywords = ? WHERE document_id = ?",
                arguments: [fullText, retainedIssuer ?? "", keywords, documentID]
            )
        }
    }

    /// `nil` en dehors du plein régime (§5.4.4) — machine non éligible, Apple Intelligence
    /// désactivée, modèle pas encore prêt — ou si l'inférence échoue : l'analyse déterministe
    /// suffit à rendre le document cherchable, jamais une erreur bloquante ici (EF-07).
    private static func generateInsight(text: String, generator: DocumentInsightGenerator) async -> DocumentInsight? {
        guard case .fullPipeline = DegradationPolicy.behavior(for: generator.availability) else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? await generator.generate(fromText: text)
    }

    private static func resolveEffectiveDate(entities: [ExtractedEntity], addedAt: String) -> EffectiveDate.Result? {
        let allDates = entities.filter { $0.kind == .date }.compactMap(\.valueDate)
        guard !allDates.isEmpty else { return nil }
        return EffectiveDate.resolve(
            userVerified: nil, emissionContextDate: nil, allDates: allDates,
            contentCreatedAt: nil, filenameDate: nil, addedAt: addedAt
        )
    }
}
