import DropFeatures
import SwiftUI

/// Écran Préférences (EX-02) : emplacement du coffre (EF-20) et budget disque, affiché en
/// permanence (EF-26), calculé pour de vrai sur le coffre actif. La réparation (EF-28) est
/// traitée séparément (DRO-49, Phase 7). Le changement d'emplacement avec migration vérifiée
/// (EF-20) n'est pas encore câblé : afficher l'emplacement actuel sans permettre de le changer
/// plutôt que proposer une action qui ne ferait rien.
struct PreferencesView: View {
    let environment: AppEnvironment

    @State private var budget = VaultBudget(vaultSizeBytes: 0, dedupSavingsBytes: 0, indexSizeBytes: 0, vectorsSizeBytes: 0)

    var body: some View {
        Form {
            Section("Emplacement du coffre") {
                LabeledContent("Dossier actuel", value: environment.vaultRoot.path)
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
        .task { budget = await environment.computeBudget() }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    PreferencesView(environment: try! AppEnvironment(vaultRoot: FileManager.default.temporaryDirectory.appendingPathComponent("drop-preview")))
}
