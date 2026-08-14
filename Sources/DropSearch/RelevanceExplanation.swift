import Foundation

/// Explication d'un résultat (§5.7, EF-69) : pourquoi ce document remonte, en langage clair.
/// Ordre de priorité : signaux forts et déterministes d'abord (correspondance exacte), puis la
/// nature de la correspondance (lexicale/sémantique/approchante), puis les signaux de contexte.
public enum RelevanceExplanation {
    public static func describe(signals: RelevanceSignals, matchedGenerators: Set<String>) -> [String] {
        var reasons: [String] = []

        if signals.exactFilenameMatch {
            reasons.append("Le nom du fichier correspond exactement à la recherche")
        }
        if signals.exactEntityMatch {
            reasons.append("Contient une information identifiée correspondant exactement à la recherche")
        }
        if matchedGenerators.contains("lexical") {
            reasons.append("Contient les mots recherchés")
        } else if matchedGenerators.contains("semantic") {
            reasons.append("Le contenu correspond au sens de la recherche")
        }
        if matchedGenerators.contains("trigram") {
            reasons.append("Correspondance approchante (faute de frappe possible)")
        }
        if matchedGenerators.contains("exact") {
            reasons.append("Correspond aux filtres de la recherche (date, montant, type, tag)")
        }
        if let age = signals.ageInDays, age < 30 {
            reasons.append("Document récent")
        }
        if signals.openedRecently {
            reasons.append("Ouvert récemment")
        }

        if reasons.isEmpty {
            reasons.append("Correspond à la recherche")
        }
        return reasons
    }
}
