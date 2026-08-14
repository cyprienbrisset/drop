/// Résultat d'extraction pour une page de document (§5.2) : texte, origine, confiance OCR éventuelle.
public struct PageText: Sendable {
    public enum Source: String, Sendable {
        case native, ocr, attributed, plain
    }

    public let pageNumber: Int
    public let source: Source
    public let content: String
    public let ocrConfidence: Double?

    public init(pageNumber: Int, source: Source, content: String, ocrConfidence: Double? = nil) {
        self.pageNumber = pageNumber
        self.source = source
        self.content = content
        self.ocrConfidence = ocrConfidence
    }
}
