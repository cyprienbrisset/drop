import AppKit
import DropFeatures
import SwiftUI

/// Gère la tray icon, le popover de dépôt et les fenêtres Recherche/Préférences directement en
/// AppKit (§EX-01/EX-02). Nécessaire pour la détection du survol pendant un glisser-déposer
/// (`DropTargetStatusView`) — quelque chose qu'aucune scène SwiftUI ne permet d'obtenir sur
/// l'icône elle-même, seulement sur le contenu d'un popover déjà ouvert.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment: AppEnvironment

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var searchWindow: NSWindow?
    private var preferencesWindow: NSWindow?

    override init() {
        // `try!` assumé : si le coffre ne peut pas être créé (permissions, disque plein), l'app
        // ne peut de toute façon rien faire — ENF-31/32 (page d'erreur dédiée) reste à construire
        // (DRO-49). Échouer bruyamment ici est plus honnête que continuer à moitié fonctionnel.
        environment = try! AppEnvironment(vaultRoot: AppEnvironment.defaultVaultLocation)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sans bundle `.app` réel à ce stade (pas d'`Info.plist`, DRO-53), `LSUIElement` ne peut
        // pas être déclaré : cette politique doit être posée par code (EX-01, aucune icône Dock).
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        setUpPopover()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let dragTarget = DropTargetStatusView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        dragTarget.onClick = { [weak self] in self?.togglePopover() }
        dragTarget.onDragEntered = { [weak self] in self?.showPopover() }
        dragTarget.onPerformDrop = { [weak self] urls in
            self?.showPopover()
            self?.environment.handleDrop(of: urls)
        }
        statusItem.view = dragTarget
    }

    private func setUpPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DropZoneView(environment: environment, onOpenSearch: { [weak self] in self?.openSearchWindow() },
                                    onOpenPreferences: { [weak self] in self?.openPreferencesWindow() })
        )
    }

    private func togglePopover() {
        if popover.isShown {
            popover.close()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard !popover.isShown, let view = statusItem.view else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func openSearchWindow() {
        popover.close()
        NSApp.activate(ignoringOtherApps: true)

        if searchWindow == nil {
            let hosting = NSHostingController(rootView: SearchView(environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Rechercher"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            searchWindow = window
        }
        searchWindow?.center()
        searchWindow?.makeKeyAndOrderFront(nil)
    }

    func openPreferencesWindow() {
        popover.close()
        NSApp.activate(ignoringOtherApps: true)

        if preferencesWindow == nil {
            let hosting = NSHostingController(rootView: PreferencesView(environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Préférences"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Application menu bar, aucune fenêtre au lancement, aucune icône Dock (EX-01). Toute la
/// présentation (tray icon, popover, fenêtres) est gérée par `AppDelegate` — cette scène ne sert
/// qu'à satisfaire `App.body`, jamais affichée.
@main
struct DropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
