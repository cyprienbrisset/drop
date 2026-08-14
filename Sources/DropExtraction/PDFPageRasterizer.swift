import AppKit
import PDFKit

/// Rendu d'une page PDF en image, pour l'OCR (§5.2) — l'OCR s'applique page par page, jamais au
/// document entier, afin qu'un PDF mixte texte/image ne soit pas OCRisé en totalité.
public struct PDFPageRasterizer: Sendable {
    public init() {}

    public func image(for page: PDFPage, scale: CGFloat = 2.0) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let image = NSImage(size: pixelSize)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let context = NSGraphicsContext.current?.cgContext else { return nil }
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
