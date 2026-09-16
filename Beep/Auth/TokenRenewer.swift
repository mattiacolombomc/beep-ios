import Foundation
import Observation
import WebKit

/// Silent token renewal: `tool_mobile_get_autologin_key` (needs the private token) opens a
/// short-lived web session; a hidden web view then runs the usual launch.php handshake
/// and we swap in the fresh token. Only works while the current token is still valid.
@Observable
final class TokenRenewer {
    enum Outcome: Equatable {
        case renewed
        case notNeeded
        case unavailable(String)
        case failed(String)
    }

    static let renewAfter: TimeInterval = 28 * 24 * 3600

    private(set) var lastOutcome: Outcome?
    private(set) var isRunning = false
    private let session: AppSession
    private var hidden: HiddenHandshake?

    init(session: AppSession) { self.session = session }

    var isDue: Bool {
        guard session.privateToken != nil, let issued = session.tokenIssuedAt else { return false }
        return Date.now.timeIntervalSince(issued) > Self.renewAfter
    }

    /// Renews if the token is older than `renewAfter`.
    func renewIfNeeded() async {
        guard isDue else { return }
        _ = await renewNow()
    }

    @discardableResult
    func renewNow() async -> Outcome {
        guard !isRunning else { return lastOutcome ?? .failed("busy") }
        isRunning = true
        defer { isRunning = false }
        let outcome = await perform()
        lastOutcome = outcome
        return outcome
    }

    private func perform() async -> Outcome {
        guard let client = session.client, let user = session.user, user.id != 0 else { return .unavailable("not signed in") }
        guard let privateToken = session.privateToken else { return .unavailable("no private token: sign in again once to enable silent renewal") }
        let autologin: AutologinKeyDTO
        do {
            autologin = try await client.autologinKey(privateToken: privateToken)
        } catch MoodleError.invalidToken {
            session.markExpired()
            return .failed("token already invalid")
        } catch {
            return .failed(String(describing: error))
        }
        let passport = LoginFlow.makePassport()
        let launch = LoginFlow.launchURL(passport: passport)
        guard var comps = URLComponents(string: autologin.autologinurl) else { return .failed("bad autologin url") }
        comps.queryItems = [
            URLQueryItem(name: "userid", value: String(user.id)),
            URLQueryItem(name: "key", value: autologin.key),
            URLQueryItem(name: "urltogo", value: launch.absoluteString),
        ]
        guard let url = comps.url else { return .failed("bad autologin url") }
        let handshake = HiddenHandshake()
        hidden = handshake
        defer { hidden = nil }
        do {
            let creds = try await handshake.run(url: url, passport: passport, timeout: 40)
            // Validate before adopting.
            _ = try await MoodleClient(token: creds.token).siteInfo()
            try session.adopt(token: creds.token, privateToken: creds.privateToken)
            return .renewed
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// Off-screen WKWebView that resolves when the moodlemobile:// callback arrives.
    final class HiddenHandshake: NSObject, WKNavigationDelegate {
        private var webView: WKWebView?
        private var continuation: CheckedContinuation<LoginFlow.Credentials, Error>?
        private var passport = ""

        struct Timeout: Error {}
        struct NoCallback: Error, CustomStringConvertible { let landedOn: String; var description: String { "no token callback; landed on \(landedOn)" } }

        func run(url: URL, passport: String, timeout: TimeInterval) async throws -> LoginFlow.Credentials {
            self.passport = passport
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
            wv.navigationDelegate = self
            wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 " + URLSessionTransport.userAgent
            webView = wv
            let watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finish(.failure(Timeout()))
            }
            defer { watchdog.cancel() }
            return try await withCheckedThrowingContinuation { (c: CheckedContinuation<LoginFlow.Credentials, Error>) in
                self.continuation = c
                wv.load(URLRequest(url: url))
            }
        }

        private func finish(_ result: Result<LoginFlow.Credentials, Error>) {
            guard let c = continuation else { return }
            continuation = nil
            webView?.stopLoading()
            webView = nil
            c.resume(with: result)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            if let creds = LoginFlow.parseCallback(url, passport: passport) {
                finish(.success(creds))
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // If we ended up on a login page the autologin didn't take: give up early.
            if let url = webView.url, url.path().contains("/login/") {
                finish(.failure(NoCallback(landedOn: url.absoluteString)))
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if let url = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL,
               let creds = LoginFlow.parseCallback(url, passport: passport) {
                finish(.success(creds))
            } else if (error as NSError).code != NSURLErrorCancelled {
                finish(.failure(error))
            }
        }
    }
}
