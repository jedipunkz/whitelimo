import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A small client for the Nature Remo Cloud API.
///
/// See <https://swagger.nature.global/> for the API reference. Every request is
/// authenticated with a personal access token issued at
/// <https://home.nature.global/>.
public final class RemoClient: @unchecked Sendable {
    /// The production endpoint.
    public static let defaultBaseURL = URL(string: "https://api.nature.global")!
    /// How long a single call may take.
    public static let defaultTimeout: TimeInterval = 15

    public let baseURL: URL

    private let token: String
    private let session: URLSession

    private let lock = NSLock()
    private var storedRateLimit = RateLimit()

    public init(token: String, baseURL: URL = RemoClient.defaultBaseURL, session: URLSession? = nil) {
        self.token = token
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = RemoClient.defaultTimeout
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    /// The throttling state observed on the most recent response.
    public var rateLimit: RateLimit {
        lock.lock()
        defer { lock.unlock() }
        return storedRateLimit
    }

    // MARK: - Endpoints

    /// The owner of the access token. This is the cheapest call available and is
    /// used to check a token the user just typed in.
    public func me() async throws -> User {
        try await get("/1/users/me")
    }

    /// The Nature Remo devices registered on the account.
    public func devices() async throws -> [Device] {
        try await get("/1/devices")
    }

    /// Every appliance on the account, including the buttons and the learned IR
    /// signals that control them.
    public func appliances() async throws -> [Appliance] {
        try await get("/1/appliances")
    }

    /// Emits a learned IR signal.
    public func sendSignal(id: String) async throws {
        guard !id.isEmpty else { throw RemoError.missingIdentifier("signal id") }
        _ = try await send(method: "POST", path: "/1/signals/\(escape(id))/send", form: [:])
    }

    /// Presses a predefined button of a light appliance.
    @discardableResult
    public func sendLightButton(applianceID: String, button: String) async throws -> LightState {
        guard !applianceID.isEmpty else { throw RemoError.missingIdentifier("appliance id") }
        let data = try await send(
            method: "POST",
            path: "/1/appliances/\(escape(applianceID))/light",
            form: ["button": button]
        )
        return try decode(LightState.self, from: data)
    }

    /// Presses a predefined button of a TV appliance.
    @discardableResult
    public func sendTVButton(applianceID: String, button: String) async throws -> TVState {
        guard !applianceID.isEmpty else { throw RemoError.missingIdentifier("appliance id") }
        let data = try await send(
            method: "POST",
            path: "/1/appliances/\(escape(applianceID))/tv",
            form: ["button": button]
        )
        return try decode(TVState.self, from: data)
    }

    /// Changes the air conditioner settings. Only the fields set in `parameters`
    /// are sent, and the API merges them into the current settings.
    @discardableResult
    public func updateAirconSettings(
        applianceID: String,
        parameters: AirconParameters
    ) async throws -> AirconSettings {
        guard !applianceID.isEmpty else { throw RemoError.missingIdentifier("appliance id") }
        let form = parameters.formFields
        guard !form.isEmpty else { throw RemoError.missingIdentifier("air conditioner setting to update") }
        let data = try await send(
            method: "POST",
            path: "/1/appliances/\(escape(applianceID))/aircon_settings",
            form: form
        )
        return try decode(AirconSettings.self, from: data)
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(method: "GET", path: path, form: nil)
        return try decode(T.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RemoError.decoding(error.localizedDescription)
        }
    }

    private func send(method: String, path: String, form: [String: String]?) async throws -> Data {
        guard !token.isEmpty else { throw RemoError.missingToken }

        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw RemoError.transport("cannot build a URL for \(path)")
        }

        var request = URLRequest(url: url.absoluteURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(RemoClient.userAgent, forHTTPHeaderField: "User-Agent")
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(RemoClient.encodeForm(form).utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RemoError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RemoError.transport("the response was not an HTTP response")
        }

        let limit = RemoClient.rateLimit(from: http)
        lock.lock()
        storedRateLimit = limit
        lock.unlock()

        guard (200...299).contains(http.statusCode) else {
            throw RemoError.api(
                status: http.statusCode,
                message: RemoClient.message(from: data),
                rateLimit: limit
            )
        }
        return data
    }

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    static let userAgent = "whitelimo (+https://github.com/jedipunkz/whitelimo)"

    /// How much of a failed response ends up in an error message. The API is
    /// free to answer with anything at all — an HTML page from a proxy, say —
    /// and that text lands in an alert, so it cannot be shown in whole.
    static let maximumErrorDetail = 200

    static func rateLimit(from response: HTTPURLResponse) -> RateLimit {
        var limit = RateLimit()
        if let value = response.value(forHTTPHeaderField: "X-Rate-Limit-Limit") {
            limit.limit = Int(value)
        }
        if let value = response.value(forHTTPHeaderField: "X-Rate-Limit-Remaining") {
            limit.remaining = Int(value)
        }
        if let value = response.value(forHTTPHeaderField: "X-Rate-Limit-Reset"),
           let seconds = TimeInterval(value), seconds > 0 {
            limit.reset = Date(timeIntervalSince1970: seconds)
        }
        return limit
    }

    /// Digs the human readable message out of an error payload. The API answers
    /// with `{"code": .., "message": ".."}` for most failures, but a proxy or a
    /// gateway in front of it may answer with anything, so the raw body is the
    /// fallback.
    static func message(from data: Data) -> String {
        struct Payload: Decodable {
            var message: String?
            var detail: String?
        }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            if let message = payload.message, !message.isEmpty {
                return truncate(message, to: maximumErrorDetail)
            }
            if let detail = payload.detail, !detail.isEmpty {
                return truncate(detail, to: maximumErrorDetail)
            }
        }
        let body = String(decoding: data, as: UTF8.self)
        return truncate(body.split(whereSeparator: \.isWhitespace).joined(separator: " "), to: maximumErrorDetail)
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    /// Form-encodes the fields, sorted by name so the body is deterministic.
    static func encodeForm(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.keys.sorted().map { key in
            let name = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let value = fields[key] ?? ""
            return "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }
}
