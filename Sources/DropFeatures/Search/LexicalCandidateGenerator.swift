import DropCore
import DropIndex
import DropSearch
import Foundation
import GRDB

/// Générateur de candidats lexicaux (§5.7) : `fts_docs` en BM25, pondération de colonnes
/// display_name ×3, issuer ×2, keywords ×2, body ×1 — dans cet ordre de déclaration du schéma.
public struct LexicalCandidateGenerator: CandidateGenerator {
    private let database: DropIndexDatabase

    public init(database: DropIndexDatabase) {
        self.database = database
    }

    public func candidates(for query: ParsedQuery, limit: Int) async throws -> [RankedDocument] {
        let text = query.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let matchExpression = Self.ftsMatchExpression(for: text)
        let filter = QueryFilters.clause(for: query)
        let arguments: [any DatabaseValueConvertible & Sendable] = [matchExpression] + filter.arguments + [limit]

        return try await database.pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT fts_docs.document_id AS document_id
                FROM fts_docs
                JOIN documents ON documents.id = fts_docs.document_id
                WHERE fts_docs MATCH ? AND \(filter.sql)
                ORDER BY bm25(fts_docs, 3.0, 1.0, 2.0, 2.0)
                LIMIT ?
                """,
                arguments: StatementArguments(arguments)
            )
            return rows.enumerated().map { index, row in
                RankedDocument(documentID: row["document_id"], rank: index + 1)
            }
        }
    }

    /// Échappe la requête libre pour la syntaxe `MATCH` de FTS5 : chaque terme est mis entre
    /// guillemets (pour éviter qu'une ponctuation ou un opérateur ne casse la requête) et
    /// recherché en préfixe (`*`, sur les index `prefix = '2 3 4'` du schéma, §4.4). Sans cela,
    /// un mot collé à l'extension par le tokenizer (ex. `edf.pdf` reste un seul token à cause du
    /// `.` dans `tokenchars`) ne matcherait jamais une requête sur le seul mot « edf ».
    ///
    /// Termes joints par `OR`, jamais l'espace nu (§ET implicite de FTS5, DRO-46) : une requête en
    /// langage naturel comme « quel était mon solde en février » contient presque toujours un mot
    /// absent du document (« mon », « était »...) — l'exiger en plus des mots qui comptent vraiment
    /// (« solde », « février ») ferait échouer la recherche précisément quand elle est formulée le
    /// plus naturellement. BM25 continue de classer un document qui matche plusieurs termes devant
    /// celui qui n'en matche qu'un — l'assouplissement ne coûte rien en précision relative.
    static func ftsMatchExpression(for text: String) -> String {
        let allTerms = text.split(separator: " ").map(String.init)
        // Les mots-outils français ne portent aucun signal discriminant et, combinés au préfixe
        // (`*`), plusieurs correspondent par accident à des mots sans rapport de plusieurs
        // caractères (« en »* trouve « engie », « entretien »...) — les retirer avant l'union
        // laisse BM25 classer sur les mots qui comptent réellement. Une requête réduite à des
        // mots-outils garde malgré tout tous ses termes plutôt que de chercher sur rien.
        let significantTerms = allTerms.filter { !Self.isStopword($0) }
        let terms = significantTerms.isEmpty ? allTerms : significantTerms

        return terms
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " OR ")
    }

    private static func isStopword(_ term: String) -> Bool {
        term.count < 2 || stopwords.contains(term.lowercased())
    }

    /// Mots-outils français les plus fréquents dans une requête tapée naturellement (articles,
    /// pronoms, prépositions courtes, auxiliaires) — jamais exhaustif, seulement ceux qui posent
    /// un vrai risque de faux positifs en préfixe sur un corpus de quelques mots.
    private static let stopwords: Set<String> = [
        "le", "la", "les", "l", "un", "une", "des", "de", "du", "d", "et", "ou", "à", "au", "aux",
        "en", "je", "j", "j'ai", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "ce", "cet", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses",
        "notre", "votre", "leur", "leurs", "que", "qu", "qui", "quoi", "où", "dont",
        "est", "suis", "es", "sont", "était", "étais", "ai", "as", "a", "avons", "avez", "ont",
        "pour", "par", "avec", "sans", "sur", "dans", "combien", "comment", "pourquoi", "quel", "quelle",
    ]
}
