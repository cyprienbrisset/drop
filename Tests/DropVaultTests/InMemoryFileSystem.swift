import DropCore
import Foundation

/// Système de fichiers en mémoire, pour tester l'ingestion sans toucher le disque.
final class InMemoryFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]

    func seed(_ path: String, contents: Data) {
        lock.withLock { files[path] = contents }
    }

    func fileExists(at url: URL) -> Bool {
        lock.withLock { files[url.path] != nil }
    }

    func fileSize(at url: URL) throws -> Int64 {
        guard let data = lock.withLock({ files[url.path] }) else {
            throw DropError(code: "TEST-404", message: "not found")
        }
        return Int64(data.count)
    }

    func modificationDate(at url: URL) throws -> Date { .distantPast }

    func createDirectory(at url: URL) throws {}

    func moveItem(at source: URL, to destination: URL) throws {
        lock.withLock { files[destination.path] = files.removeValue(forKey: source.path) }
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
        lock.withLock { files.keys.filter { $0.hasPrefix(url.path) }.map { URL(fileURLWithPath: $0) } }
    }

    func copyItem(at source: URL, to destination: URL) throws {
        guard let data = lock.withLock({ files[source.path] }) else {
            throw DropError(code: "TEST-404", message: "not found")
        }
        lock.withLock { files[destination.path] = data }
    }

    func forEachChunk(at url: URL, chunkSize: Int, _ body: (Data) throws -> Void) throws {
        guard let data = lock.withLock({ files[url.path] }) else {
            throw DropError(code: "TEST-404", message: "not found")
        }
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            try body(data.subdata(in: offset..<end))
            offset = end
        }
    }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
