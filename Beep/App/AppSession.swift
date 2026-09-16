import Foundation
import Observation

/// Authentication state shared through the environment.
@Observable
final class AppSession {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(UserProfile)
    }

    struct UserProfile: Equatable, Codable {
        var id: Int
        var fullname: String
        var username: String
        var pictureURL: URL?
    }

    private(set) var state: State = .loading
    private(set) var token: String?
    let tokenStore: TokenStore
    private let defaults: UserDefaults
    private let profileKey = "profile"

    init(tokenStore: TokenStore = TokenStore(), defaults: UserDefaults = .standard) {
        self.tokenStore = tokenStore
        self.defaults = defaults
    }

    var client: MoodleClient? { token.map { MoodleClient(token: $0) } }

    var user: UserProfile? {
        if case .signedIn(let u) = state { return u }
        return nil
    }

    /// Restores a previous session from Keychain + cached profile.
    func restore() {
        guard let saved = tokenStore.load(), !saved.isEmpty else { state = .signedOut; return }
        token = saved
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
            signIn(token: client.token, info: info)
        } catch MoodleError.invalidToken {
            signOut()
        } catch {
            // Offline: keep whatever we have, the UI will show a placeholder.
            state = .signedIn(UserProfile(id: 0, fullname: "", username: "", pictureURL: nil))
        }
    }

    /// Validates a token against WeBeep and, if good, persists it.
    func signIn(withToken candidate: String) async throws {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = try await MoodleClient(token: trimmed).siteInfo()
        try tokenStore.save(trimmed)
        signIn(token: trimmed, info: info)
    }

    private func signIn(token: String, info: SiteInfoDTO) {
        self.token = token
        let profile = UserProfile(id: info.userid, fullname: info.fullname, username: info.username,
                                  pictureURL: info.userpictureurl.flatMap(URL.init(string:)))
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: profileKey) }
        state = .signedIn(profile)
    }

    /// Demo launches: fake signed-in user, no network.
    func enterDemo() {
        token = "demo"
        state = .signedIn(UserProfile(id: 1, fullname: "Mario Rossi", username: "10812345@polimi.it", pictureURL: nil))
    }

    func signOut() {
        tokenStore.clear()
        defaults.removeObject(forKey: profileKey)
        token = nil
        state = .signedOut
    }
}
