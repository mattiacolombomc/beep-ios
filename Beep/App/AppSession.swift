import Foundation
import Observation

/// Authentication state shared through the environment.
@Observable
final class AppSession {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(UserProfile)
        /// WeBeep rejected the token; local data is kept until the user signs in again.
        case expired(UserProfile)
    }

    struct UserProfile: Equatable, Codable {
        var id: Int
        var fullname: String
        var username: String
        var pictureURL: URL?
    }

    private(set) var state: State = .loading
    private(set) var token: String?
    private(set) var privateToken: String?
    /// When the current token was obtained (login or silent renewal).
    private(set) var tokenIssuedAt: Date?
    let tokenStore: TokenStore
    private let defaults: UserDefaults
    private let profileKey = "profile"
    private let issuedKey = "tokenIssuedAt"
    private let expiredKey = "sessionExpired"
    /// Called when a different WeBeep user signs in (the local store must be wiped).
    var onUserChanged: (() -> Void)?

    init(tokenStore: TokenStore = TokenStore(), defaults: UserDefaults = .standard) {
        self.tokenStore = tokenStore
        self.defaults = defaults
    }

    var client: MoodleClient? { token.map { MoodleClient(token: $0) } }

    var user: UserProfile? {
        switch state {
        case .signedIn(let u), .expired(let u): return u
        default: return nil
        }
    }

    var isExpired: Bool { if case .expired = state { return true } else { return false } }

    /// Restores a previous session from Keychain + cached profile.
    func restore() {
        guard let saved = tokenStore.load(), !saved.isEmpty else {
            // Expired session survives relaunch: profile kept, token gone.
            if defaults.bool(forKey: expiredKey), let data = defaults.data(forKey: profileKey),
               let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
                state = .expired(profile)
            } else {
                state = .signedOut
            }
            return
        }
        token = saved
        privateToken = tokenStore.loadPrivateToken()
        tokenIssuedAt = defaults.object(forKey: issuedKey) as? Date
        if let data = defaults.data(forKey: profileKey), let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            state = .signedIn(profile)
        } else {
            state = .loading
            Task { await validateCurrentToken() }
        }
    }

    private func validateCurrentToken() async {
        guard let client else { state = .signedOut; return }
        do {
            let info = try await client.siteInfo()
            apply(token: client.token, privateToken: privateToken, info: info)
        } catch MoodleError.invalidToken {
            signOut()
        } catch {
            state = .signedIn(UserProfile(id: 0, fullname: "", username: "", pictureURL: nil))
        }
    }

    /// Validates a token against WeBeep and, if good, persists it (and the private token when present).
    func signIn(withToken candidate: String, privateToken: String? = nil) async throws {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = try await MoodleClient(token: trimmed).siteInfo()
        try tokenStore.save(trimmed)
        if let privateToken { try tokenStore.savePrivateToken(privateToken) }
        apply(token: trimmed, privateToken: privateToken ?? self.privateToken, info: info)
    }

    /// Silent renewal succeeded: swap tokens without touching the profile.
    func adopt(token newToken: String, privateToken newPrivate: String?) throws {
        try tokenStore.save(newToken)
        if let newPrivate { try tokenStore.savePrivateToken(newPrivate) }
        token = newToken
        if let newPrivate { privateToken = newPrivate }
        tokenIssuedAt = .now
        defaults.set(tokenIssuedAt, forKey: issuedKey)
        defaults.removeObject(forKey: expiredKey)
        if case .expired(let u) = state { state = .signedIn(u) }
    }

    private func apply(token: String, privateToken: String?, info: SiteInfoDTO) {
        let previousID = user?.id
        self.token = token
        self.privateToken = privateToken
        tokenIssuedAt = .now
        defaults.set(tokenIssuedAt, forKey: issuedKey)
        let profile = UserProfile(id: info.userid, fullname: info.fullname, username: info.username,
                                  pictureURL: info.userpictureurl.flatMap(URL.init(string:)))
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: profileKey) }
        defaults.removeObject(forKey: expiredKey)
        if let previousID, previousID != 0, previousID != info.userid { onUserChanged?() }
        state = .signedIn(profile)
    }

    /// WeBeep said `invalidtoken`: keep the data, ask for a new login.
    func markExpired() {
        guard let user, user.id != 0 else { signOut(); return }
        token = nil
        tokenStore.clear()
        defaults.set(true, forKey: expiredKey)
        state = .expired(user)
    }

    /// Demo launches: fake signed-in user, no network.
    func enterDemo() {
        token = "demo"
        state = .signedIn(UserProfile(id: 1, fullname: "Mario Rossi", username: "10812345@polimi.it", pictureURL: nil))
    }

    func signOut() {
        if defaults.bool(forKey: DemoData.flagKey) {
            defaults.removeObject(forKey: DemoData.flagKey)
            onUserChanged?()
        }
        tokenStore.clear()
        defaults.removeObject(forKey: profileKey)
        defaults.removeObject(forKey: issuedKey)
        defaults.removeObject(forKey: expiredKey)
        defaults.removeObject(forKey: "onboarding.done")
        defaults.removeObject(forKey: "lastSyncAt")
        token = nil
        privateToken = nil
        tokenIssuedAt = nil
        state = .signedOut
    }
}
