import Foundation
import SwiftUI

/// 검색어 문법
///   공백        AND        →  agent memory
///   "따옴표"     구문        →  "world model"  (공백·하이픈 모두 허용: world-model 도 매치)
///   -단어        제외        →  diffusion -medical   /  -"protein folding"
///
/// 매칭은 제목 + 초록 + AI 요약 + 키워드 + 저자 전체에서, "단어의 시작" 기준으로 대소문자 무시.
///   → "agent" 는 agents/agentic 과 매치되지만, "rl" 은 world/url 안의 rl 과는 매치되지 않음.
struct SearchQuery {
    let includes: [String]
    let excludes: [String]
    private let includeRegexes: [NSRegularExpression]
    private let excludeRegexes: [NSRegularExpression]

    init(_ raw: String) {
        var inc: [String] = []
        var exc: [String] = []
        for token in Self.tokenize(raw) {
            if token.hasPrefix("-"), token.count > 1 {
                exc.append(String(token.dropFirst()))
            } else {
                inc.append(token)
            }
        }
        includes = inc
        excludes = exc
        includeRegexes = inc.compactMap(Self.regex(for:))
        excludeRegexes = exc.compactMap(Self.regex(for:))
    }

    var isEmpty: Bool { includes.isEmpty && excludes.isEmpty }

    /// Hugging Face 검색에 넘길 평문 (제외어는 받은 뒤 로컬에서 거름)
    var plainText: String { includes.joined(separator: " ") }

    /// arXiv search_query 문법으로 변환. 포함어가 없으면 nil.
    var arxivQuery: String? {
        guard !includes.isEmpty else { return nil }
        func field(_ term: String) -> String { term.contains(" ") ? "all:\"\(term)\"" : "all:\(term)" }
        var q = includes.map(field).joined(separator: " AND ")
        for term in excludes { q += " ANDNOT " + field(term) }
        return q
    }

    /// Semantic Scholar bulk search 문법 (공백 = AND, "구문", -제외). 포함어가 없으면 nil.
    var semanticScholarQuery: String? {
        guard !includes.isEmpty else { return nil }
        func quoted(_ term: String) -> String { term.contains(" ") ? "\"\(term)\"" : term }
        return (includes.map(quoted) + excludes.map { "-" + quoted($0) }).joined(separator: " ")
    }

    // MARK: 매칭

    func matches(_ paper: Paper) -> Bool {
        let text = paper.searchableText
        let range = NSRange(text.startIndex..., in: text)
        for re in includeRegexes where re.firstMatch(in: text, range: range) == nil { return false }
        for re in excludeRegexes where re.firstMatch(in: text, range: range) != nil { return false }
        return true
    }

    // MARK: 하이라이트

    /// 일치하는 부분을 굵게 + 형광펜
    func highlighted(_ text: String) -> AttributedString {
        Self.build(text, matchRanges(in: text))
    }

    /// 초록에서 처음 일치하는 곳 주변만 잘라서 하이라이트. 초록에 일치가 없으면 nil.
    func snippet(from text: String, length: Int = 220) -> AttributedString? {
        guard let first = matchRanges(in: text).first else { return nil }

        var start = text.index(first.lowerBound, offsetBy: -70, limitedBy: text.startIndex) ?? text.startIndex
        if start != text.startIndex,
           let space = text[start..<first.lowerBound].firstIndex(where: \.isWhitespace) {
            start = text.index(after: space)   // 단어 중간에서 시작하지 않도록
        }
        let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex

        var result = AttributedString(start == text.startIndex ? "" : "…")
        result += highlighted(String(text[start..<end]))
        if end != text.endIndex { result += AttributedString("…") }
        return result
    }

    private func matchRanges(in text: String) -> [Range<String.Index>] {
        let whole = NSRange(text.startIndex..., in: text)
        var ranges: [Range<String.Index>] = []
        for re in includeRegexes {
            for match in re.matches(in: text, range: whole) {
                if let r = Range(match.range, in: text) { ranges.append(r) }
            }
        }
        // 정렬 후 겹치는 구간 병합
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for r in ranges {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    private static func build(_ text: String, _ ranges: [Range<String.Index>]) -> AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        for r in ranges where r.lowerBound >= cursor {
            if cursor < r.lowerBound { out += AttributedString(String(text[cursor..<r.lowerBound])) }
            var mark = AttributedString(String(text[r]))
            mark.inlinePresentationIntent = .stronglyEmphasized
            mark.backgroundColor = Color.yellow.opacity(0.35)
            out += mark
            cursor = r.upperBound
        }
        if cursor < text.endIndex { out += AttributedString(String(text[cursor...])) }
        return out
    }

    // MARK: 파싱

    private static func regex(for term: String) -> NSRegularExpression? {
        let words = term.split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty else { return nil }
        // 앞이 글자/숫자가 아닌 곳에서 시작 + 구문 안의 공백은 공백·하이픈 아무거나.
        // 한중일 문자는 띄어쓰기 없이 붙어 쓰이므로 단어 경계를 요구하지 않음.
        let isCJK = term.range(of: "[\\p{Han}\\p{Hangul}\\p{Hiragana}\\p{Katakana}]", options: .regularExpression) != nil
        let boundary = isCJK ? "" : "(?<![\\p{L}\\p{N}])"
        let pattern = boundary + words.joined(separator: "[\\s\\-]+")
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func tokenize(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false
        let quotes: Set<Character> = ["\"", "“", "”"]

        for ch in raw {
            if quotes.contains(ch) {
                if inQuote {
                    tokens.append(current)
                    current = ""
                    inQuote = false
                } else {
                    // -"구문" 은 제외 구문으로 유지
                    if current != "-" {
                        tokens.append(current)
                        current = ""
                    }
                    inQuote = true
                }
            } else if ch.isWhitespace && !inQuote {
                tokens.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        tokens.append(current)

        return tokens
            .map { collapseWhitespace($0) }
            .filter { !$0.isEmpty && $0 != "-" }
    }
}
