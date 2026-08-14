/// Résultat complet d'une extraction (§5.2). `pagesNeedingOCR` liste, pour un PDF, les pages dont
/// la densité textuelle native est insuffisante (EF-42) — le texte natif de ces pages est déjà
/// dans `pages`, potentiellement vide ou quasi vide ; l'OCR (DRO-30) les complète séparément.
public struct ExtractedDocument: Sendable {
    public let pages: [PageText]
    public let pagesNeedingOCR: Set<Int>
    public let pageCount: Int

    public init(pages: [PageText], pagesNeedingOCR: Set<Int> = [], pageCount: Int? = nil) {
        self.pages = pages
        self.pagesNeedingOCR = pagesNeedingOCR
        self.pageCount = pageCount ?? pages.count
    }
}
