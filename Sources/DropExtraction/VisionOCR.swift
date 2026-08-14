import CoreGraphics
import Vision

/// Résultat d'une passe OCR (§5.2) : texte reconnu et confiance moyenne, conservée pour pondérer
/// le classement plus tard (§5.7, multiplicateur « confiance OCR < 0,5 »).
public struct OCRResult: Sendable {
    public let text: String
    public let confidence: Double
}

/// OCR via `Vision`, `.accurate`, français puis anglais (§5.2). Système uniquement — aucune
/// dépendance ML tierce (§4.1).
public struct VisionOCR: Sendable {
    public init() {}

    public func recognizeText(in image: CGImage) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        var lines: [String] = []
        var confidences: [Double] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            lines.append(candidate.string)
            confidences.append(Double(candidate.confidence))
        }

        let text = lines.joined(separator: "\n")
        let averageConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        return OCRResult(text: text, confidence: averageConfidence)
    }

    /// Étiquettes descriptives à vocabulaire fermé (§5.2) — pas de reconnaissance visuelle
    /// ouverte, explicitement hors périmètre V1 (§2.2).
    public func classify(_ image: CGImage, minimumConfidence: Double = 0.5) throws -> [String] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .filter { Double($0.confidence) >= minimumConfidence }
            .map(\.identifier)
    }
}
