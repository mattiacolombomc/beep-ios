import Foundation

/// Minimal transport abstraction so the client can be tested with canned responses.
protocol HTTPTransport: Sendable {
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse)
    /// Form-encoded POST; Moodle requires it for sensitive parameters (private token).
    func post(_ url: URL, form: [(String, String)]) async throws -> (Data, HTTPURLResponse)
}

extension HTTPTransport {
    func post(_ url: URL, form: [(String, String)]) async throws -> (Data, HTTPURLResponse) {
        try await get(url.appending(queryItems: form.map { URLQueryItem(name: $0.0, value: $0.1) }))
    }
}

struct URLSessionTransport: HTTPTransport {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    /// Moodle gates some functions (autologin key) behind the official app's user agent.
    static let userAgent = "MoodleMobile 4.5.0 (Beep; iOS)"

    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return try await perform(request)
    }

    func post(_ url: URL, form: [(String, String)]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = form.map { URLQueryItem(name: $0.0, value: $0.1) }
        request.httpBody = Data((comps.percentEncodedQuery ?? "").utf8)
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw MoodleError.transport("non-HTTP response") }
            return (data, http)
        } catch let error as MoodleError {
            throw error
        } catch {
            throw MoodleError.transport(error.localizedDescription)
        }
    }
}

/// WeBeep constants. Everything hits `webeep.polimi.it`.
nonisolated enum WeBeep {
    static let host = URL(string: "https://webeep.polimi.it")!
    static let restServer = host.appending(path: "webservice/rest/server.php")
    static let shibbolethLogin = host.appending(path: "auth/shibboleth/index.php")
    static let dashboard = host.appending(path: "my/")
    static let mobileLaunch = host.appending(path: "admin/tool/mobile/launch.php")
    static let service = "moodle_mobile_app"
    static let securityKeysPage = host.appending(path: "user/managetoken.php")
}

/// Stateless Moodle REST client: builds `server.php` GET requests, decodes JSON,
/// maps the Moodle error envelope to `MoodleError`.
struct MoodleClient: Sendable {
    let token: String
    let transport: any HTTPTransport
    let language: String

    init(token: String, transport: any HTTPTransport = URLSessionTransport(), language: String = Locale.current.language.languageCode?.identifier ?? "en") {
        self.token = token
        self.transport = transport
        self.language = language
    }

    func url(function: String, parameters: [(String, String)] = []) -> URL {
        var items = [
            URLQueryItem(name: "moodlewsrestformat", value: "json"),
            URLQueryItem(name: "wstoken", value: token),
            URLQueryItem(name: "wsfunction", value: function),
            URLQueryItem(name: "moodlewssettinglang", value: language),
        ]
        items += parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        return WeBeep.restServer.appending(queryItems: items)
    }

    func call<T: Decodable>(_ function: String, parameters: [(String, String)] = [], post: Bool = false, as type: T.Type) async throws -> T {
        let (data, response) = post
            ? try await transport.post(url(function: function), form: parameters)
            : try await transport.get(url(function: function, parameters: parameters))
        guard (200...299).contains(response.statusCode) else { throw MoodleError.http(status: response.statusCode) }
        // Down for maintenance, WeBeep redirects every call to an HTML page under /error/.
        if response.url?.path().hasPrefix("/error") == true || Self.looksLikeHTML(data) {
            let message = Self.maintenanceMessage(in: String(decoding: data, as: UTF8.self), language: language)
            NotificationCenter.default.post(name: .webeepUnavailable, object: nil, userInfo: message.map { ["message": $0] })
            throw MoodleError.unavailable(message: message)
        }
        let value = try Self.decode(type, from: data)
        NotificationCenter.default.post(name: .webeepAvailable, object: nil)
        return value
    }

