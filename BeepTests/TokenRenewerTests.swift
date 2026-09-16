import Foundation
import Testing
@testable import Beep

struct TokenRenewerTests {
    @Test func autologinKeyURL() throws {
        let client = MoodleClient(token: "T", transport: StubTransport(data: Data(), status: 200))
        let url = client.url(function: "tool_mobile_get_autologin_key", parameters: [("privatetoken", "P")])
        let q = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(q["wsfunction"] == "tool_mobile_get_autologin_key")
        #expect(q["privatetoken"] == "P")
    }

    @Test func decodesAutologinKey() throws {
        let json = Data(#"{"key":"abc","autologinurl":"https://webeep.polimi.it/admin/tool/mobile/autologin.php","warnings":[]}"#.utf8)
        let dto = try MoodleClient.decode(AutologinKeyDTO.self, from: json)
        #expect(dto.key == "abc")
        #expect(dto.autologinurl.hasSuffix("autologin.php"))
    }

    @MainActor @Test func renewalIsDueOnlyAfterFourWeeks() async throws {
        let session = AppSession(tokenStore: TokenStore(service: "test-\(UUID().uuidString)"), defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let renewer = TokenRenewer(session: session)
        #expect(!renewer.isDue)   // not signed in
        let outcome = await renewer.renewNow()
        #expect(outcome == .unavailable("not signed in"))
    }
}
