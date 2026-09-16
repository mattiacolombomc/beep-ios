import Testing
@testable import Beep

struct NotificationHTMLTests {
    let moodle = """
    <p><font face="sans-serif"><a href="https://webeep.polimi.it/course/view.php?id=1">Ingegneria Informatica</a> » <a href="#">Forum</a> » <a href="#">Annunci</a> » <a href="#">Buon inizio</a></font></p>
    <table border="0" cellpadding="3" cellspacing="0" class="forumpost">
    <tr><td class="picture left"><img src="x"></td>
    <td class="topic starter"><div class="subject">Buon inizio anno</div><div class="author">di <a href="#">Lisa Wium</a> - mercoledì, 16 settembre 2026, 11:38</div></td></tr>
    <tr><td class="left side">&nbsp;</td><td class="content">
    <p>Ciao a tutti,</p><p>benvenuti!</p>
    </td></tr></table>
    <hr /><p><a href="https://webeep.polimi.it/mod/forum/discuss.php?d=1">Vedi il post nel contesto</a> | <a href="#">Disiscriviti</a></p>
    """

    @Test func keepsOnlyPostBody() {
        let out = NotificationHTML.cleaned(moodle)
        #expect(out.contains("benvenuti!"))
        #expect(!out.contains("»"))
        #expect(!out.contains("Disiscriviti"))
        #expect(!out.contains("Lisa Wium"))
    }

    @Test func fallbackStripsBreadcrumbAndFooter() {
        let html = "<p>A » B » C</p><div>Body text</div><hr/><p><a>Disiscriviti</a></p>"
        let out = NotificationHTML.cleaned(html)
        #expect(out == "<div>Body text</div>")
    }

    @Test func plainHTMLUntouched() {
        #expect(NotificationHTML.cleaned("<p>Hello</p>") == "<p>Hello</p>")
    }
}
