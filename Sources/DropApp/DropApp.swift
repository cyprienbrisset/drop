import AppKit
import DropFeatures
import SwiftUI

/// Application menu bar (`LSUIElement`), aucune fenêtre au lancement, aucune icône Dock par défaut
/// (EX-01). Trois surfaces seulement : Drop Zone, Search, Préférences (EX-02).
@main
struct DropApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Drop", systemImage: "tray.and.arrow.down") {
            Text("Drop Zone — à construire (EF-01..EF-13)")
            Divider()
            Button("Rechercher…") {
                openWindow(id: "search")
            }
            SettingsLink {
                Text("Préférences…")
            }
            Button("Quitter Drop") {
                NSApplication.shared.terminate(nil)
            }
        }

        // Résultats vides en attendant le bootstrap applicatif (cf. note de portée de SearchView).
        WindowGroup(id: "search") {
            SearchView(results: [])
        }

        Settings {
            // Données de démonstration : le bootstrap vers un VaultService/DropIndexDatabase
            // réels n'est pas encore câblé (cf. note de portée dans PreferencesView).
            PreferencesView(
                vaultLocation: Self.defaultVaultLocation,
                budget: VaultBudget(vaultSizeBytes: 0, dedupSavingsBytes: 0, indexSizeBytes: 0, vectorsSizeBytes: 0)
            )
        }
    }

    private static var defaultVaultLocation: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Drop")
    }
}
