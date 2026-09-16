import Foundation
import WebKit

/// Runs a short scripted task inside a hidden, autologin-authenticated WeBeep web session.
/// Used for actions Moodle exposes only on the website (self-unenrolment).
@MainActor
final class WebSession: NSObject, WKNavigationDelegate {
    struct Timeout: Error {}
    struct Failed: Error, CustomStringConvertible { let reason: String; var description: String { reason } }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?
    private var onPage: ((WKWebView, URL) async -> Bool)?   // return true when done

    /// Builds the autologin URL that lands on `target` with a live web session.
    static func autologinURL(session: AppSession, target: URL) async throws -> URL {
        guard let client = session.client, let user = session.user, user.id != 0 else { throw Failed(reason: "not signed in") }
        guard let privateToken = session.privateToken else { throw Failed(reason: "sign in again once to enable web actions") }
        let auto = try await client.autologinKey(privateToken: privateToken)
        guard var comps = URLComponents(string: auto.autologinurl) else { throw Failed(reason: "bad autologin url") }
        comps.queryItems = [
            URLQueryItem(name: "userid", value: String(user.id)),
            URLQueryItem(name: "key", value: auto.key),
            URLQueryItem(name: "urltogo", value: target.absoluteString),
        ]
        guard let url = comps.url else { throw Failed(reason: "bad autologin url") }
        return url
    }

    /// Loads `url`; after every page load calls `onPage`, finishing when it returns true.
    func run(url: URL, timeout: TimeInterval = 40, onPage: @escaping (WKWebView, URL) async -> Bool) async throws {
        self.onPage = onPage
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 " + URLSessionTransport.userAgent
        wv.navigationDelegate = self
        webView = wv
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            self?.finish(.failure(Timeout()))
        }
        defer { watchdog.cancel() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            wv.load(URLRequest(url: url))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        webView?.stopLoading()
        webView = nil
        c.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, let onPage else { return }
        Task { @MainActor in
            if url.path().contains("/login/") { finish(.failure(Failed(reason: "autologin rejected, landed on \(url.path())"))); return }
            if await onPage(webView, url) { finish(.success(())) }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { finish(.failure(error)) }
    }
}

/// Self-unenrolment through WeBeep's website (Moodle has no web-service call for it).
enum Unenroller {
    @MainActor
    static func unenrol(course: Course, session: AppSession) async throws {
        guard let client = session.client else { throw WebSession.Failed(reason: "not signed in") }
        let methods = try await client.enrolmentMethods(courseID: course.id)
        guard let selfEnrol = methods.first(where: { $0.type == "self" }) else {
            throw WebSession.Failed(reason: String(localized: "This course has no self-enrolment, so you cannot leave it from here. Ask the professor or WeBeep support."))
        }
        let target = WeBeep.host.appending(path: "enrol/self/unenrolself.php").appending(queryItems: [URLQueryItem(name: "enrolid", value: String(selfEnrol.id))])
        let url = try await WebSession.autologinURL(session: session, target: target)
        let web = WebSession()
        var submitted = false
        try await web.run(url: url) { webView, pageURL in
            if pageURL.path().contains("unenrolself.php") && !submitted {
                // Confirm page: submit the form that carries confirm=1.
                let js = """
                (() => {
                  const forms = Array.from(document.querySelectorAll('form'));
                  const f = forms.find(x => x.querySelector('input[name="confirm"]') && (x.action || '').includes('unenrolself'));
                  if (f) { f.submit(); return 'submitted'; }
                  return 'noform:' + document.title;
                })()
                """
                let result = try? await webView.evaluateJavaScript(js) as? String
                if result == "submitted" { submitted = true; return false }
                return false
            }
            // Any page after the submission means Moodle processed it (course index, dashboard…).
            return submitted
        }
        // Verify against the API.
        if let user = session.user {
            let courses = try await client.userCourses(userID: user.id)
            if courses.contains(where: { $0.id == course.id }) {
                throw WebSession.Failed(reason: String(localized: "WeBeep still lists this course. Try again in a minute."))
            }
        }
    }
}
