import AppKit
import FoundationModels
import Foundation

/// Validation bloquante A (§5.4.5, §9 Phase 0, DRO-16) : la disponibilité de l'inférence
/// FoundationModels lorsque le processus n'est pas au premier plan n'est pas garantie
/// contractuellement par Apple. Ce protocole mesure le comportement réel.
///
/// Mode d'emploi : lancez `swift run ValidationHarness a --minutes 10`, puis **passez
/// immédiatement à une autre application** (⌘⇥) et laissez tourner. Le rapport final indique,
/// pour chaque tentative, si le Terminal était au premier plan et si l'inférence a réussi.
func runValidationA(durationMinutes: Int) async throws {
    print("Validation A — inférence en arrière-plan (\(durationMinutes) min). Passez à une autre application maintenant (⌘⇥).")

    let model = SystemLanguageModel.default
    var results: [ValidationAAttempt] = []
    let deadline = Date().addingTimeInterval(Double(durationMinutes) * 60)
    let probeInterval: TimeInterval = 15

    while Date() < deadline {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isSelfFrontmost = frontmost == Bundle.main.bundleIdentifier || frontmost == nil

        let attemptStart = Date()
        var succeeded = false
        var failureReason: String?

        switch model.availability {
        case .available:
            do {
                let session = LanguageModelSession(model: model)
                _ = try await session.respond(to: "Réponds uniquement par le mot: ok")
                succeeded = true
            } catch {
                failureReason = String(describing: error)
            }
        case .unavailable(let reason):
            failureReason = "unavailable(\(reason))"
        }

        let latency = Date().timeIntervalSince(attemptStart)
        results.append(
            ValidationAAttempt(
                timestamp: attemptStart, selfWasFrontmost: isSelfFrontmost,
                succeeded: succeeded, latencySeconds: latency, failureReason: failureReason
            )
        )
        print(
            "[\(attemptStart.formatted(.iso8601))] frontmost=\(isSelfFrontmost) succeeded=\(succeeded) "
                + "latency=\(String(format: "%.2f", latency))s" + (failureReason.map { " reason=\($0)" } ?? "")
        )

        try await Task.sleep(for: .seconds(probeInterval))
    }

    printValidationAReport(results)
}

struct ValidationAAttempt {
    let timestamp: Date
    let selfWasFrontmost: Bool
    let succeeded: Bool
    let latencySeconds: TimeInterval
    let failureReason: String?
}

private func printValidationAReport(_ attempts: [ValidationAAttempt]) {
    let backgrounded = attempts.filter { !$0.selfWasFrontmost }
    let backgroundedSuccesses = backgrounded.filter(\.succeeded)

    print("\n=== Rapport Validation A ===")
    print("Tentatives totales : \(attempts.count)")
    print("Tentatives en arrière-plan : \(backgrounded.count)")
    print(
        "Succès en arrière-plan : \(backgroundedSuccesses.count)/\(backgrounded.count)"
            + (backgrounded.isEmpty ? " (aucune mesure en arrière-plan — avez-vous changé d'application ?)" : "")
    )
    print("""

    Critère de décision (§5.4.5) :
      - Si le taux de succès en arrière-plan est proche du taux au premier plan → l'inférence
        fonctionne hors premier plan, aucun plan B nécessaire.
      - Si le taux de succès chute significativement en arrière-plan → activer le plan B déjà
        arrêté par le CDC : vidage de la file sémantique à l'ouverture de la Drop Zone ou de la
        barre de recherche, avec progression visible (DRO-31).
    """)
}
