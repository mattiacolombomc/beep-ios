import Testing
@testable import Beep

struct FileURLTokenizerTests {
    let token = "abc123"

    @Test func plainPluginfileGetsQuestionMark() {
        let url = "https://webeep.polimi.it/webservice/pluginfile.php/1/mod_resource/content/2/slides.pdf"
        #expect(FileURLTokenizer.tokenized(url, type: "file", token: token) == url + "?token=abc123")
    }

    @Test func forcedownloadGetsAmpersand() {
        let url = "https://webeep.polimi.it/webservice/pluginfile.php/1/mod_folder/content/0/a.zip?forcedownload=1"
        #expect(FileURLTokenizer.tokenized(url, type: "file", token: token) == url + "&token=abc123")
    }

    @Test func otherQueryStringStillGetsToken() {
        let url = "https://webeep.polimi.it/webservice/pluginfile.php/1/x/y.pdf?rev=3"
        #expect(FileURLTokenizer.tokenized(url, type: "file", token: token) == url + "&token=abc123")
    }

    @Test func nonFileUntouched() {
        let url = "https://example.com/video"
        #expect(FileURLTokenizer.tokenized(url, type: "url", token: token) == url)
    }

    @Test func keyStripsToken() {
        #expect(FileURLTokenizer.key("https://h/p.pdf?token=abc") == "https://h/p.pdf")
        #expect(FileURLTokenizer.key("https://h/p.pdf?forcedownload=1&token=abc") == "https://h/p.pdf?forcedownload=1")
        #expect(FileURLTokenizer.key("https://h/p.pdf") == "https://h/p.pdf")
    }
}
