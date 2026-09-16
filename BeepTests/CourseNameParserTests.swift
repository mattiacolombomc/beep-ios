import Testing
@testable import Beep

struct CourseNameParserTests {
    @Test func standardWebeepTitle() {
        let t = CourseNameParser.parse("054443 - SOFTWARE ENGINEERING 2 (CAMILLI MATTEO, DI NITTO ELISABETTA, ROSSI MATTEO GIOVANNI)")
        #expect(t.code == "054443")
        #expect(t.name == "Software Engineering 2")
        #expect(t.professors == "Camilli Matteo, Di Nitto Elisabetta, Rossi Matteo Giovanni")
    }

    @Test func codesInsideParenthesesAndYearTag() {
        let t = CourseNameParser.parse("ARTIFICIAL NEURAL NETWORKS AND DEEP LEARNING (054307 +056869 BORACCHI-MATTEUCCI) [2026-27]")
        #expect(t.name == "Artificial Neural Networks and Deep Learning")
        #expect(t.code == "054307")
        #expect(t.professors == "Boracchi-Matteucci")
    }

    @Test func professorWithBracketId() {
        let t = CourseNameParser.parse("088983 - FOUNDATIONS OF OPERATIONS RESEARCH (MALUCELLI FEDERICO [123456])")
        #expect(t.code == "088983")
        #expect(t.name == "Foundations of Operations Research")
        #expect(t.professors == "Malucelli Federico")
    }

    @Test func multilangTitle() {
        let t = CourseNameParser.parse("{mlang it}Ingegneria Informatica{mlang}{mlang en}Computer Engineering{mlang}", language: "it")
        #expect(t.name == "Ingegneria Informatica")
        #expect(t.code == nil)
        #expect(t.professors == nil)
    }

    @Test func catalogueBracesAndRomanOne() {
        let t = CourseNameParser.parse("GEOMETRIA (IELLA PAOLO) {095730 - ANALISI MATEMATICA 1 E GEOMETRIA [SEZIONE A]}")
        #expect(t.name == "Geometria")
        #expect(t.professors == "Iella Paolo")
        #expect(CourseNameParser.titleCased("ANALISI MATEMATICA I E GEOMETRIA") == "Analisi Matematica I e Geometria")
    }

    @Test func plainNameIsKept() {
        let t = CourseNameParser.parse("Ingegneria Informatica")
        #expect(t.name == "Ingegneria Informatica")
    }

    @Test func titleCaseKeepsAcronymsAndNumerals() {
        #expect(CourseNameParser.titleCased("ANALISI MATEMATICA II") == "Analisi Matematica II")
        #expect(CourseNameParser.titleCased("SIGNALS FOR AI AND ML") == "Signals for AI and ML")
        #expect(CourseNameParser.titleCased("Data Bases 2") == "Data Bases 2")
        #expect(CourseNameParser.titleCased("COMPUTER SECURITY - UIC 587") == "Computer Security - UIC 587")
        #expect(CourseNameParser.titleCased("FOUNDATIONS OF OPERATIONS RESEARCH") == "Foundations of Operations Research")
    }
}
