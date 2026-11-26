import Foundation
import Testing
@testable import Beep

struct LoginSiteTests {
    let polimi = URL(string: "https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp?id_servizio=2270")!
    let webeep = URL(string: "https://webeep.polimi.it/my/")!
    let cie = URL(string: "https://idserver.servizicie.interno.gov.it/idp/login/livello2?opId=_abc")!
    let poste = URL(string: "https://posteid.poste.it/jod-login-schema/login.jsp")!

    @Test func recognisesWhoOwnsThePage() {
        #expect(LoginSite.provider(for: polimi) == .polimi)
        #expect(LoginSite.provider(for: webeep) == .polimi)
        #expect(LoginSite.provider(for: cie) == .cie)
        #expect(LoginSite.provider(for: poste) == .other)
    }

    @Test func aLookalikeHostIsNotThePolitecnico() {
        #expect(LoginSite.provider(for: URL(string: "https://notpolimi.it/login")!) == .other)
        #expect(LoginSite.provider(for: URL(string: "https://servizicie.interno.gov.it.example.com/")!) == .other)
        #expect(LoginSite.provider(for: URL(string: "moodlemobile://token=abc")!) == .other)
    }

    @Test func politecnicoPagesAreLeftToTheSystem() {
        #expect(LoginSite.wantsDesktop(polimi, cie: true, spid: true) == nil)
        #expect(LoginSite.wantsDesktop(webeep, cie: false, spid: false) == nil)
    }

    @Test func cieFollowsItsOwnSetting() {
        #expect(LoginSite.wantsDesktop(cie, cie: true, spid: false) == true)
        #expect(LoginSite.wantsDesktop(cie, cie: false, spid: true) == false)
    }

    @Test func everyOtherProviderFollowsTheSpidSetting() {
        #expect(LoginSite.wantsDesktop(poste, cie: true, spid: false) == false)
        #expect(LoginSite.wantsDesktop(poste, cie: false, spid: true) == true)
    }

    @Test func defaultsShowTheCieCodeAndTheSpidApps() {
        let defaults = UserDefaults(suiteName: "LoginSiteTests-\(UUID().uuidString)")!
        #expect(LoginSite.cieDesktop(in: defaults) == true)
        #expect(LoginSite.spidDesktop(in: defaults) == false)
        defaults.set(false, forKey: LoginSite.cieDesktopKey)
        defaults.set(true, forKey: LoginSite.spidDesktopKey)
        #expect(LoginSite.cieDesktop(in: defaults) == false)
        #expect(LoginSite.spidDesktop(in: defaults) == true)
    }
}
