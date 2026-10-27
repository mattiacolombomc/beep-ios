import Testing
@testable import Beep

/// Plain URLs and e-mail addresses in Moodle HTML become links: WebKit's data detectors do
/// that on iOS only, so the Mac showed the NSDS welcome announcement with a dead spreadsheet URL.
struct HTMLLinkifyTests {
    @Test func bareURLBecomesALink() {
        let html = "<p>The schedule is found at</p><p>https://docs.google.com/spreadsheets/d/1Wt_YC/edit?usp=sharing</p>"
        #expect(HTMLDocument.linkified(html) == "<p>The schedule is found at</p><p><a href=\"https://docs.google.com/spreadsheets/d/1Wt_YC/edit?usp=sharing\">https://docs.google.com/spreadsheets/d/1Wt_YC/edit?usp=sharing</a></p>")
    }

    @Test func emailInEscapedAngleBracketsKeepsTheBrackets() {
        let html = "<p>Luca Mottola &lt;luca.mottola@polimi.it&gt; and Alessandro</p>"
        #expect(HTMLDocument.linkified(html) == "<p>Luca Mottola &lt;<a href=\"mailto:luca.mottola@polimi.it\">luca.mottola@polimi.it</a>&gt; and Alessandro</p>")
    }

    @Test func existingLinksAndAttributesAreLeftAlone() {
        let html = "<p><a href=\"https://webeep.polimi.it/course/view.php?id=1\">https://webeep.polimi.it/course/view.php?id=1</a> <img src=\"https://x.it/a.png\" alt=\"see https://y.it\"></p>"
        #expect(HTMLDocument.linkified(html) == html)
    }

    @Test func ampersandEntitiesSurviveInsideTheURL() {
        let html = "<p>See https://example.com/a.php?x=1&amp;y=2 now.</p>"
        #expect(HTMLDocument.linkified(html) == "<p>See <a href=\"https://example.com/a.php?x=1&amp;y=2\">https://example.com/a.php?x=1&amp;y=2</a> now.</p>")
    }

    @Test func wwwWithoutSchemeGetsOne() {
        let html = "<p>www.polimi.it</p>"
        #expect(HTMLDocument.linkified(html) == "<p><a href=\"http://www.polimi.it\">www.polimi.it</a></p>")
    }

    @Test func scriptsStylesAndCommentsAreNotTouched() {
        let html = "<style>a { b: url(https://x.it) }</style><!-- https://c.it --><p>ok</p>"
        #expect(HTMLDocument.linkified(html) == html)
    }
}
