import Testing
@testable import Beep

struct NotificationHTMLTests {
    /// Old table template.
    let table = """
    <p><font face="sans-serif"><a href="https://webeep.polimi.it/course/view.php?id=1">Ingegneria Informatica</a> » <a href="#">Forum</a> » <a href="#">Annunci</a> » <a href="#">Buon inizio</a></font></p>
    <table border="0" cellpadding="3" cellspacing="0" class="forumpost">
    <tr><td class="picture left"><img src="x"></td>
    <td class="topic starter"><div class="subject">Buon inizio anno</div><div class="author">di <a href="#">Lisa Wium</a> - mercoledì, 16 settembre 2026, 11:38</div></td></tr>
    <tr><td class="left side">&nbsp;</td><td class="content">
    <p>Ciao a tutti,</p><p>benvenuti!</p>
    </td></tr></table>
    <hr /><p><a href="https://webeep.polimi.it/mod/forum/discuss.php?d=1">Vedi il post nel contesto</a> | <a href="#">Disiscriviti</a></p>
    """

    /// Moodle 4.x e-mail template, as WeBeep sends it in October 2026 (abridged).
    let email = """
    <div style="background-color: #F3F3F3; width: 100%; height: 100%">
        <div class="navbar" style="width: 90%; font-size: 12px;">
            <a target="_blank" href="https://webeep.polimi.it/course/view.php?id=2588" style="color: #8e8e8e;">Ingegneria Informatica</a>
            &raquo;
            <a target="_blank" href="https://webeep.polimi.it/mod/forum/index.php?id=2588">Forum</a>
            &raquo;
            <a target="_blank" href="https://webeep.polimi.it/mod/forum/discuss.php?d=199974">Linux Day al Politecnico - Associazione POuL</a>
        </div>
        <div style="padding: 0 0 15px 0;">
            <style>@media only screen { body { margin: 0; } .content img { max-width: 100%; } }</style>
            <div style="width: 90%; background-color: #fff;">
                <div class="forum-post" style="background-color: #fff;">
                    <div class="header">
                        <div class="topic starter">
                            <div class="picture left" style="margin-bottom: 20px;">
                            <a href="https://webeep.polimi.it/user/view.php?id=409&amp;course=2588" class="d-inline-block aabtn"><span class="userinitials size-35" title="Marco Brambilla" aria-label="Marco Brambilla" role="img">MB</span></a>
                            </div>
                            <div class="subject" style="font-size: 24px; font-weight: bold;">
                                Linux Day al Politecnico - Associazione POuL
                            </div>
                            <div class="author" style="color: #919191">
                                di <a target='_blank' href='https://webeep.polimi.it/user/view.php?id=409&course=2588'>Marco Brambilla</a> - sabato, 17 ottobre 2026, 11:14
                            </div>
                        </div>
                    </div>
                    <div>
                        <div class="left side" valign="top">&nbsp;</div>
                        <div class="content" style="margin-top: 20px; margin-bottom: 20px;">
                            <div style="margin-top: 20px; font-size: 16px; line-height: 1.6"><p>Anche questo anno torna il Linux Day il<strong> 24 Ottobre!</strong></p>
    <p>Qui la programmazione: <a href="https://linuxdaymilano.org/schedule/#calendar">https://linuxdaymilano.org/schedule/#calendar</a></p></div>
                            <div class="commands" style="margin-top: 10px; display: inline-flex;">
                            </div>
                            <div class="link">
                                <a target="_blank" href="https://webeep.polimi.it/mod/forum/discuss.php?d=199974#p226495" style="background-color: #007AFF;">
                                    Visualizza questo intervento nel contesto
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="unsubscribelink" style="width: 100%; text-align: center;">
                <a href="https://webeep.polimi.it/mod/forum/index.php?id=2588">Modifica preferenze e-mail di riepilogo</a>
            </div>
        </div>
    </div>
    """

    @Test func tableTemplateKeepsOnlyPostBody() {
        let out = NotificationHTML.cleaned(table)
        #expect(out.contains("benvenuti!"))
        #expect(!out.contains("»"))
        #expect(!out.contains("Disiscriviti"))
        #expect(!out.contains("Lisa Wium"))
        #expect(NotificationHTML.author(table) == "Lisa Wium")
        #expect(NotificationHTML.courseID(table) == 1)
    }

    @Test func emailTemplateKeepsOnlyPostBody() {
        let p = NotificationHTML.parse(email)
        #expect(p.body.hasPrefix("<div style=\"margin-top: 20px; font-size: 16px; line-height: 1.6\"><p>Anche questo anno"))
        #expect(p.body.contains("linuxdaymilano.org"))
        #expect(!p.body.contains("&raquo;"))
        #expect(!p.body.contains("MB"))
        #expect(!p.body.contains("Marco Brambilla"))
        #expect(!p.body.contains("Visualizza questo intervento"))
        #expect(!p.body.contains("Modifica preferenze"))
        #expect(!p.body.contains("class=\"commands\""))
        #expect(p.author == "Marco Brambilla")
        #expect(p.courseID == 2588)
    }

    @Test func fallbackStripsBreadcrumbAndFooter() {
        let html = "<p>A » B » C</p><div>Body text</div><hr/><p><a>Disiscriviti</a></p>"
        #expect(NotificationHTML.cleaned(html) == "<div>Body text</div>")
        let raquo = "<div class=\"navbar\"><a>A</a> &raquo; <a>B</a></div><p>Body</p>"
        #expect(NotificationHTML.cleaned(raquo) == "<p>Body</p>")
    }

    /// "New content in course X" notifications: keep the text, drop the preferences line.
    @Test func newContentNotificationDropsPreferencesLine() {
        let html = """
        <p>Nel corso <a href="https://webeep.polimi.it/course/view.php?id=24390">052537 - TECHNOLOGIES FOR INFORMATION SYSTEMS (TANCA LETIZIA) [2026-27]</a> è stata creata la seguente attività o risorsa:</p>
        <p>File <a href="https://webeep.polimi.it/mod/resource/view.php?id=499508">Course Schedule Updated on October 9. Classroom Change</a></p>
        <p><a href="https://webeep.polimi.it/message/notificationpreferences.php?userid=4948">Modifica preferenze di notifica</a></p>
        """
        let p = NotificationHTML.parse(html)
        #expect(p.body.contains("Course Schedule Updated"))
        #expect(!p.body.contains("Modifica preferenze"))
        #expect(p.author == nil)
        #expect(p.courseID == 24390)
    }

    @Test func plainHTMLUntouched() {
        #expect(NotificationHTML.cleaned("<p>Hello</p>") == "<p>Hello</p>")
        #expect(NotificationHTML.parse("<p>Hello</p>") == .init(body: "<p>Hello</p>", author: nil, courseID: nil))
    }
}
