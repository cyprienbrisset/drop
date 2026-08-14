import Foundation

public enum LogLevel: String, Sendable {
    case debug, info, warning, error
}

/// Journal local rotatif (`logs/`, §4.3), 7 jours par défaut. Ne contient jamais de donnée de
/// contenu documentaire — uniquement identifiants, tailles, durées, codes d'erreur (§7.1).
/// Chaque appelant reste responsable de ne jamais passer de texte extrait dans `message`.
public protocol DropLogger: Sendable {
    func log(_ level: LogLevel, code: String, message: String)
}

public struct FileLogger: DropLogger {
    private let directory: URL
    private let fileSystem: FileSystem
    private let clock: DropClock

    public init(directory: URL, fileSystem: FileSystem = LiveFileSystem(), clock: DropClock = SystemClock()) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.clock = clock
        try? fileSystem.createDirectory(at: directory)
    }

    public func log(_ level: LogLevel, code: String, message: String) {
        let now = clock.now()
        let line = "\(Self.timestampFormatter.string(from: now)) [\(level.rawValue.uppercased())] [\(code)] \(message)\n"
        let fileURL = directory.appendingPathComponent("drop-\(Self.dayFormatter.string(from: now)).log")
        appendLine(line, to: fileURL)
    }

    /// Supprime les fichiers `drop-YYYY-MM-DD.log` antérieurs à la fenêtre de rétention.
    public func pruneOldLogs(retentionDays: Int = 7) {
        guard let entries = try? fileSystem.contentsOfDirectory(at: directory) else { return }
        let cutoff = clock.now().addingTimeInterval(-Double(retentionDays) * 86400)
        for entry in entries {
            guard let day = Self.day(fromLogFileName: entry.lastPathComponent), day < cutoff else { continue }
            try? fileSystem.removeItem(at: entry)
        }
    }

    private func appendLine(_ line: String, to url: URL) {
        let existing = (try? fileSystem.read(at: url)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard let data = (existing + line).data(using: .utf8) else { return }
        try? fileSystem.write(data, to: url)
    }

    static func day(fromLogFileName name: String) -> Date? {
        guard name.hasPrefix("drop-"), name.hasSuffix(".log") else { return nil }
        let dayString = String(name.dropFirst("drop-".count).dropLast(".log".count))
        return dayFormatter.date(from: dayString)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // `ISO8601DateFormatter` n'est pas `Sendable`, mais cette instance est immuable après
    // configuration et n'est jamais mutée après coup — partage sûr entre threads.
    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
