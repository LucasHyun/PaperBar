import Foundation

/// 여러 곳에서 동시에 불러도 요청 사이 간격을 보장 (arXiv 가이드라인: 3초)
actor RequestPacer {
    private var nextSlot = Date.distantPast
    private let interval: TimeInterval

    init(interval: TimeInterval) { self.interval = interval }

    func waitTurn() async {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(interval)   // 기다리기 전에 자리를 먼저 예약
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }
}

/// arXiv 공개 API (키 불필요)
///  - 키워드별 최신 제출 논문: HF 는 커뮤니티가 올린 화제작 위주라 커버리지를 보완
///  - id_list 로 여러 논문 메타데이터(초록 포함) 한 번에: Hacker News 링크 보강용
enum ArxivClient {
    private static let pacer = RequestPacer(interval: 3.1)

    static func latest(matching query: SearchQuery, maxResults: Int = 30) async throws -> [Paper] {
        guard let searchQuery = query.arxivQuery else { return [] }
        return try await request([
            URLQueryItem(name: "search_query", value: searchQuery),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending"),
            URLQueryItem(name: "max_results", value: String(maxResults)),
        ])
    }

    static func papers(ids: [String]) async throws -> [Paper] {
        guard !ids.isEmpty else { return [] }
        return try await request([
            URLQueryItem(name: "id_list", value: ids.joined(separator: ",")),
            URLQueryItem(name: "max_results", value: String(ids.count)),
        ])
    }

    private static func request(_ items: [URLQueryItem]) async throws -> [Paper] {
        var c = URLComponents(string: "https://export.arxiv.org/api/query")!
        c.queryItems = items
        await pacer.waitTurn()
        let data = try await HTTP.get(c.url!)
        return ArxivAtomParser.parse(data)
    }
}

final class ArxivAtomParser: NSObject, XMLParserDelegate {
    private var papers: [Paper] = []
    private var inEntry = false
    private var inAuthor = false
    private var fields: [String: String] = [:]
    private var authors: [String] = []
    private var categories: [String] = []
    private var buffer = ""

    static func parse(_ data: Data) -> [Paper] {
        let delegate = ArxivAtomParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.papers.uniqued()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        buffer = ""
        switch elementName {
        case "entry":
            inEntry = true
            fields = [:]
            authors = []
            categories = []
        case "author":
            inAuthor = true
        case "category":
            if inEntry, let term = attributeDict["term"] { categories.append(term) }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard inEntry else { return }
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "id", "title", "summary", "published":
            fields[elementName] = text
        case "name" where inAuthor:
            authors.append(text)
        case "author":
            inAuthor = false
        case "entry":
            inEntry = false
            // 에러 응답의 entry 는 id 에 /abs/ 가 없어서 자연스럽게 걸러짐
            guard let raw = fields["id"], let id = Self.arxivID(from: raw) else { return }
            papers.append(Paper(
                id: id,
                title: collapseWhitespace(fields["title"] ?? L10n.current.untitled),
                summary: collapseWhitespace(fields["summary"] ?? ""),
                authors: authors,
                publishedAt: DateParser.parse(fields["published"]),
                upvotes: nil,
                numComments: nil,
                githubRepo: nil,
                githubStars: nil,
                aiSummary: nil,
                keywords: categories,
                source: .arxiv
            ))
        default:
            break
        }
    }

    /// "http://arxiv.org/abs/2410.12345v2" → "2410.12345"
    /// "http://arxiv.org/abs/hep-th/9901001v1" → "hep-th/9901001"
    static func arxivID(from raw: String) -> String? {
        guard let range = raw.range(of: "/abs/") else { return nil }
        var id = String(raw[range.upperBound...])
        if let version = id.range(of: #"v\d+$"#, options: .regularExpression) {
            id.removeSubrange(version)
        }
        return id.isEmpty ? nil : id
    }
}
