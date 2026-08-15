import AppKit
import Darwin
import DropCore
import DropFeatures
import SwiftUI

/// Gère la tray icon, le popover de dépôt et les fenêtres Recherche/Préférences directement en
/// AppKit (§EX-01/EX-02). Nécessaire pour la détection du survol pendant un glisser-déposer
/// (`DropTargetStatusView`) — quelque chose qu'aucune scène SwiftUI ne permet d'obtenir sur
/// l'icône elle-même, seulement sur le contenu d'un popover déjà ouvert.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var environment: AppEnvironment
    private let vaultRegistry: VaultRegistry

    private var statusItem: NSStatusItem!
    private var dropTargetView: DropTargetStatusView!
    private var popover: NSPopover!
    private var searchWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var trashWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var globalHotkeyMonitor: Any?

    /// Raccourci global promis dès l'onboarding (EX-06) : ⌥ Espace, cohérent avec ce que
    /// `OnboardingView` affiche à l'utilisateur — jamais un texte aspirationnel sans réalité.
    private static let globalShortcutDescription = "⌥ Espace"
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    /// Descripteur du verrou mono-instance (ENF-34) — jamais fermé pendant que l'app tourne :
    /// le fermer relâcherait le verrou. La sortie du processus le relâche naturellement.
    nonisolated(unsafe) private static var lockFileDescriptor: Int32 = -1

    override init() {
        // §5, backlog V3 : plusieurs coffres chiffrés séparément peuvent être connus de cette
        // machine ; celui qui rouvre au lancement est le dernier actif, jamais silencieusement
        // remis au coffre par défaut si l'utilisateur en a choisi un autre lors d'une session
        // précédente.
        let registry = VaultRegistry()
        let defaultRoot = AppEnvironment.defaultVaultLocation
        let activeDescriptor = registry.activeVaultID
            .flatMap { id in registry.listVaults().first { $0.id == id } }
            ?? registry.ensureDefaultVaultRegistered(name: "Coffre principal", path: defaultRoot.path)
        let vaultRoot = URL(fileURLWithPath: activeDescriptor.path)

        // ENF-34 : une deuxième instance ne doit jamais ouvrir le même coffre en parallèle de la
        // première — elle s'arrête immédiatement, avant tout accès disque partagé (index.db,
        // vectors.db). Vérifié avant même de construire `AppEnvironment`.
        guard Self.acquireSingleInstanceLock(vaultRoot: vaultRoot) else {
            FileHandle.standardError.write(Data("Drop est déjà lancé — cette instance s'arrête.\n".utf8))
            exit(0)
        }

        // `try!` assumé : si le coffre ne peut pas être créé (permissions, disque plein), l'app
        // ne peut de toute façon rien faire — ENF-31/32 (page d'erreur dédiée) reste à construire
        // (DRO-49). Échouer bruyamment ici est plus honnête que continuer à moitié fonctionnel.
        environment = try! AppEnvironment(vaultRoot: vaultRoot)
        vaultRegistry = registry
        super.init()
    }

    /// `flock` non bloquant sur un fichier dédié dans le coffre : la primitive standard pour un
    /// verrou mono-instance sur un même volume. En cas de doute sur le verrou lui-même (dossier
    /// pas encore créé, permissions), on n'empêche jamais le lancement — seule une seconde
    /// instance authentiquement détectée doit s'arrêter. Rappelée lors d'un changement de coffre
    /// (§switchVault) : le verrou précédent est alors relâché avant de poser le nouveau, jamais
    /// les deux à la fois.
    private static func acquireSingleInstanceLock(vaultRoot: URL) -> Bool {
        try? FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        let lockPath = vaultRoot.appendingPathComponent(".drop.lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return true }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        if lockFileDescriptor >= 0 { close(lockFileDescriptor) }
        lockFileDescriptor = descriptor
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sans bundle `.app` réel à ce stade (pas d'`Info.plist`, DRO-53), `LSUIElement` ne peut
        // pas être déclaré : cette politique doit être posée par code (EX-01, aucune icône Dock).
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        setUpPopover()
        registerGlobalHotkey()
        wirePendingAnalysisIndicator()

        if !UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey) {
            openOnboardingWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalHotkeyMonitor {
            NSEvent.removeMonitor(globalHotkeyMonitor)
        }
    }

    /// ⌥ Espace ouvre la recherche depuis n'importe quelle application (§EX-02). Un moniteur
    /// global standard (pas un `CGEventTap`) : aucune permission d'accessibilité requise, l'app
    /// n'étant de toute façon jamais sandboxée (§4.1).
    private func registerGlobalHotkey() {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.option], event.keyCode == 49 else { return }
            Task { @MainActor in self?.openSearchWindow() }
        }
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
        dropTargetView = dragTarget
    }

    /// §5.8/EX-08 : relie l'icône de la barre de menus à l'état réel de la file d'analyse — sans
    /// second appel après une bascule de coffre (§switchVault), l'icône continuerait de refléter
    /// la file du coffre précédent, jamais celle qui vient de s'ouvrir.
    private func wirePendingAnalysisIndicator() {
        environment.onPendingAnalysisChanged = { [weak self] hasPending in
            self?.dropTargetView.setProcessing(hasPending)
        }
    }

    private func setUpPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DropZoneView(
                environment: environment, onOpenSearch: { [weak self] in self?.openSearchWindow() },
                onOpenPreferences: { [weak self] in self?.openPreferencesWindow() },
                onOpenTrash: { [weak self] in self?.openTrashWindow() }
            )
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

        // Reconstruite à chaque ouverture plutôt que mise en cache : la liste des coffres peut
        // avoir changé (création, bascule) depuis la dernière fermeture de cette fenêtre.
        let hosting = NSHostingController(
            rootView: PreferencesView(
                environment: environment, vaults: vaultRegistry.listVaults(), activeVaultID: vaultRegistry.activeVaultID,
                onCreateVault: { [weak self] in self?.createNewVault() },
                onSwitchVault: { [weak self] descriptor in self?.switchVault(to: descriptor) }
            )
        )
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: hosting)
            window.title = "Préférences"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        } else {
            preferencesWindow?.contentViewController = hosting
        }
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    /// §5, backlog V3 : ouvre un dossier vide ou déjà utilisé comme coffre, l'enregistre dans le
    /// registre puis y bascule immédiatement — jamais deux étapes séparées qui laisseraient un
    /// coffre enregistré mais jamais ouvert.
    private func createNewVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Choisissez ou créez un dossier pour le nouveau coffre"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let nameAlert = NSAlert()
        nameAlert.messageText = "Nommez ce coffre"
        nameAlert.informativeText = "Ce nom n'apparaît que dans Drop, jamais sur le disque."
        nameAlert.addButton(withTitle: "Créer")
        nameAlert.addButton(withTitle: "Annuler")
        let nameField = NSTextField(string: folder.lastPathComponent)
        nameField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        nameAlert.accessoryView = nameField
        guard nameAlert.runModal() == .alertFirstButtonReturn else { return }

        let trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = vaultRegistry.registerVault(
            name: trimmedName.isEmpty ? folder.lastPathComponent : trimmedName, path: folder.path
        )
        switchVault(to: descriptor)
    }

    /// §5, backlog V3 : reconstruit `environment` contre un autre coffre et referme les fenêtres
    /// liées à l'ancien — leur état (résultats de recherche, corbeille chargée…) appartient au
    /// coffre qui vient de se refermer, jamais à celui qui s'ouvre.
    private func switchVault(to descriptor: VaultDescriptor) {
        guard descriptor.path != environment.vaultRoot.path else { return }

        let newRoot = URL(fileURLWithPath: descriptor.path)
        guard Self.acquireSingleInstanceLock(vaultRoot: newRoot), let newEnvironment = try? AppEnvironment(vaultRoot: newRoot) else {
            let alert = NSAlert()
            alert.messageText = "Impossible d'ouvrir ce coffre"
            alert.informativeText = "« \(descriptor.path) » n'est peut-être plus accessible, ou déjà ouvert par une autre instance de Drop."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }

        popover?.close()
        searchWindow?.close(); searchWindow = nil
        trashWindow?.close(); trashWindow = nil
        preferencesWindow?.close(); preferencesWindow = nil

        environment = newEnvironment
        vaultRegistry.setActiveVault(id: descriptor.id)
        setUpPopover()
        dropTargetView.setProcessing(false)
        wirePendingAnalysisIndicator()
    }

    func openTrashWindow() {
        popover.close()
        NSApp.activate(ignoringOtherApps: true)

        if trashWindow == nil {
            let hosting = NSHostingController(rootView: TrashView(environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Corbeille"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            trashWindow = window
        }
        trashWindow?.center()
        trashWindow?.makeKeyAndOrderFront(nil)
    }

    private func openOnboardingWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if onboardingWindow == nil {
            let hosting = NSHostingController(
                rootView: OnboardingView(
                    vaultLocation: environment.vaultRoot, globalShortcut: Self.globalShortcutDescription,
                    onChooseVaultLocation: { [weak self] in self?.showVaultLocationChangeNotYetAvailableAlert() },
                    onTryDemoDrop: { [weak self] in self?.dropDemoFile() },
                    onFinish: { [weak self] in self?.finishOnboarding() }
                )
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Bienvenue dans Drop"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        onboardingWindow?.close()
    }

    /// EF-20 : changer d'emplacement avec migration vérifiée n'est pas encore câblé (cf.
    /// `PreferencesView`) — un bouton qui ne ferait rien silencieusement serait pire qu'une
    /// alerte honnête sur cette limite actuelle.
    private func showVaultLocationChangeNotYetAvailableAlert() {
        let alert = NSAlert()
        alert.messageText = "Pas encore disponible"
        alert.informativeText = "Le changement d'emplacement du coffre avec migration arrive dans une prochaine version. Le coffre reste pour l'instant à l'emplacement affiché."
        alert.runModal()
    }

    /// Dépôt de démonstration réel (EX-06) : un vrai fichier, ingéré par le même chemin qu'un
    /// glisser-déposer — pas une simulation qui ferait croire à une fonctionnalité factice.
    private func dropDemoFile() {
        let content = """
        Bienvenue dans Drop.

        Ceci est un document de démonstration. Déposez vos propres fichiers sur l'icône de la \
        barre de menus pour les rendre immédiatement cherchables en langage naturel.
        """
        let demoURL = FileManager.default.temporaryDirectory.appendingPathComponent("Bienvenue dans Drop.txt")
        try? content.write(to: demoURL, atomically: true, encoding: .utf8)
        environment.handleDrop(of: [demoURL])
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
