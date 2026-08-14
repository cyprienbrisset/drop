import AppKit
import DropFeatures
import SwiftUI

/// Application menu bar (`LSUIElement`), aucune fenêtre au lancement, aucune icône Dock par défaut
/// (EX-01). Trois surfaces seulement : Drop Zone (popover de la tray icon), Search, Préférences
/// (EX-02), toutes branchées sur un unique `AppEnvironment` — le coffre réel de cette machine.
@main
struct DropApp: App {
    // `try!` assumé : si le coffre ne peut pas être créé (permissions, disque plein), l'app ne
    // peut de toute façon rien faire — ENF-31/32 (page d'erreur dédiée disque plein/coffre
    // illisible) reste à construire, cf. DRO-49. Échouer bruyamment ici est plus honnête que
    // continuer dans un état à moitié fonctionnel sans cette infrastructure.
    @State private var environment = try! AppEnvironment(vaultRoot: AppEnvironment.defaultVaultLocation)

    var body: some Scene {
        MenuBarExtra("Drop", systemImage: "tray.and.arrow.down") {
            DropZoneView(environment: environment)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "search") {
            SearchView(environment: environment)
        }
        .windowResizability(.contentSize)

        Settings {
            PreferencesView(environment: environment)
        }
    }
}
