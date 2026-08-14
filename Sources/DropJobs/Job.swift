/// File de travaux persistante (§5.8) : une analyse interrompue reprend, elle ne se perd pas.
/// Priorités par défaut : extract 10, entities 20, thumbnail 30, insight 40, ocr 50, embed 60.
public enum JobKind: String, Sendable {
    case extract, ocr, entities, insight, embed, thumbnail
}

public enum JobState: String, Sendable {
    case queued, running, done, failed, skipped
}

public struct Job: Sendable {
    public let documentID: String
    public let kind: JobKind
    public var priority: Int
    public var state: JobState
    public var attempts: Int

    public init(documentID: String, kind: JobKind, priority: Int, state: JobState = .queued, attempts: Int = 0) {
        self.documentID = documentID
        self.kind = kind
        self.priority = priority
        self.state = state
        self.attempts = attempts
    }

    public static let defaultPriority: [JobKind: Int] = [
        .extract: 10, .entities: 20, .thumbnail: 30, .insight: 40, .ocr: 50, .embed: 60,
    ]
}
