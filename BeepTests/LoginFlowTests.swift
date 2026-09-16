import CryptoKit
import Foundation
import Testing
@testable import Beep

struct LoginFlowTests {
    @Test func launchURLCarriesServiceAndPassport() throws {
        let url = LoginFlow.launchURL(passport: "123.456")
        let q = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(url.path() == "/admin/tool/mobile/launch.php")
        #expect(q["service"] == "moodle_mobile_app")
        #expect(q["passport"] == "123.456")
    }

    @Test func parsesCallbackAndValidatesSignature() throws {
        let passport = "42.0"
        let sig = Insecure.MD5.hash(data: Data(("https://webeep.polimi.it" + passport).utf8)).map { String(format: "%02x", $0) }.joined()
        let payload = Data("\(sig):::abcdef0123456789:::priv".utf8).base64EncodedString()
        let url = URL(string: "moodlemobile://token=\(payload)")!
        let creds = try #require(LoginFlow.parseCallback(url, passport: passport))
        #expect(creds.token == "abcdef0123456789")
        #expect(creds.privateToken == "priv")
        #expect(creds.signatureValid)
    }

    @Test func wrongSignatureStillYieldsTokenButFlagged() throws {
        let payload = Data("nope:::tok".utf8).base64EncodedString()
        let creds = try #require(LoginFlow.parseCallback(URL(string: "moodlemobile://token=\(payload)")!, passport: "1"))
        #expect(creds.token == "tok")
        #expect(creds.privateToken == nil)
        #expect(!creds.signatureValid)
    }

    @Test func rejectsOtherSchemes() {
        #expect(LoginFlow.parseCallback(URL(string: "https://webeep.polimi.it/my/")!, passport: "1") == nil)
    }
}
