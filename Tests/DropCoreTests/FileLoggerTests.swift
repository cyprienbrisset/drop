import DropCore
import Foundation
import Testing

/// Système de fichiers en mémoire, pour tester la journalisation et la purge sans toucher le disque.
final class InMemoryFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []

    func fileExists(at url: URL) -> Bool {
        lock.withLock { files[url.path] != nil }
    }

    func fileSize(at url: URL) throws -> Int64 {
        lock.withLock { Int64(files[url.path]?.count ?? 0) }
    }

    func modificationDate(at url: URL) throws -> Date { .distantPast }

    func createDirectory(at url: URL) throws {
        lock.withLock { directories.insert(url.path) }
    }

    func moveItem(at source: URL, to destination: URL) throws {
        lock.withLock {
            files[destination.path] = files.removeValue(forKey: source.path)
        }
    }

    func removeItem(at url: URL) throws {
        lock.withLock { _ = files.removeValue(forKey: url.path) }
    }

    func read(at url: URL) throws -> Data {
        guard let data = lock.withLock({ files[url.path] }) else {
            throw DropError(code: "TEST-404", message: "not found")
        }
        return data
    }

    func write(_ data: Data, to url: URL) throws {
        lock.withLock { files[url.path] = data }
    }

    func syncFile(at url: URL) throws {}
    func syncDirectory(at url: URL) throws {}

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        lock.withLock {
            files.keys
                .filter { $0.hasPrefix(url.path) }
                .map { URL(fileURLWithPath: $0) }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

struct FixedClock: DropClock {
    let date: Date
    func now() -> Date { date }
}

@Test func loggerAppendsLinesToTodaysFile() {
    let fileSystem = InMemoryFileSystem()
    let directory = URL(fileURLWithPath: "/logs")
    let clock = FixedClock(date: Date(timeIntervalSince1970: 1_755_158_400)) // 2025-08-14
    let logger = FileLogger(directory: directory, fileSystem: fileSystem, clock: clock)

    logger.log(.info, code: "DROP-ING-000", message: "ingestion démarrée")
    logger.log(.error, code: "DROP-ING-004", message: "divergence de hash")

    let content = try! fileSystem.read(at: directory.appendingPathComponent("drop-2025-08-14.log"))
    let text = String(data: content, encoding: .utf8)!
    #expect(text.contains("DROP-ING-000"))
    #expect(text.contains("DROP-ING-004"))
}

@Test func pruneRemovesLogsOlderThanRetention() {
    let fileSystem = InMemoryFileSystem()
    let directory = URL(fileURLWithPath: "/logs")
    let now = Date(timeIntervalSince1970: 1_755_158_400) // 2025-08-14
    let clock = FixedClock(date: now)
    let logger = FileLogger(directory: directory, fileSystem: fileSystem, clock: clock)

    let oldFile = directory.appendingPathComponent("drop-2025-07-01.log")
    let recentFile = directory.appendingPathComponent("drop-2025-08-13.log")
    try! fileSystem.write(Data("old".utf8), to: oldFile)
    try! fileSystem.write(Data("recent".utf8), to: recentFile)

    logger.pruneOldLogs(retentionDays: 7)

    #expect(!fileSystem.fileExists(at: oldFile))
    #expect(fileSystem.fileExists(at: recentFile))
}