    /// JSON never starts with "<"; a web page does.
    static func looksLikeHTML(_ data: Data) -> Bool {
        data.prefix(64).first { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) } == UInt8(ascii: "<")
    }

    /// The sentence WeBeep's maintenance page shows, in `language` ("it" or "en"); nil for any
    /// other web page. Looked up by keyword so a reworded page still has a fair chance.
    static func maintenanceMessage(in html: String, language: String) -> String? {
        let body = html.replacing(/<(script|style)\b.*?<\/\1>/.ignoresCase().dotMatchesNewlines(), with: " ")
        let lines = body.replacing(/<[^>]+>/, with: "\n").split(separator: "\n")
            .map { decodeEntities(String($0)).split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        let keywords = language == "it" ? ["manutenzione", "aggiornamento di sistema", "non è disponibile"] : ["maintenance", "not available", "be right back"]
        return lines.first { line in let l = line.lowercased(); return keywords.contains { l.contains($0) } && !l.contains("/") }
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        for (entity, char) in [("&egrave;", "è"), ("&eacute;", "é"), ("&agrave;", "à"), ("&ugrave;", "ù"), ("&ograve;", "ò"), ("&igrave;", "ì"),
                               ("&#39;", "'"), ("&apos;", "'"), ("&quot;", "\""), ("&nbsp;", " "), ("&amp;", "&")] {
            out = out.replacing(entity, with: char)
        }
        return out
    }
}

extension Notification.Name {
    /// WeBeep answered a web page instead of data (maintenance); `userInfo["message"]` is its text.
    static let webeepUnavailable = Notification.Name("Beep.webeepUnavailable")
    /// A web-service call succeeded again.
    static let webeepAvailable = Notification.Name("Beep.webeepAvailable")
}

// MARK: - Decoding

extension MoodleClient {

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(MoodleErrorEnvelope.self, from: data) {
            if envelope.errorcode == "invalidtoken" { throw MoodleError.invalidToken }
            throw MoodleError.server(code: envelope.errorcode, message: envelope.message ?? envelope.exception)
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw MoodleError.decoding(String(describing: error))
        }
    }
}

// MARK: - Endpoints

extension MoodleClient {
    func siteInfo() async throws -> SiteInfoDTO {
        try await call("core_webservice_get_site_info", as: SiteInfoDTO.self)
    }

    func userCourses(userID: Int) async throws -> [CourseDTO] {
        try await call("core_enrol_get_users_courses", parameters: [("userid", String(userID))], as: [CourseDTO].self)
    }

    func categories() async throws -> [CategoryDTO] {
        try await call("core_course_get_categories", as: [CategoryDTO].self)
    }

    func courseContents(courseID: Int) async throws -> [SectionDTO] {
        try await call("core_course_get_contents", parameters: [("courseid", String(courseID))], as: [SectionDTO].self)
    }

    func popupNotifications(userID: Int) async throws -> PopupNotificationsDTO {
        try await call("message_popup_get_popup_notifications", parameters: [("useridto", String(userID))], as: PopupNotificationsDTO.self)
    }

    func markNotificationRead(id: Int) async throws {
        struct Result: Decodable { let notificationid: Int? }
        _ = try await call("core_message_mark_notification_read", parameters: [("notificationid", String(id))], as: Result.self)
    }

    func forumDiscussions(forumID: Int) async throws -> ForumDiscussionsDTO {
        try await call("mod_forum_get_forum_discussions", parameters: [("forumid", String(forumID)), ("sortorder", "1")], as: ForumDiscussionsDTO.self)
    }

    func searchCatalog(_ query: String, page: Int = 0, perPage: Int = 30) async throws -> CatalogSearchDTO {
        try await call("core_course_search_courses",
                       parameters: [("criterianame", "search"), ("criteriavalue", query), ("page", String(page)), ("perpage", String(perPage))],
                       as: CatalogSearchDTO.self)
    }

    func enrolmentMethods(courseID: Int) async throws -> [EnrolmentMethodDTO] {
        try await call("core_enrol_get_course_enrolment_methods", parameters: [("courseid", String(courseID))], as: [EnrolmentMethodDTO].self)
    }

    /// Self-enrolment without a key. Courses with an enrolment key are refused by Moodle.
    func enrolSelf(courseID: Int) async throws -> EnrolResultDTO {
        try await call("enrol_self_enrol_user", parameters: [("courseid", String(courseID))], post: true, as: EnrolResultDTO.self)
    }

    /// Requires the private token from the mobile launch handshake. Rate limited by Moodle (once per 6 minutes).
    func autologinKey(privateToken: String) async throws -> AutologinKeyDTO {
        try await call("tool_mobile_get_autologin_key", parameters: [("privatetoken", privateToken)], post: true, as: AutologinKeyDTO.self)
    }

    func discussionPosts(discussionID: Int) async throws -> DiscussionPostsDTO {
        try await call("mod_forum_get_discussion_posts", parameters: [("discussionid", String(discussionID))], as: DiscussionPostsDTO.self)
    }
}
