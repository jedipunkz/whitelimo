import Foundation
import MenuKit

/// The on-disk state of the application: the access token plus the menu that
/// was built the last time the appliances were fetched.
public struct Configuration: Codable, Equatable, Sendable {
    /// The Nature Remo personal access token.
    public var token: String
    /// The account the token belongs to, shown at the top of the menu.
    public var userNickname: String?
    /// The cached menu, so the menu bar has something to show before — or
    /// without — talking to the API.
    public var appliances: [ApplianceMenu]
    /// The appliances the last fetch could not turn into menu entries, kept so
    /// whitelimo can explain their absence at any time.
    public var skipped: [SkippedAppliance]
    /// When `appliances` was last refreshed.
    public var fetchedAt: Date?

    public init(
        token: String = "",
        userNickname: String? = nil,
        appliances: [ApplianceMenu] = [],
        skipped: [SkippedAppliance] = [],
        fetchedAt: Date? = nil
    ) {
        self.token = token
        self.userNickname = userNickname
        self.appliances = appliances
        self.skipped = skipped
        self.fetchedAt = fetchedAt
    }

    /// Whether an access token has been stored.
    public var isConfigured: Bool { !token.isEmpty }

    enum CodingKeys: String, CodingKey {
        case token
        case userNickname = "user_nickname"
        case appliances
        case skipped
        case fetchedAt = "fetched_at"
    }

    // Written out by hand so that a configuration file from an older version —
    // or one edited by a user — keeps loading when a key is missing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        userNickname = try container.decodeIfPresent(String.self, forKey: .userNickname)
        // The menu is only a cache, and a newer whitelimo may have written an
        // action kind this one does not know. Losing the cache costs a refresh;
        // throwing here would cost the token stored alongside it.
        appliances = (try? container.decodeIfPresent([ApplianceMenu].self, forKey: .appliances)) ?? []
        skipped = (try? container.decodeIfPresent([SkippedAppliance].self, forKey: .skipped)) ?? []
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encodeIfPresent(userNickname, forKey: .userNickname)
        if !appliances.isEmpty {
            try container.encode(appliances, forKey: .appliances)
        }
        if !skipped.isEmpty {
            try container.encode(skipped, forKey: .skipped)
        }
        try container.encodeIfPresent(fetchedAt, forKey: .fetchedAt)
    }
}
