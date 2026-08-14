import AppKit

/// Vue AppKit de l'icône de la barre de menus, capable de détecter un glisser-déposer qui *survole*
/// l'icône — pas seulement un clic. `NSStatusItem.button` (créé par l'API publique moderne) est un
/// `NSStatusBarButton` qu'on ne peut pas sous-classer, et AppKit n'offre aucune autre façon
/// documentée de recevoir un glisser-déposer directement sur une icône de barre de menus.
/// `NSStatusItem.view`, dépréciée depuis 10.10 mais jamais retirée, reste le seul point d'entrée
/// pour un contenu entièrement personnalisé — c'est la technique qu'utilisent encore aujourd'hui
/// des applications de dépôt comme Dropzone ou CleanShot, pour cette raison précise : sans elle,
/// il faut d'abord cliquer pour ouvrir le panneau avant de pouvoir y glisser un fichier, ce qui
/// oblige à viser une icône minuscule pendant tout le geste de glisser-déposer.
final class DropTargetStatusView: NSView {
    var onClick: (() -> Void)?
    var onDragEntered: (() -> Void)?
    var onPerformDrop: (([URL]) -> Void)?

    private let imageView = NSImageView()
    private var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        imageView.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Drop")
        imageView.contentTintColor = .labelColor
        imageView.imageScaling = .scaleProportionallyDown
        imageView.frame = bounds.insetBy(dx: 3, dy: 3)
        imageView.autoresizingMask = [.width, .height]
        // L'image porte déjà une description ; elle ne doit jamais être un second élément
        // VoiceOver distinct de cette vue (`isAccessibilityElement` ci-dessous porte, seule,
        // le rôle et le libellé de l'icône entière).
        imageView.setAccessibilityElement(false)
        addSubview(imageView)
        registerForDraggedTypes([.fileURL])
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    // MARK: - Accessibilité (DRO-50)

    /// `NSStatusItem.view` (voir le commentaire en tête de fichier) contourne
    /// `NSStatusBarButton`, qui expose son rôle/libellé à VoiceOver automatiquement — cette vue
    /// personnalisée doit donc le faire elle-même, sans quoi l'unique point d'entrée de
    /// l'application resterait invisible au rotor VoiceOver.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Drop" }
    override func accessibilityHelp() -> String? {
        "Ouvre le menu de Drop. Glissez un document ici pour le déposer dans le coffre."
    }

    /// VoiceOver déclenche une pression via cette action plutôt qu'un vrai clic souris — sans
    /// elle, l'icône serait annoncée mais jamais activable par un utilisateur VoiceOver.
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isHighlighted = true
        onDragEntered?()
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isHighlighted = false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        isHighlighted = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isHighlighted = false
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty
        else {
            return false
        }
        onPerformDrop?(urls)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }
}
