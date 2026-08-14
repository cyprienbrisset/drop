import Foundation
import NaturalLanguage

/// Validation bloquante B (§9 Phase 0, DRO-17) : mesure de la qualité de `NLContextualEmbedding`
/// en français sur 30 paires de référence. Les paires ne portent sur aucun document utilisateur —
/// ce sont des phrases génériques construites pour ce test, pas un corpus de production (cf. DRO-15).
///
/// Critère de décision proposé (non dicté par le CDC, à valider) : l'écart moyen entre la
/// similarité cosinus des paires "proches" et celle des paires "éloignées" doit dépasser 0,10.
/// En dessous, le CDC prévoit un repli documenté sur lexical + entités déterministes.
func runValidationB() throws {
    guard let embedding = NLContextualEmbedding(language: .french) else {
        print("Aucun modèle d'embedding contextuel disponible pour le français sur cette machine.")
        return
    }

    if !embedding.hasAvailableAssets {
        print("Les assets du modèle ne sont pas encore téléchargés localement. Lancez `requestAssets()` puis relancez.")
        return
    }

    try embedding.load()
    defer { embedding.unload() }

    var similarScores: [Double] = []
    var dissimilarScores: [Double] = []

    print("=== Validation B — paires proches ===")
    for pair in similarPairs {
        let score = try cosineSimilarity(pair.0, pair.1, embedding: embedding)
        similarScores.append(score)
        print(String(format: "%.3f  « %@ »  ~  « %@ »", score, pair.0, pair.1))
    }

    print("\n=== Validation B — paires éloignées ===")
    for pair in dissimilarPairs {
        let score = try cosineSimilarity(pair.0, pair.1, embedding: embedding)
        dissimilarScores.append(score)
        print(String(format: "%.3f  « %@ »  ~  « %@ »", score, pair.0, pair.1))
    }

    let meanSimilar = similarScores.reduce(0, +) / Double(similarScores.count)
    let meanDissimilar = dissimilarScores.reduce(0, +) / Double(dissimilarScores.count)
    let gap = meanSimilar - meanDissimilar

    print("\n=== Rapport Validation B ===")
    print(String(format: "Similarité moyenne — paires proches   : %.3f", meanSimilar))
    print(String(format: "Similarité moyenne — paires éloignées : %.3f", meanDissimilar))
    print(String(format: "Écart (séparation)                    : %.3f", gap))
    print(gap > 0.10 ? "→ Séparation jugée suffisante (seuil proposé 0.10)." : "→ Séparation insuffisante : envisager le repli lexical + entités (§9 Phase 0).")
}

private func cosineSimilarity(_ a: String, _ b: String, embedding: NLContextualEmbedding) throws -> Double {
    let vectorA = try meanPooledVector(for: a, embedding: embedding)
    let vectorB = try meanPooledVector(for: b, embedding: embedding)
    return cosine(vectorA, vectorB)
}

private func meanPooledVector(for text: String, embedding: NLContextualEmbedding) throws -> [Double] {
    let result = try embedding.embeddingResult(for: text, language: .french)
    var sum = [Double](repeating: 0, count: embedding.dimension)
    var count = 0
    result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
        for index in 0..<min(vector.count, sum.count) {
            sum[index] += vector[index]
        }
        count += 1
        return true
    }
    guard count > 0 else { return sum }
    return sum.map { $0 / Double(count) }
}

private func cosine(_ a: [Double], _ b: [Double]) -> Double {
    var dot = 0.0, normA = 0.0, normB = 0.0
    for index in 0..<min(a.count, b.count) {
        dot += a[index] * b[index]
        normA += a[index] * a[index]
        normB += b[index] * b[index]
    }
    guard normA > 0, normB > 0 else { return 0 }
    return dot / (normA.squareRoot() * normB.squareRoot())
}

/// 15 paires proches (paraphrase / synonymie), françaises, génériques.
private let similarPairs: [(String, String)] = [
    ("La facture d'électricité est arrivée hier.", "J'ai reçu la facture EDF ce mois-ci."),
    ("Le contrat de location a été signé la semaine dernière.", "Nous avons signé le bail récemment."),
    ("Le médecin m'a prescrit des médicaments.", "L'ordonnance du docteur liste plusieurs traitements."),
    ("Le virement bancaire a été effectué ce matin.", "L'argent a été transféré sur mon compte aujourd'hui."),
    ("Mon salaire a été versé en fin de mois.", "Le bulletin de paie confirme le paiement mensuel."),
    ("Le colis a été livré à l'adresse indiquée.", "Le paquet est arrivé chez moi comme prévu."),
    ("La déclaration d'impôts doit être envoyée avant fin mai.", "Il faut soumettre ses impôts avant la date limite de mai."),
    ("Le rendez-vous chez le dentiste est confirmé pour lundi.", "J'ai bien un rendez-vous dentaire lundi prochain."),
    ("La garantie du produit couvre deux ans.", "Cet appareil est garanti pendant vingt-quatre mois."),
    ("Le devis pour les travaux a été accepté.", "Nous avons validé le devis de rénovation."),
    ("Le train a eu du retard ce matin.", "Le train est arrivé en retard aujourd'hui."),
    ("Elle a annulé son abonnement au gymnase.", "Elle a résilié son inscription à la salle de sport."),
    ("Le restaurant est complet ce soir.", "Il n'y a plus de table disponible ce soir au restaurant."),
    ("La réunion a été déplacée à demain.", "On a reporté la réunion au lendemain."),
    ("Le chat dort sur le canapé.", "Le chat fait une sieste sur le sofa."),
]

/// 15 paires éloignées (sujets sans rapport), françaises, génériques.
private let dissimilarPairs: [(String, String)] = [
    ("La facture d'électricité est arrivée hier.", "Le chat dort sur le canapé."),
    ("Le contrat de location a été signé la semaine dernière.", "Il pleut beaucoup à Marseille en automne."),
    ("Le médecin m'a prescrit des médicaments.", "L'équipe de football a gagné le match hier soir."),
    ("Le virement bancaire a été effectué ce matin.", "Le film commence à vingt heures trente."),
    ("Mon salaire a été versé en fin de mois.", "Les randonneurs ont atteint le sommet à midi."),
    ("Le colis a été livré à l'adresse indiquée.", "La recette demande trois œufs et de la farine."),
    ("La déclaration d'impôts doit être envoyée avant fin mai.", "Le concert était magnifique hier soir."),
    ("Le rendez-vous chez le dentiste est confirmé pour lundi.", "Le musée expose des tableaux impressionnistes."),
    ("La garantie du produit couvre deux ans.", "Les enfants jouent dans le parc après l'école."),
    ("Le devis pour les travaux a été accepté.", "Le vin rouge se marie bien avec ce fromage."),
    ("Le train a eu du retard ce matin.", "Elle apprend le piano depuis trois ans."),
    ("Elle a annulé son abonnement au gymnase.", "La bibliothèque ferme à dix-huit heures."),
    ("Le restaurant est complet ce soir.", "Le jardin botanique est ouvert toute l'année."),
    ("La réunion a été déplacée à demain.", "Le volcan est resté endormi pendant des siècles."),
    ("Le chat dort sur le canapé.", "La facture d'électricité est arrivée hier."),
]
