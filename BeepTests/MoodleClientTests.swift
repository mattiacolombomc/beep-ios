import Foundation
import Testing
@testable import Beep

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}
private final class FixtureAnchor {}

struct StubTransport: HTTPTransport {
    let data: Data
    let status: Int
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct MoodleClientTests {
    @Test func buildsRestURL() throws {
        let client = MoodleClient(token: "T0K", transport: StubTransport(data: Data(), status: 200), language: "it")
        let url = client.url(function: "core_course_get_contents", parameters: [("courseid", "41213")])
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.host == "webeep.polimi.it")
        #expect(comps.path == "/webservice/rest/server.php")
        let q = Dictionary(uniqueKeysWithValues: comps.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(q["moodlewsrestformat"] == "json")
        #expect(q["wstoken"] == "T0K")
        #expect(q["wsfunction"] == "core_course_get_contents")
        #expect(q["courseid"] == "41213")
    }

    @Test func decodesSiteInfo() async throws {
        let client = MoodleClient(token: "t", transport: StubTransport(data: try fixture("site_info"), status: 200))
        let info = try await client.siteInfo()
        #expect(info.userid == 12345)
        #expect(info.fullname == "Mario Rossi")
    }

    @Test func decodesCoursesAndCategories() throws {
        let courses = try MoodleClient.decode([CourseDTO].self, from: try fixture("users_courses"))
        #expect(courses.count == 2)
        #expect(courses[0].isfavourite == true)
        #expect(courses[1].hidden == true)
        let cats = try MoodleClient.decode([CategoryDTO].self, from: try fixture("categories"))
        #expect(cats.map(\.name) == ["2026-27", "CCS", "2025-26"])
    }

    @Test func decodesCourseContents() throws {
        let sections = try MoodleClient.decode([SectionDTO].self, from: try fixture("course_contents"))
        #expect(sections.count == 2)
        let modnames = sections[1].modules.map(\.modname)
        #expect(modnames == ["resource", "folder", "url", "page"])
        let folder = sections[1].modules[1]
        #expect(folder.contents?.count == 2)
        #expect(folder.contents?[1].filepath == "/Solutions/")
        #expect(sections[1].modules[0].contents?.first?.timemodified == 1757900000)
        #expect(sections[0].modules[0].contents == nil)
    }

    @Test func mapsInvalidTokenEnvelope() async throws {
        let client = MoodleClient(token: "bad", transport: StubTransport(data: try fixture("error_invalidtoken"), status: 200))
        await #expect(throws: MoodleError.invalidToken) { try await client.siteInfo() }
    }

    @Test func mapsHTTPFailure() async throws {
        let client = MoodleClient(token: "t", transport: StubTransport(data: Data(), status: 503))
        await #expect(throws: MoodleError.http(status: 503)) { try await client.siteInfo() }
    }
}
