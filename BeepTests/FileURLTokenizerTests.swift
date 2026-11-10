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

    /// Moodle bumps the revision segment of every file in a folder whenever the folder is edited:
    /// the key must not move with it, or unchanged files look deleted and new.
    @Test func keyIgnoresTheRevisionOfFoldersResourcesAndPages() {
        let base = "https://webeep.polimi.it/webservice/pluginfile.php"
        #expect(FileURLTokenizer.key("\(base)/1627154/mod_folder/content/19/Old%20recordings/a.mp4?forcedownload=1&token=T")
                == FileURLTokenizer.key("\(base)/1627154/mod_folder/content/20/Old%20recordings/a.mp4?forcedownload=1&token=T"))
        #expect(FileURLTokenizer.key("\(base)/1627154/mod_folder/content/20/Old%20recordings/a.mp4?forcedownload=1")
                == "\(base)/1627154/mod_folder/content/0/Old%20recordings/a.mp4?forcedownload=1")
        #expect(FileURLTokenizer.key("\(base)/1040160/mod_resource/content/28/FDA_notes.pdf?forcedownload=1")
                == "\(base)/1040160/mod_resource/content/0/FDA_notes.pdf?forcedownload=1")
        #expect(FileURLTokenizer.key("\(base)/1060758/mod_page/content/7/img.png")
                == "\(base)/1060758/mod_page/content/0/img.png")
    }

    @Test func keyLeavesUnrevisionedURLsAlone() {
        let base = "https://webeep.polimi.it/webservice/pluginfile.php"
        let page = "\(base)/1060758/mod_page/content/index.html?forcedownload=1"
        let book = "\(base)/1034688/mod_book/chapter/815/Dispense.pdf"
        #expect(FileURLTokenizer.key(page) == page)
        #expect(FileURLTokenizer.key(book) == book)
    }

    /// The migration runs the key over stored keys: a second pass must change nothing,
    /// even for a sub-folder whose name is a number.
    @Test func keyIsIdempotent() {
        let url = "https://webeep.polimi.it/webservice/pluginfile.php/9/mod_folder/content/31/2024/exam.pdf?forcedownload=1"
        let once = FileURLTokenizer.key(url)
        #expect(once.contains("/content/0/2024/exam.pdf"))
        #expect(FileURLTokenizer.key(once) == once)
    }
}
