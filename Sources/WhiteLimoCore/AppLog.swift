import Foundation

/// Appends to a log file next to the configuration.
///
/// A menu bar app has no console, so the log is the only record of what went
/// wrong. It is deliberately tiny: one line per event, and the file starts over
/// once it grows past a megabyte -- while running as well as at launch, because
/// whitelimo is started at login and left alone for weeks.
public final class AppLog: @unchecked Sendable {
    /// How large the log may grow before it is started over.
    public static let maximumSize: UInt64 = 1 << 20

    private let lock = NSLock()
    private var handle: FileHandle?
    private var written: UInt64 = 0
    private let formatter: DateFormatter

    public private(set) var url: URL?

    /// Opens the log at `url`. A log that cannot be opened is not an error worth
    /// bothering the user with: the messages are dropped instead.
    public init(url: URL?) {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let url else { return }

        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return
        }

        let attributes = try? manager.attributesOfItem(atPath: url.path)
        if let size = attributes?[.size] as? NSNumber, size.uint64Value > AppLog.maximumSize {
            try? manager.removeItem(at: url)
        }
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        written = (try? handle.seekToEnd()) ?? 0
        self.handle = handle
        self.url = url
    }

    deinit {
        try? handle?.close()
    }

    public func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return }
        let line = Data("\(formatter.string(from: Date())) \(message)\n".utf8)
        try? handle.write(contentsOf: line)
        written += UInt64(line.count)
        if written > AppLog.maximumSize {
            // Truncating in place rather than deleting and recreating keeps the
            // file's owner-only permissions and the open handle.
            try? handle.truncate(atOffset: 0)
            try? handle.seek(toOffset: 0)
            written = 0
        }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        handle = nil
    }
}
