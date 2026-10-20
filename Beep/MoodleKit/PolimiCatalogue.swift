import Foundation

/// The public "Manifesti degli Studi" of Politecnico di Milano: the one place that says in which
/// semester a course is taught (WeBeep does not). One GET per course code and academic year,
/// no login, nothing personal in the request. The answer is an HTML page with uppercase table
/// tags; the "Periodo" column holds "1° sem", "2° sem" or "Annuale".
nonisolated enum PolimiCatalogue {
    static let endpoint = URL(string: "https://onlineservices.polimi.it/manifesti/manifesti/controller/ricerche/RicercaPerInsegnamentoPublic.do")!

    /// Search by course code in the catalogue of the academic year starting in `startYear`.
    static func url(code: String, startYear: Int) -> URL {
        endpoint.appending(queryItems: [
            URLQueryItem(name: "evn_default", value: "evento"),
            URLQueryItem(name: "lang", value: "IT"),
            URLQueryItem(name: "aa", value: String(startYear)),
            URLQueryItem(name: "k_cf", value: "-1"),
            URLQueryItem(name: "sede", value: "ALL_SEDI"),
            URLQueryItem(name: "tipoCorso", value: "ALL_TIPO_CORSO"),
            URLQueryItem(name: "ac_ins", value: "0"),
            URLQueryItem(name: "semestre", value: "ALL_SEMESTRI"),
            URLQueryItem(name: "aree", value: "-1"),
            URLQueryItem(name: "tipoInsegnamento", value: "ALL_TIPO_INSEGNAMENTO"),
            URLQueryItem(name: "insegn_ricerca", value: code),
        ])
    }

    /// Fetches and parses. Nil when the catalogue has no row for the code (manifesto not out
    /// yet, or not a Polimi course); throws on network and server errors.
    static func period(code: String, startYear: Int, transport: any HTTPTransport) async throws -> Semester? {
        let (data, response) = try await transport.get(url(code: code, startYear: startYear))
        guard (200...299).contains(response.statusCode) else { throw MoodleError.http(status: response.statusCode) }
        return period(in: String(decoding: data, as: UTF8.self), code: code)
    }

    /// The "Periodo" column of the rows for `code`, by majority: a course has one row per study
    /// plan that includes it, normally all with the same period. The column is found by its
    /// header, so a reordered table still parses; a page in a new shape yields nil, never a wrong
    /// semester.
    static func period(in html: String, code: String) -> Semester? {
        var periodColumn: Int?
        var votes: [Semester: Int] = [:]
        for row in html.matches(of: /<tr\b[^>]*>(.*?)<\/tr>/.ignoresCase().dotMatchesNewlines()) {
            let cells = Array(row.1.matches(of: /<t([hd])\b[^>]*>(.*?)<\/t[hd]>/.ignoresCase().dotMatchesNewlines()))
            guard !cells.isEmpty else { continue }
            if cells.contains(where: { $0.1.lowercased() == "h" }) {
                periodColumn = cells.firstIndex { text($0.2).caseInsensitiveCompare("Periodo") == .orderedSame }
                continue
            }
            guard let periodColumn, periodColumn < cells.count, cells.contains(where: { text($0.2) == code }) else { continue }
            if let s = semester(text(cells[periodColumn].2)) { votes[s, default: 0] += 1 }
        }
        return votes.sorted { ($0.value, -$0.key.rawValue) > ($1.value, -$1.key.rawValue) }.first?.key
    }

    /// Cell text: tags out, whitespace collapsed.
    private static func text(_ cell: Substring) -> String {
        cell.replacing(/<[^>]+>/, with: " ").replacing("&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func semester(_ cell: String) -> Semester? {
        let t = cell.lowercased()
        if t.contains("annual") { return .annual }
        guard t.contains("sem"), !t.contains("trim") else { return nil }   // trimesters are not semesters
        if t.hasPrefix("1") { return .first }
        if t.hasPrefix("2") { return .second }
        return nil
    }
}
