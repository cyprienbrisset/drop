import CoreGraphics
import Foundation
import ImageIO

/// Images (PNG, JPEG, HEIC, TIFF, GIF, BMP) : OCR + étiquettes descriptives à vocabulaire fermé
/// (§5.2). Les images de moins de 100×100 px ne sont pas OCRisées.
public struct ImageTextExtractor: Sendable {
    private let ocr = VisionOCR()

    public init() {}

    public func extract(fileAt url: URL) throws -> ExtractedDocument {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ExtractionError.unreadable
        }

        guard image.width >= 100, image.height >= 100 else {
            return ExtractedDocument(pages: [], pageCount: 0)
        }

        let ocrResult = try ocr.recognizeText(in: image)
        let labels = (try? ocr.classify(image)) ?? []
        var content = ocrResult.text
        if !labels.isEmpty {
            content += content.isEmpty ? labels.joined(separator: ", ") : "\n" + labels.joined(separator: ", ")
        }

        guard !content.isEmpty else { return ExtractedDocument(pages: [], pageCount: 0) }
        return ExtractedDocument(pages: [
            PageText(pageNumber: 0, source: .ocr, content: content, ocrConfidence: ocrResult.confidence)
        ])
    }
}
