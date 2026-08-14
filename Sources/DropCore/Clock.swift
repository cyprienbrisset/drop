import Foundation

/// Horloge injectable : tout code qui raisonne sur "maintenant" (filtres temporels, stabilité EF-11,
/// backoff DropJobs) passe par ce protocole afin de rester testable de manière déterministe.
public protocol DropClock: Sendable {
    func now() -> Date
}

public struct SystemClock: DropClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Attente injectable : la fenêtre de stabilité (EF-11) doit être testable sans jamais
/// ralentir la suite de tests de deux secondes réelles à chaque cas.
public protocol Sleeper: Sendable {
    func sleep(seconds: Double) async throws
}

public struct SystemSleeper: Sleeper {
    public init() {}
    public func sleep(seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

public struct ImmediateSleeper: Sleeper {
    public init() {}
    public func sleep(seconds: Double) async throws {}
}
