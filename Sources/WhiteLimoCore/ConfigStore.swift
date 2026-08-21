import Foundation

/// Why a configuration file could not be read or written.
public enum ConfigError: Error, LocalizedError {
    case noHomeDirectory
    case unreadable(URL, String)
    case unparsable(URL, String)
    case unwritable(URL, String)

    public var errorDescription: String? {
        switch self {
        case .noHomeDirectory:
            return "Cannot locate the Application Support directory."
        case let .unreadable(url, detail):
            return "Cannot read \(url.path): \(detail)"
        case let .unparsable(url, detail):
            return "Cannot parse \(url.path): \(detail)"
        case let .unwritable(url, detail):
            return "Cannot write \(url.path): \(detail)"
        }
    }
}

/// Reads and writes the configuration file.
///
/// It lives at `~/Library/Application Support/whitelimo/config.json`. The
/// location can be overridden with the `WHITELIMO_CONFIG` environment variable,
/// which is handy for testing and for keeping the token on a removable volume.
public struct ConfigStore: Sendable {
    /// The environment variable that overrides the configuration path.
    public static let environmentKey = "WHITELIMO_CONFIG"
    /// The name of the folder the configuration and the log file share.
    public static let directoryName = "whitelimo"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        self.url = try ConfigStore.defaultURL(environment: environment)
    }

    /// Where the configuration is stored.
    public static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let path = environment[environmentKey], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ConfigError.noHomeDirectory
        }
        return support
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    /// The folder holding the configuration file and the log.
    public var directory: URL {
        url.deletingLastPathComponent()
    }

    /// Reads the configuration. A missing file is not an error: an empty
    /// configuration comes back, so the caller can ask for a token.
    public func load() throws -> Configuration {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return Configuration()
        } catch {
            throw ConfigError.unreadable(url, error.localizedDescription)
        }
        if data.isEmpty {
            return Configuration()
        }
        do {
            return try ConfigStore.decoder.decode(Configuration.self, from: data)
        } catch {
            throw ConfigError.unparsable(url, error.localizedDescription)
        }
    }

    /// Writes the configuration. The file holds an access token, so the folder
    /// and the file are created with owner-only permissions, and the write goes
    /// through a temporary file so a crash cannot truncate a working config.
    public func save(_ configuration: Configuration) throws {
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ConfigError.unwritable(directory, error.localizedDescription)
        }

        var data = try ConfigStore.encoder.encode(configuration)
        data.append(0x0A)

        let temporary = directory.appendingPathComponent(
            ".config-\(UUID().uuidString).json",
            isDirectory: false
        )
        do {
            try data.write(to: temporary, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            if manager.fileExists(atPath: url.path) {
                // .usingNewMetadataOnly, or the permissions of whatever config
                // file happened to be there before win over the 0600 above.
                _ = try manager.replaceItemAt(
                    url,
                    withItemAt: temporary,
                    options: .usingNewMetadataOnly
                )
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw ConfigError.unwritable(url, error.localizedDescription)
        }
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
