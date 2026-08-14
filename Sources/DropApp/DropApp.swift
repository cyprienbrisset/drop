import AppKit
import DropFeatures
import SwiftUI

/// Sans bundle `.app` réel à ce stade du projet (pas encore de paquetage Xcode/notarisation,
/// DRO-53), il n'y a pas d'`Info.plist` pour déclarer `LSUIElement` — cette politique doit donc
/// être posée par code pour garantir qu'aucune icône Dock n'apparaît (EX-01), de façon fiable
/// indépendamment de la manière dont l'exécutable est lancé (`swift run`, double-clic, etc.).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Application menu bar, aucune fenêtre au lancement, aucune icône Dock (EX-01). Trois surfaces
/// seulement : Drop Zone (popover de la tray icon), Search, Préférences (EX-02), toutes branchées
/// sur un unique `AppEnvironment` — le coffre réel de cette machine.
@main
struct DropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
