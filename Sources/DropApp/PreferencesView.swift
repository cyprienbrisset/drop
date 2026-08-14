import DropFeatures
import SwiftUI

/// Écran Préférences (EX-02) : emplacement du coffre (EF-20) et budget disque, affiché en
/// permanence (EF-26). La réparation (EF-28) est traitée séparément (DRO-49, Phase 7).
///
/// Note de portée : cette vue affiche les données qu'on lui passe ; elle ne lit pas encore l'état
/// réel de l'application (pas de bootstrap `DropApp` vers un `VaultService`/`DropIndexDatabase`
/// vivants à ce stade du projet). Le changement d'emplacement avec migration vérifiée (EF-20)
/// n'est pas encore câblé : afficher l'emplacement actuel sans permettre de le changer plutôt que
/// proposer une action qui ne ferait rien.
struct PreferencesView: View {
    let vaultLocation: URL
    let budget: VaultBudget

    var body: some View {
        Form {
            Section("Emplacement du coffre") {
                LabeledContent("Dossier actuel", value: vaultLocation.path)
            }

            Section("Budget disque") {
                LabeledContent("Taille du coffre", value: Self.formatBytes(budget.vaultSizeBytes))
                LabeledContent("Économie de déduplication", value: Self.formatBytes(budget.dedupSavingsBytes))
                LabeledContent("Taille de l'index", value: Self.formatBytes(budget.indexSizeBytes))
                LabeledContent("Taille des vecteurs", value: Self.formatBytes(budget.vectorsSizeBytes))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 260)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    PreferencesView(
        vaultLocation: URL(fileURLWithPath: "/Users/exemple/Library/Application Support/Drop"),
        budget: VaultBudget(vaultSizeBytes: 128_000_000, dedupSavingsBytes: 12_000_000, indexSizeBytes: 4_500_000, vectorsSizeBytes: 0)
    )
}
