import SwiftUI
import UniformTypeIdentifiers

/// Contenu du popover de la tray icon (EX-01, EX-02) : zone de glisser-déposer, puis les mêmes
/// trois actions qu'un menu classique (rechercher, préférences, quitter) — en style `.window`
/// pour que le glisser-déposer fonctionne (le style `.menu` de `MenuBarExtra` ne le permet pas).
struct DropZoneView: View {
    let environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            dropZone
            Divider()
            actionRow(systemImage: "magnifyingglass", title: "Rechercher…") {
                activateAndRun { openWindow(id: "search") }
            }
            actionRow(systemImage: "gearshape", title: "Préférences…") {
                activateAndRun { openSettings() }
            }
            actionRow(systemImage: "power", title: "Quitter Drop") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    /// Sans ceci, `openWindow`/`openSettings` déclenchés depuis le popover d'une `MenuBarExtra`
    /// n'amènent parfois aucune fenêtre au premier plan : l'app (accessoire, sans icône Dock)
    /// n'est jamais devenue « active » au sens AppKit tant qu'on reste dans le popover. Activer
    /// explicitement avant d'ouvrir la scène est le correctif documenté pour ce cas.
    private func activateAndRun(_ action: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            action()
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )

            VStack(spacing: 6) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 26))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.bounce, value: environment.dropZoneState)
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(14)
        }
        .frame(height: 110)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handle(providers)
            return true
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private func actionRow(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(systemImage: systemImage, title: title)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func handle(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    environment.handleDrop(of: [url])
                }
            }
        }
    }

    private var statusSymbol: String {
        switch environment.dropZoneState {
        case .idle, .hovering: return "tray.and.arrow.down"
        case .ingesting: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .duplicate: return "doc.on.doc"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch environment.dropZoneState {
        case .idle, .hovering, .ingesting: return .secondary
        case .success: return .green
        case .duplicate: return .orange
        case .failure: return .red
        }
    }

    private var statusText: String {
        switch environment.dropZoneState {
        case .idle: return "Déposez un document ici"
        case .hovering: return "Relâchez pour déposer"
        case .ingesting(let name): return "Ingestion de « \(name) »…"
        case .success(let name): return "« \(name) » ajouté au coffre"
        case .duplicate(let name): return "« \(name) » est déjà dans le coffre"
        case .failure(let name, let message): return "« \(name) » : \(message)"
        }
    }
}

#Preview {
    DropZoneView(environment: try! AppEnvironment(vaultRoot: FileManager.default.temporaryDirectory.appendingPathComponent("drop-preview")))
}
