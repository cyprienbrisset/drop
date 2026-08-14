import DropFeatures
import DropLicense
import SwiftUI

/// Écran Préférences (EX-02) : emplacement du coffre (EF-20) et budget disque, affiché en
/// permanence (EF-26), calculé pour de vrai sur le coffre actif. La réparation (EF-28) est
/// traitée séparément (DRO-49, Phase 7). Le changement d'emplacement avec migration vérifiée
/// (EF-20) n'est pas encore câblé : afficher l'emplacement actuel sans permettre de le changer
/// plutôt que proposer une action qui ne ferait rien.
struct PreferencesView: View {
    let environment: AppEnvironment

    @State private var budget = VaultBudget(vaultSizeBytes: 0, dedupSavingsBytes: 0, indexSizeBytes: 0, vectorsSizeBytes: 0)
    @State private var documentCount = 0

    var body: some View {
        Form {
            Section("Emplacement du coffre") {
                LabeledContent("Dossier actuel", value: environment.vaultRoot.path)
            }

            Section("Licence") {
                LabeledContent("Documents", value: "\(documentCount) / \(LicenseGate.freeCap) (version gratuite)")
                if documentCount >= LicenseGate.freeCap {
                    Text("Plafond atteint — les documents existants restent pleinement consultables ; l'ajout de nouveaux documents nécessite la version Pro.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Budget disque") {
                LabeledContent("Taille du coffre", value: Self.formatBytes(budget.vaultSizeBytes))
                LabeledContent("Économie de déduplication", value: Self.formatBytes(budget.dedupSavingsBytes))
                LabeledContent("Taille de l'index", value: Self.formatBytes(budget.indexSizeBytes))
                LabeledContent("Taille des vecteurs", value: Self.formatBytes(budget.vectorsSizeBytes))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 300)
        .task {
            budget = await environment.computeBudget()
            documentCount = (try? await environment.activeDocumentCount()) ?? 0
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    PreferencesView(environment: try! AppEnvironment(vaultRoot: FileManager.default.temporaryDirectory.appendingPathComponent("drop-preview")))
}
