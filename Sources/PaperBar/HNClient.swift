import Foundation

/// Hacker News 공개 검색 API (Algolia, 키 불필요)
/// 최근 N일 동안 arXiv 링크가 걸린 스토리를 점수순으로 가져온다.
/// HN 은 제목·링크만 주므로 초록 등은 ArxivClient.papers(ids:) 로 보강.
enum HNClient {
    struct Story {
        let arxivID: String
        let itemID: String
        let points: Int
        let comments: Int
    }

    private struct Response: Decodable { let hits: [Hit] }
    private struct Hit: Decodable {
        let objectID: String
        let url: String?
        let points: Int?
        let num_comments: Int?
    }

    static func arxivStories(days: Int = 7, minPoints: Int = 3) async throws -> [Story] {
        var c = URLComponents(string: "https://hn.algolia.com/api/v1/search")!
        let since = Int(Date().timeIntervalSince1970) - days * 86_400
        c.queryItems = [
            URLQueryItem(name: "query", value: "arxiv.org"),
            URLQueryItem(name: "restrictSearchableAttributes", value: "url"),
            URLQueryItem(name: "tags", value: "story"),
            URLQueryItem(name: "numericFilters", value: "created_at_i>\(since),points>=\(minPoints)"),
            URLQueryItem(name: "hitsPerPage", value: "100"),
        ]
        let data = try await HTTP.get(c.url!)
        let hits = try JSONDecoder().decode(Response.self, from: data).hits

        // 같은 논문이 여러 번 올라왔으면 점수가 가장 높은 스토리만
        var best: [String: Story] = [:]
        for hit in hits {
            guard let url = hit.url, let id = arxivID(fromURL: url) else { continue }
            let story = Story(arxivID: id, itemID: hit.objectID,
                              points: hit.points ?? 0, comments: hit.num_comments ?? 0)
            if let existing = best[id], existing.points >= story.points { continue }
            best[id] = story
        }
        return best.values.sorted { $0.points > $1.points }
    }

    /// arxiv.org/abs|pdf|html/<id> (alphaxiv.org 링크도 같은 id 라 함께 잡힘), 버전 꼬리는 제외
    static func arxivID(fromURL url: String) -> String? {
        let pattern = #"arxiv\.org/(?:abs|pdf|html)/([a-z\-]+(?:\.[A-Za-z]{2})?/\d{7}|\d{4}\.\d{4,5})"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let range = Range(match.range(at: 1), in: url) else { return nil }
        return String(url[range])
    }
}
