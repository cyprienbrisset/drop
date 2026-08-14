import Foundation

/// Détection de version (EF-06) : un même `version_group_id` est **proposé** si le radical du nom
/// de fichier est proche (distance de Levenshtein ≤ 3) et la taille dans ±25 %. Jamais automatique :
/// cette fonction pose l'étiquette de groupe pour affichage ultérieur, elle ne fusionne ni ne
/// remplace aucun document.
public enum VersionDetection {
    public static func normalizedStem(ofFilename filename: String) -> String {
        (filename as NSString).deletingPathExtension.lowercased()
    }

    public static func isLikelyVersion(
        nameA: String, sizeA: Int64, nameB: String, sizeB: Int64,
        maxLevenshteinDistance: Int = 3, maxSizeDeltaRatio: Double = 0.25
    ) -> Bool {
        guard sizeA > 0, sizeB > 0 else { return false }
        let stemA = normalizedStem(ofFilename: nameA)
        let stemB = normalizedStem(ofFilename: nameB)
        guard levenshteinDistance(stemA, stemB) <= maxLevenshteinDistance else { return false }
        let ratio = Double(abs(sizeA - sizeB)) / Double(max(sizeA, sizeB))
        return ratio <= maxSizeDeltaRatio
    }

    public static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previousRow = Array(0...b.count)
        var currentRow = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            currentRow[0] = i
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    currentRow[j] = previousRow[j - 1]
                } else {
                    currentRow[j] = Swift.min(previousRow[j - 1] + 1, previousRow[j] + 1, currentRow[j - 1] + 1)
                }
            }
            previousRow = currentRow
        }
        return previousRow[b.count]
    }
}
