import DropCore
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
    var vaults: [VaultDescriptor] = []
    var activeVaultID: String?
    var onCreateVault: () -> Void = {}
    var onSwitchVault: (VaultDescriptor) -> Void = { _ in }

    @State private var budget = VaultBudget(vaultSizeBytes: 0, dedupSavingsBytes: 0, indexSizeBytes: 0, vectorsSizeBytes: 0)
    @State private var documentCount = 0
    @State private var remindersEnabled = false
    @State private var stats = VaultStats(documentCount: 0, averageAnalysisSeconds: nil)

    private enum ConditionKind: String, CaseIterable, Identifiable {
        case issuerEquals = "Émetteur est"
        case docTypeEquals = "Type est"
        case amountGreaterThan = "Montant supérieur à"
        case keywordContains = "Mot-clé contient"
        var id: String { rawValue }
    }
    @State private var newRuleConditionKind: ConditionKind = .issuerEquals
    @State private var newRuleConditionValue = ""
    @State private var newRuleActionTag = ""

    // Fenêtre de préférences à volets (§HIG macOS : System Settings, Mail, Xcode…) plutôt qu'un
    // unique formulaire qui défile — sept sections d'un coup n'orientaient plus nulle part.
    // `TabView` avec `Tab(_:systemImage:)` rend nativement la barre d'icônes de la barre d'outils
    // sur macOS, sans configuration supplémentaire.
    var body: some View {
        TabView {
            Tab("Général", systemImage: "gearshape") { generalPane }
            Tab("Rappels", systemImage: "bell") { remindersPane }
            Tab("Automatisation", systemImage: "wand.and.stars") { automationPane }
            Tab("Stockage", systemImage: "internaldrive") { storagePane }
        }
        .frame(minWidth: 760, minHeight: 640)
        .task {
            budget = await environment.computeBudget()
            documentCount = (try? await environment.activeDocumentCount()) ?? 0
            remindersEnabled = await environment.remindersEnabled()
            stats = await environment.computeStats()
            await environment.loadAutomationRules()
        }
    }

    private var generalPane: some View {
        Form {
            Section("Emplacement du coffre") {
                LabeledContent("Dossier actuel", value: environment.vaultRoot.path)
                Button("Importer un coffre existant…") { environment.importVault() }
            }

            Section("Coffres") {
                Text("Chaque coffre a sa propre clé de chiffrement — les basculer ne partage jamais rien entre eux.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(vaults) { vault in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(vault.name)
                            Text(vault.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if vault.id == activeVaultID {
                            Text("Actif")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Basculer") { onSwitchVault(vault) }
                        }
                    }
                }

                Button("Nouveau coffre…", action: onCreateVault)
            }

            Section("Licence") {
                LabeledContent("Documents", value: "\(documentCount) / \(LicenseGate.freeCap) (version gratuite)")
                if documentCount >= LicenseGate.freeCap {
                    Text("Plafond atteint — les documents existants restent pleinement consultables ; l'ajout de nouveaux documents nécessite la version Pro.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var remindersPane: some View {
        Form {
            Section("Rappels d'échéance") {
                Toggle("Me rappeler des échéances détectées", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, newValue in environment.setRemindersEnabled(newValue) }
                Text("Une notification locale est proposée pour les documents où une échéance a été détectée. Désactivé par défaut ; l'activer déclenche la demande d'autorisation système.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var automationPane: some View {
        Form {
            Section("Automatisation") {
                Text("Type Hazel : « si… alors ajoute le tag… » — appliqué automatiquement après chaque analyse, jamais avant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(environment.automationRuleList) { rule in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { rule.isEnabled },
                            set: { environment.setAutomationRule(rule, isEnabled: $0) }
                        )) {
                            Text(Self.describe(rule))
                        }
                        Button {
                            environment.removeAutomationRule(rule)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retirer la règle \(rule.name)")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Picker("Condition", selection: $newRuleConditionKind) {
                        ForEach(ConditionKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    TextField(conditionValuePlaceholder, text: $newRuleConditionValue)
                        .textFieldStyle(.roundedBorder)
                    TextField("Alors ajoute le tag…", text: $newRuleActionTag)
                        .textFieldStyle(.roundedBorder)
                    Button("Ajouter la règle", action: addRule)
                        .disabled(newRuleConditionValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || newRuleActionTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }

    private var storagePane: some View {
        Form {
            Section("Statistiques") {
                LabeledContent("Documents dans le coffre", value: "\(stats.documentCount)")
                if environment.pendingAnalysisCount > 0 {
                    LabeledContent("En cours d'analyse", value: "\(environment.pendingAnalysisCount)")
                }
                if let average = stats.averageAnalysisSeconds {
                    LabeledContent("Temps de traitement moyen", value: Self.formatDuration(average))
                } else {
                    Text("Temps de traitement moyen : pas encore de mesure (aucune analyse terminée).")
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
    }

    private var conditionValuePlaceholder: String {
        switch newRuleConditionKind {
        case .issuerEquals: return "ex. EDF"
        case .docTypeEquals: return "ex. facture"
        case .amountGreaterThan: return "ex. 100"
        case .keywordContains: return "ex. électricité"
        }
    }

    private func addRule() {
        let value = newRuleConditionValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = newRuleActionTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !tag.isEmpty else { return }

        let condition: AutomationRules.Condition
        switch newRuleConditionKind {
        case .issuerEquals: condition = .issuerEquals(value)
        case .docTypeEquals: condition = .docTypeEquals(value)
        case .amountGreaterThan:
            guard let threshold = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
            condition = .amountGreaterThan(threshold)
        case .keywordContains: condition = .keywordContains(value)
        }

        environment.addAutomationRule(name: "\(newRuleConditionKind.rawValue) « \(value) »", condition: condition, actionTag: tag)
        newRuleConditionValue = ""
        newRuleActionTag = ""
    }

    private static func describe(_ rule: AutomationRules.Rule) -> String {
        let conditionText: String
        switch rule.condition {
        case .issuerEquals(let value): conditionText = "émetteur = « \(value) »"
        case .docTypeEquals(let value): conditionText = "type = « \(value) »"
        case .amountGreaterThan(let value): conditionText = "montant > \(value.formatted())"
        case .keywordContains(let value): conditionText = "mot-clé contient « \(value) »"
        }
        return "Si \(conditionText) → tag « \(rule.actionTag) »"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        seconds < 60
            ? String(format: "%.0f s", seconds)
            : String(format: "%d min %02d s", Int(seconds) / 60, Int(seconds) % 60)
    }
}

#Preview {
    PreferencesView(environment: try! AppEnvironment(vaultRoot: FileManager.default.temporaryDirectory.appendingPathComponent("drop-preview")))
}
