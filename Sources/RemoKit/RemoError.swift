import Foundation

/// The throttling state reported by the `X-Rate-Limit-*` response headers. The
/// Nature Remo Cloud API allows 30 requests per five minutes.
public struct RateLimit: Equatable, Sendable {
    public var limit: Int?
    public var remaining: Int?
    public var reset: Date?

    public init(limit: Int? = nil, remaining: Int? = nil, reset: Date? = nil) {
        self.limit = limit
        self.remaining = remaining
        self.reset = reset
    }

    /// How long to wait before the window resets, or nil when it already has or
    /// the API did not say.
    public var retryAfter: TimeInterval? {
        guard let reset else { return nil }
        let seconds = reset.timeIntervalSinceNow
        return seconds > 0 ? seconds : nil
    }
}

/// Everything that can go wrong while talking to the API.
public enum RemoError: Error, Equatable, Sendable {
    /// No access token has been configured yet.
    case missingToken
    /// A required identifier was empty, which would produce a nonsense URL.
    case missingIdentifier(String)
    /// The request never made it to a response.
    case transport(String)
    /// The API answered with a non-2xx status.
    case api(status: Int, message: String, rateLimit: RateLimit)
    /// The response arrived but could not be understood.
    case decoding(String)

    /// Whether the failure is an authentication one, i.e. the access token is
    /// missing, malformed or revoked.
    public var isUnauthorized: Bool {
        switch self {
        case .missingToken:
            return true
        case let .api(status, _, _):
            return status == 401 || status == 403
        default:
            return false
        }
    }

    /// Whether the failure was caused by exceeding the API quota.
    public var isRateLimited: Bool {
        if case let .api(status, _, _) = self {
            return status == 429
        }
        return false
    }

    /// The throttling state reported alongside the failure, when there was one.
    public var rateLimit: RateLimit? {
        if case let .api(_, _, rateLimit) = self {
            return rateLimit
        }
        return nil
    }
}

extension RemoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No access token is configured."
        case let .missingIdentifier(what):
            return "Missing \(what)."
        case let .transport(detail):
            return "Cannot reach the Nature Remo API: \(detail)"
        case let .api(status, message, _):
            let text = message.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : message
            return "Nature Remo API: \(status) \(text)"
        case let .decoding(detail):
            return "Cannot read the response from the Nature Remo API: \(detail)"
        }
    }
}
