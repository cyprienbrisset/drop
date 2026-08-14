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
