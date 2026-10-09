import Foundation

/// Semantic Scholar Academic Graph API
///  - 인용순 탭: GET  /paper/search/bulk  (최근 N일 논문을 인용 많은 순으로)
///  - 인용수 보강: POST /paper/batch       (다른 탭 논문에 인용수 붙이기, 최대 500개씩)
/// 키 없이도 되지만 모든 비인증 사용자가 한도를 나눠 쓰므로 자주 429 가 남 → 무료 키 권장.
enum S2Client {
    private static let base = "https://api.semanticscholar.org/graph/v1"
    /// 키가 있으면 초당 1회가 기본 한도
    private static let pacer = RequestPacer(interval: 1.1)
    private static let fields = "title,abstract,authors,externalIds,publicationDate,citationCount,influentialCitationCount"

    /// 최근 `days`일 안에 나온 논문 중 인용 많은 순.
    /// query 가 nil 이면 컴퓨터과학 전체에서.
    static func mostCited(query: String?, days: Int, limit: Int = 60, apiKey: String?) async throws -> [Paper] {
        var c = URLComponents(string: "\(base)/paper/search/bulk")!
        let from = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var items = [
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "sort", value: "citationCount:desc"),
            URLQueryItem(name: "publicationDateOrYear", value: DateParser.dayOnly.string(from: from) + ":"),
        ]
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "query", value: query))
        } else {
            items.append(URLQueryItem(name: "fieldsOfStudy", value: "Computer Science"))
        }
        c.queryItems = items

        let data = try await send(URLRequest(url: c.url!), apiKey: apiKey)
        let response = try JSONDecoder().decode(BulkResponse.self, from: data)
        let papers = (response.data ?? []).compactMap { $0.value?.paper }.uniqued()
        return Array(papers.prefix(limit))
    }

    /// arXiv ID → 인용수
    static func citationCounts(arxivIDs: [String], apiKey: String?) async throws -> [String: Int] {
        var result: [String: Int] = [:]
        let chunks = stride(from: 0, to: arxivIDs.count, by: 500).map {
            Array(arxivIDs[$0..<min($0 + 500, arxivIDs.count)])
        }
        for chunk in chunks {
            var c = URLComponents(string: "\(base)/paper/batch")!
            c.queryItems = [URLQueryItem(name: "fields", value: "citationCount")]
            var request = URLRequest(url: c.url!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["ids": chunk.map { "ARXIV:\($0)" }])

            let data = try await send(request, apiKey: apiKey)
            // 찾지 못한 논문은 null 로 옴 (입력 순서와 같은 순서)
            let items = try JSONDecoder().decode([CitationOnly?].self, from: data)
            for (index, item) in items.enumerated() where index < chunk.count {
                if let count = item?.citationCount { result[chunk[index]] = count }
            }
        }
        return result
    }

    /// 간격 조절 + 429/5xx 는 2초, 4초 쉬고 재시도
    private static func send(_ request: URLRequest, apiKey: String?) async throws -> Data {
        var request = request
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        let hasKey = !(apiKey ?? "").isEmpty

        for attempt in 0..<3 {
            await pacer.waitTurn()
            let (data, response) = try await HTTP.session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) { return data }
            if (code == 429 || code >= 500), attempt < 2 {
                try? await Task.sleep(nanoseconds: UInt64(2 << attempt) * 1_000_000_000)
                continue
            }
            switch code {
            case 429: throw PaperBarError.rateLimited(hasKey: hasKey)
            case 401, 403: throw PaperBarError.badAPIKey
            default: throw PaperBarError.http(code, "api.semanticscholar.org")
            }
        }
        throw PaperBarError.rateLimited(hasKey: hasKey)
    }
}

// MARK: - 디코딩

private struct BulkResponse: Decodable {
    let total: Int?
    let token: String?
    let data: [Lossy<S2Paper>]?
}

private struct CitationOnly: Decodable {
    let citationCount: Int?
}

private struct S2Author: Decodable {
    let name: String?
}

/// externalIds 값은 문자열이거나(ArXiv, DOI) 숫자(CorpusId)라서 둘 다 받음
private struct FlexibleString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = ""
        } else if let string = try? container.decode(String.self) {
            value = string
        } else {
            value = String(try container.decode(Int.self))
        }
    }
}

private struct S2Paper: Decodable {
    let paperId: String?
    let title: String?
    let abstract: String?
    let authors: [S2Author]?
    let externalIds: [String: FlexibleString]?
    let publicationDate: String?
    let citationCount: Int?
    let influentialCitationCount: Int?

    var paper: Paper? {
        guard let paperId, let title, !title.isEmpty else { return nil }
        let arxivID = externalIds?["ArXiv"]?.value ?? ""
        var paper = Paper(
            id: arxivID.isEmpty ? "s2:\(paperId)" : arxivID,
            title: collapseWhitespace(title),
            summary: collapseWhitespace(abstract ?? ""),
            authors: (authors ?? []).compactMap(\.name),
            publishedAt: DateParser.parse(publicationDate),
            upvotes: nil,
            numComments: nil,
            githubRepo: nil,
            githubStars: nil,
            aiSummary: nil,
            keywords: [],
            source: .semanticScholar
        )
        paper.citationCount = citationCount
        paper.influentialCitations = influentialCitationCount
        paper.s2PaperID = paperId
        return paper
    }
}
