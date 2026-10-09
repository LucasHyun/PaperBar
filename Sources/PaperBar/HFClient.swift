import Foundation

/// Hugging Face Papers 공개 JSON API (키 불필요)
///  - 트렌딩: GET /api/daily_papers?sort=trending&limit=N
///  - 검색:   GET /api/papers/search?q=...&limit=N
enum HFClient {
    private static let base = "https://huggingface.co/api"

    static func trending(limit: Int = 50) async throws -> [Paper] {
        var c = URLComponents(string: "\(base)/daily_papers")!
        c.queryItems = [
            URLQueryItem(name: "sort", value: "trending"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await fetch(c.url!)
    }

    static func search(_ query: String, limit: Int = 30) async throws -> [Paper] {
        var c = URLComponents(string: "\(base)/papers/search")!
        c.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await fetch(c.url!)
    }

    private static func fetch(_ url: URL) async throws -> [Paper] {
        let data = try await HTTP.get(url)
        // 항목 하나가 깨져도 나머지는 살리도록 Lossy 로 디코딩
        let entries = try JSONDecoder().decode([Lossy<HFEntry>].self, from: data)
        return entries.compactMap { $0.value?.paper }.uniqued()
    }
}

// MARK: - 디코딩 (필드가 빠지거나 이름이 바뀌어도 최대한 버티도록 느슨하게)

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

private extension KeyedDecodingContainer where K == AnyKey {
    /// 여러 후보 키 중 처음으로 디코딩에 성공한 값
    func first<T: Decodable>(_ type: T.Type, _ keys: String...) -> T? {
        for key in keys {
            if let value = try? decodeIfPresent(T.self, forKey: AnyKey(key)) { return value }
        }
        return nil
    }
}

private struct HFAuthor: Decodable { let name: String? }

/// daily_papers / search 응답 항목: { "paper": {...}, "title", "summary", "numComments", ... }
/// 혹시 "paper" 없이 평평하게 와도 처리.
private struct HFEntry: Decodable {
    let paper: Paper

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: AnyKey.self)
        let inner = (try? outer.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("paper"))) ?? outer

        guard let id = inner.first(String.self, "id") ?? outer.first(String.self, "id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "missing paper id"))
        }

        let title = inner.first(String.self, "title") ?? outer.first(String.self, "title") ?? L10n.current.untitled
        let summary = inner.first(String.self, "summary") ?? outer.first(String.self, "summary") ?? ""
        let authors = (inner.first([HFAuthor].self, "authors") ?? []).compactMap(\.name)

        paper = Paper(
            id: id,
            title: collapseWhitespace(title),
            summary: collapseWhitespace(summary),
            authors: authors,
            publishedAt: DateParser.parse(inner.first(String.self, "publishedAt")
                                          ?? outer.first(String.self, "publishedAt")),
            upvotes: inner.first(Int.self, "upvotes"),
            numComments: outer.first(Int.self, "numComments") ?? inner.first(Int.self, "numComments"),
            githubRepo: inner.first(String.self, "githubRepo"),
            githubStars: inner.first(Int.self, "githubStars"),
            aiSummary: inner.first(String.self, "ai_summary", "aiSummary"),
            keywords: inner.first([String].self, "ai_keywords", "aiKeywords") ?? [],
            source: .huggingface
        )
    }
}
