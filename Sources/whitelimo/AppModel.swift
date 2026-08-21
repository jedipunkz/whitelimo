import Foundation
import MenuKit
import RemoKit
import WhiteLimoCore

/// A failure that belongs to whitelimo itself rather than to the API.
enum AppError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No access token is configured yet. Pick “Set Access Token…” from the menu."
        }
    }
}

/// The state the menu is built from, and the operations the menu triggers.
///
/// Everything here runs on the main actor: the menu reads it while it is being
/// rebuilt, and every API call ends by updating it.
@MainActor
final class AppModel {
    /// The name shown in the menu and in alerts.
    static let name = "whitelimo"

    /// Where a Nature Remo personal access token can be issued.
    static let tokenPage = URL(string: "https://home.nature.global/")!

    /// The version baked into the app bundle, or "dev" when whitelimo is run
    /// straight out of the build directory.
    static let version: String = {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let short, !short.isEmpty else { return "dev" }
        return short
    }()

    private(set) var configuration = Configuration()
    /// The outcome of the last action, shown at the top of the menu.
    private(set) var status = ""

    private let store: ConfigStore?
    private let log: AppLog
    private var client: RemoClient?

    /// Loads the configuration. A configuration that cannot be read is reported
    /// through `warn` and replaced by an empty one, so the user can still run
    /// the setup from the menu.
    init(warn: (String) -> Void) {
        let store = try? ConfigStore()
        self.store = store
        log = AppLog(url: store?.directory.appendingPathComponent("whitelimo.log", isDirectory: false))

        guard let store else {
            warn("Cannot locate the configuration folder. Settings will not be saved.")
            return
        }
        do {
            configuration = try store.load()
        } catch {
            log.write("cannot load the configuration: \(error.localizedDescription)")
            warn("Cannot read the configuration file, so whitelimo started with an empty one.\n\n\(error.localizedDescription)")
        }
        if configuration.isConfigured {
            client = RemoClient(token: configuration.token)
        }
        log.write("---- \(AppModel.name) \(AppModel.version) started ----")
    }

    /// Where the configuration is stored, if the folder could be located.
    var configurationURL: URL? { store?.url }

    /// The disabled first line of the menu, naming the account the stored token
    /// belongs to.
    var headerText: String {
        guard configuration.isConfigured else {
            return "\(AppModel.name) \(AppModel.version) — not set up"
        }
        if let nickname = configuration.userNickname, !nickname.isEmpty {
            return "\(AppModel.name) \(AppModel.version) — \(nickname)"
        }
        return "\(AppModel.name) \(AppModel.version)"
    }

    var aboutText: String {
        var lines: [String] = []
        lines.append("Control Nature Remo from the menu bar.")
        lines.append("")
        if let nickname = configuration.userNickname, !nickname.isEmpty {
            lines.append("Account: \(nickname)")
        }
        lines.append("Appliances: \(configuration.appliances.count)")
        if !configuration.skipped.isEmpty {
            lines.append("Not controllable: \(configuration.skipped.count) (\(skippedList))")
        }
        if let fetchedAt = configuration.fetchedAt {
            lines.append("Last fetched: \(AppModel.timestamp.string(from: fetchedAt))")
        }
        if let url = configurationURL {
            lines.append("Configuration: \(url.path)")
        }
        lines.append("Access tokens: \(AppModel.tokenPage.absoluteString)")
        return lines.joined(separator: "\n")
    }

    /// Names the skipped appliances, keeping the text short enough for an alert
    /// when an account has many of them.
    var skippedList: String {
        let shown = 3
        let names = configuration.skipped.prefix(shown).map(\.summary)
        if configuration.skipped.count > shown {
            return names.joined(separator: ", ") + " and \(configuration.skipped.count - shown) more"
        }
        return names.joined(separator: ", ")
    }

    /// The sentence appended to a setup summary when some appliances could not
    /// be turned into menu entries.
    var skippedNote: String {
        guard !configuration.skipped.isEmpty else { return "" }
        return """

            Cannot be controlled: \(configuration.skipped.count) (\(skippedList))
            whitelimo supports infrared remotes, air conditioners, lights and TVs.
            """
    }

    func setStatus(_ text: String) {
        status = text
    }

    /// Stores a token, checks it against the API and rebuilds the menu from the
    /// appliances the account holds. Returns a summary for the confirmation
    /// alert.
    func configure(token: String) async throws -> String {
        let candidate = RemoClient(token: token)
        let user = try await candidate.me()

        configuration.token = token
        configuration.userNickname = user.nickname
        client = candidate
        // Save before fetching: a token that works is worth keeping even if the
        // appliance list cannot be fetched right now.
        save()
        log.write("token accepted for \(user.nickname)")

        let tree = try await fetchAppliances()
        return """
            Signed in as \(user.nickname).
            Appliances: \(tree.appliances.count)\(skippedNote)
            """
    }

    /// Fetches the appliances again and rebuilds the cached menu.
    @discardableResult
    func fetchAppliances() async throws -> MenuTree {
        guard let client else { throw AppError.notConfigured }
        let appliances = try await client.appliances()
        let tree = MenuBuilder.build(from: appliances)

        configuration.appliances = tree.appliances
        configuration.skipped = tree.skipped
        configuration.fetchedAt = Date()
        save()
        log.write("fetched \(tree.appliances.count) appliances, skipped \(tree.skipped.count)")
        return tree
    }

    /// Runs one menu entry and returns the status line to show for it.
    func perform(_ action: MenuAction) async throws -> String {
        guard let client else { throw AppError.notConfigured }
        do {
            let summary = try await MenuExecutor.execute(action, using: client)
            let text = summary.isEmpty ? "\(action.label) sent" : "\(action.label): \(summary)"
            log.write("\(action.kind.rawValue) \(action.applianceID) \(action.value) -> \(text)")
            return text
        } catch {
            log.write("\(action.kind.rawValue) \(action.applianceID) \(action.value) failed: \(error.localizedDescription)")
            throw error
        }
    }

    func note(_ message: String) {
        log.write(message)
    }

    func save() {
        guard let store else { return }
        do {
            try store.save(configuration)
        } catch {
            log.write("cannot save the configuration: \(error.localizedDescription)")
        }
    }

    func shutDown() {
        log.write("---- \(AppModel.name) stopped ----")
        log.close()
    }

    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

/// Renders an error for an alert, adding a hint for the failures a user can
/// actually do something about.
func describe(_ error: Error) -> String {
    guard let remo = error as? RemoError else {
        return error.localizedDescription
    }
    if remo.isUnauthorized {
        return """
            The access token was rejected. Set it again from “Set Access Token…”.

            \(remo.localizedDescription)
            """
    }
    if remo.isRateLimited {
        return """
            The API rate limit was reached. The Nature Remo API allows 30 requests every 5 minutes. \(retryHint(remo))

            \(remo.localizedDescription)
            """
    }
    return remo.localizedDescription
}

/// Turns the `X-Rate-Limit-Reset` header sent with a 429 into something the user
/// can act on.
func retryHint(_ error: RemoError) -> String {
    guard let seconds = error.rateLimit?.retryAfter else {
        return "Please wait a while and try again."
    }
    let minutes = Int(seconds / 60) + 1
    let resumesAt = Date().addingTimeInterval(seconds)
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return "You can try again in about \(minutes) min (around \(formatter.string(from: resumesAt)))."
}
