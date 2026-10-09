import Foundation

enum PaperSource: String, Codable {
    case huggingface
    case arxiv
    case semanticScholar
}

/// 앱 전체에서 쓰는 논문 한 편.
/// id 는 arXiv ID (예: 2410.12345). arXiv 에 없는 Semantic Scholar 논문은 "s2:<paperId>".
struct Paper: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var summary: String
    var authors: [String]
    var publishedAt: Date?
    var upvotes: Int?
    var numComments: Int?
    var githubRepo: String?
    var githubStars: Int?
    var aiSummary: String?
    var keywords: [String]
    var source: PaperSource

    // Hacker News 에서 화제가 된 경우
    var hnItemID: String? = nil
    var hnPoints: Int? = nil
    var hnComments: Int? = nil

    // Semantic Scholar
    var citationCount: Int? = nil
    var influentialCitations: Int? = nil
    var s2PaperID: String? = nil

    var isArxiv: Bool { !id.hasPrefix("s2:") }

    var hfURL: URL? { isArxiv ? URL(string: "https://huggingface.co/papers/\(id)") : nil }
    var arxivURL: URL? { isArxiv ? URL(string: "https://arxiv.org/abs/\(id)") : nil }
    var pdfURL: URL? { isArxiv ? URL(string: "https://arxiv.org/pdf/\(id)") : nil }
    var githubURL: URL? { githubRepo.flatMap(URL.init(string:)) }
    var hnURL: URL? { hnItemID.flatMap { URL(string: "https://news.ycombinator.com/item?id=\($0)") } }
    var s2URL: URL? {
        if let s2PaperID { return URL(string: "https://www.semanticscholar.org/paper/\(s2PaperID)") }
        return isArxiv ? URL(string: "https://www.semanticscholar.org/arxiv/\(id)") : nil
    }

    /// 행을 클릭했을 때 열리는 주소
    var primaryURL: URL? {
        switch source {
        case .huggingface: return hfURL ?? arxivURL
        case .arxiv: return arxivURL
        case .semanticScholar: return s2URL ?? arxivURL
        }
    }

    var sourceLabel: String {
        switch source {
        case .huggingface: return "HF"
        case .arxiv: return "arXiv"
        case .semanticScholar: return "S2"
        }
    }

    /// 인기순 정렬용: HF 추천수 → HN 점수 → 인용수 순으로 사용
    var popularity: Int { upvotes ?? hnPoints ?? citationCount ?? -1 }

    /// 필터가 들여다보는 전체 텍스트: 제목 + 초록 + AI 요약 + 키워드/분야 + 저자
    var searchableText: String {
        [title, summary, aiSummary ?? "", keywords.joined(separator: " "), authors.joined(separator: ", ")]
            .joined(separator: "\n")
    }
}

extension Array where Element == Paper {
    /// 같은 id 가 여러 번 나오면 처음 것만 남김
    func uniqued() -> [Paper] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case ranked, popular, cited, newest
    var id: String { rawValue }

    func label(_ s: Strings) -> String {
        switch self {
        case .ranked: return s.sortRanked
        case .popular: return s.sortPopular
        case .cited: return s.sortCited
        case .newest: return s.sortNewest
        }
    }
}

// MARK: - 공용 유틸

/// 배열 안 항목 하나가 깨져도 나머지는 살리는 디코딩 래퍼
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

enum DateParser {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    /// Semantic Scholar 의 "2025-03-14"
    static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return withFraction.date(from: string) ?? plain.date(from: string) ?? dayOnly.date(from: string)
    }
}

/// 줄바꿈·연속 공백을 한 칸으로
func collapseWhitespace(_ s: String) -> String {
    s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

enum PaperBarError: LocalizedError {
    case http(Int, String)
    case rateLimited(hasKey: Bool)
    case badAPIKey

    var errorDescription: String? {
        let s = L10n.current
        switch self {
        case let .http(code, host): return s.httpError(code, host)
        case let .rateLimited(hasKey): return hasKey ? s.rateLimitedWithKey : s.rateLimitedNoKey
        case .badAPIKey: return s.badAPIKey
        }
    }
}

enum HTTP {
    static let userAgent = "PaperBar/1.0 (macOS menu bar app)"

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PaperBarError.http(http.statusCode, url.host ?? "")
        }
        return data
    }
}
