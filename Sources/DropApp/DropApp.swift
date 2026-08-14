import DropFeatures
import SwiftUI

/// Application menu bar (`LSUIElement`), aucune fenêtre au lancement, aucune icône Dock par défaut
/// (EX-01). Trois surfaces seulement : Drop Zone, Search, Préférences (EX-02).
@main
struct DropApp: App {
    var body: some Scene {
        MenuBarExtra("Drop", systemImage: "tray.and.arrow.down") {
            Text("Drop Zone — à construire (DRO-26)")
        }
    }
}
