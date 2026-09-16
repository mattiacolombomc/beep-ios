import Testing
@testable import Beep

struct MultilangTests {
    let text = "{mlang it}Materiali{mlang}{mlang en}Materials{mlang}"

    @Test func picksRequestedLanguage() {
        #expect(Multilang.resolve(text, language: "it") == "Materiali")
        #expect(Multilang.resolve(text, language: "en-US") == "Materials")
    }

    @Test func fallsBackToEnglishThenFirst() {
        #expect(Multilang.resolve(text, language: "de") == "Materials")
        #expect(Multilang.resolve("{mlang it}Solo italiano{mlang}", language: "en") == "Solo italiano")
    }

    @Test func plainTextUntouched() {
        #expect(Multilang.resolve("Bacheca", language: "en") == "Bacheca")
    }
}
