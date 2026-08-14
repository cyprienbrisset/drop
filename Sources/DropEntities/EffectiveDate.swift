import Foundation

/// Règle de priorité pour la date effective (§5.3.3), la même partout dans le produit.
public enum EffectiveDate {
    public enum Source: String, Sendable {
        case user, emissionContext, mostFrequent, contentMetadata, filename, addedAt
    }

    public struct Result: Sendable, Equatable {
        public let date: String // ISO 8601 yyyy-MM-dd
        public let source: Source
        /// `true` uniquement pour `addedAt` (§5.3.3 point 6) : affichée en gris, non fiable.
        public var isUnreliable: Bool { source == .addedAt }
    }

    /// - Parameters:
    ///   - userVerified: date corrigée par l'utilisateur, prioritaire absolue.
    ///   - emissionContextDate: date trouvée en contexte d'émission (« facture du », « émis le »...) sur la première page.
    ///   - allDates: toutes les dates détectées dans le document (pour la fréquence).
    ///   - contentCreatedAt: métadonnée du fichier.
    ///   - filenameDate: date déduite du nom de fichier.
    ///   - addedAt: date d'ingestion, dernier recours.
    public static func resolve(
        userVerified: String?, emissionContextDate: String?, allDates: [String],
        contentCreatedAt: String?, filenameDate: String?, addedAt: String
    ) -> Result {
        if let userVerified {
            return Result(date: userVerified, source: .user)
        }
        if let emissionContextDate {
            return Result(date: emissionContextDate, source: .emissionContext)
        }
        if let mostFrequent = mostFrequentDate(in: allDates) {
            return Result(date: mostFrequent, source: .mostFrequent)
        }
        if let contentCreatedAt {
            return Result(date: contentCreatedAt, source: .contentMetadata)
        }
        if let filenameDate {
            return Result(date: filenameDate, source: .filename)
        }
        return Result(date: addedAt, source: .addedAt)
    }

    private static func mostFrequentDate(in dates: [String]) -> String? {
        guard !dates.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for date in dates { counts[date, default: 0] += 1 }
        let maxCount = counts.values.max() ?? 0
        // En cas d'égalité, on garde l'ordre d'apparition (premier trouvé) pour rester déterministe.
        return dates.first { counts[$0] == maxCount }
    }
}
