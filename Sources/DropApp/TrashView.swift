import DropFeatures
import SwiftUI

/// Corbeille (EX-05, EF-23, §5.9) : les documents retirés restent visibles et restaurables
/// pendant 30 jours (par défaut) avant purge définitive — le vocabulaire reflète partout la
/// réversibilité de l'action (« retiré », jamais « supprimé »).
struct TrashView: View {
    let environment: AppEnvironment

    private static let retentionDays = 30

    var body: some View {
        Group {
            if environment.trashedDocuments.isEmpty {
                ContentUnavailableView(
                    "Corbeille vide",
                    systemImage: "trash",
                    description: Text("Les documents retirés du coffre apparaissent ici pendant 30 jours.")
                )
            } else {
                List(environment.trashedDocuments) { document in
                    TrashedDocumentRow(document: document, retentionDays: Self.retentionDays) {
                        environment.restoreFromTrash(document)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .task { await environment.loadTrash() }
    }
}

private struct TrashedDocumentRow: View {
    let document: ManageTrash.TrashedDocument
    let retentionDays: Int
    let onRestore: () -> Void

    private var daysRemaining: Int {
        let elapsedDays = Int(Date().timeIntervalSince(document.trashedAt) / 86400)
        return max(retentionDays - elapsedDays, 0)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayName)
                    .font(.body)
                Text(retentionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restaurer", action: onRestore)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var retentionMessage: String {
        daysRemaining <= 0
            ? "Purge définitive imminente"
            : "Purge définitive dans \(daysRemaining) jour\(daysRemaining > 1 ? "s" : "")"
    }
}

#Preview {
    TrashView(environment: try! AppEnvironment(vaultRoot: FileManager.default.temporaryDirectory.appendingPathComponent("drop-preview")))
}
