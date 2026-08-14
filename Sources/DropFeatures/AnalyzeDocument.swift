import DropCore
import DropEntities
import DropExtraction
import DropIndex
import DropVault
import Foundation
import GRDB

/// Cas d'usage : analyse déterministe d'un document déjà ingéré (§4.2 `RunAnalysis`, sous-ensemble
/// couvrant l'extraction de texte et les entités déterministes — le modèle de langage arrive en
/// Phase 5). Respecte l'ordre de subsidiarité (EF-41) : texte → OCR conditionnel → regex.
///
/// Persiste `page_texts`, `entities`, met à jour `documents` (émetteur, date effective) et
/// `fts_docs` (corps, émetteur) — un document reste cherchable dès l'ingestion (EF-40), enrichi
/// ensuite par ce passage.
public struct AnalyzeDocument: Sendable {
    private let vault: VaultService
    private let database: DropIndexDatabase
    private let extractor = DocumentTextExtractor()
    private let amountExtractor = AmountExtractor()
    private let dateExtractor = DateExtractor()
    private let identifierExtractor = IdentifierExtractor()
    private let issuerDictionary = IssuerDictionary()

    public init(vault: VaultService, database: DropIndexDatabase) {
        self.vault = vault
        self.database = database
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
                + identifierExtractor.extract(from: page.content, pageNo: page.pageNumber)
                + issuerDictionary.match(in: page.content)
        }

        let issuer = entities.first { $0.kind == .org }?.valueText
        let effectiveDate = Self.resolveEffectiveDate(entities: entities, addedAt: addedAt)

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

            try db.execute(
                sql: """
                UPDATE documents SET issuer = ?, effective_date = ?, effective_date_src = ?, analysis_state = 'done'
                WHERE id = ? AND user_verified = 0
                """,
                arguments: [issuer, effectiveDate?.date, effectiveDate?.source.rawValue, documentID]
            )

            try db.execute(
                sql: "UPDATE fts_docs SET body = ?, issuer = ? WHERE document_id = ?",
                arguments: [fullText, issuer ?? "", documentID]
            )
        }
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
