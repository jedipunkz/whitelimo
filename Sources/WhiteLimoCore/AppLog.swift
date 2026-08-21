import Foundation

/// Appends to a log file next to the configuration.
///
/// A menu bar app has no console, so the log is the only record of what went
/// wrong. It is deliberately tiny: one line per event, and the file starts over
/// once it grows past a megabyte.
public final class AppLog: @unchecked Sendable {
    /// How large the log may grow before it is started over.
    public static let maximumSize: UInt64 = 1 << 20

    private let lock = NSLock()
    private var handle: FileHandle?
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
        _ = try? handle.seekToEnd()
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
        let line = "\(formatter.string(from: Date())) \(message)\n"
        try? handle.write(contentsOf: Data(line.utf8))
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        handle = nil
    }
}
