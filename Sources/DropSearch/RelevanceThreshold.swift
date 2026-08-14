import Foundation

/// Seuil de pertinence (§5.7, EF-68) : élague les résultats fusionnés à 35 % du meilleur score,
/// avec un plancher absolu en dessous duquel même le meilleur résultat n'est pas jugé pertinent
/// (« aucun résultat pertinent » plutôt qu'une liste de bruit). Le plancher par défaut est un
/// point de départ technique — il doit être calibré par le harnais d'évaluation (§8.3, DRO-46)
/// une fois `recall@3` mesuré sur un corpus réel, pas ajusté à l'intuition.
public enum RelevanceThreshold {
    public static let bestScoreRatio = 0.35
    public static let defaultAbsoluteFloor = 0.005

    public static func cutoff(bestScore: Double, absoluteFloor: Double = defaultAbsoluteFloor) -> Double {
        max(bestScore * bestScoreRatio, absoluteFloor)
    }

    /// Applique le seuil à un ensemble `documentID -> score`. Renvoie un ensemble vide si le
    /// meilleur score lui-même est nul ou négatif (rien de pertinent à élaguer).
    public static func apply(to scores: [String: Double], absoluteFloor: Double = defaultAbsoluteFloor) -> [String: Double] {
        guard let best = scores.values.max(), best > 0 else { return [:] }
        let threshold = cutoff(bestScore: best, absoluteFloor: absoluteFloor)
        return scores.filter { $0.value >= threshold }
    }
}
