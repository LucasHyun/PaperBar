import AppKit
import Foundation
import ServiceManagement

/// 탭 하나 = 피드 하나
enum FeedID: Hashable {
    case trending              // Hugging Face 트렌딩
    case hackerNews            // 최근 7일 HN 에서 화제가 된 arXiv 논문
    case semanticScholar       // 최근 N일 논문 중 인용 많은 순 (Semantic Scholar)
    case keyword(String)       // 저장한 키워드
}

/// 지금 화면에 보여줄 목록 + 엄격 필터로 숨긴 개수
struct ListState {
    var papers: [Paper]
    var hiddenByStrict: Int
}

@MainActor
final class PaperStore: ObservableObject {

    // MARK: 피드
    @Published private(set) var trending: [Paper] = []
    @Published private(set) var hackerNews: [Paper] = []
    @Published private(set) var semanticScholar: [Paper] = []
    @Published private(set) var keywordFeeds: [String: [Paper]] = [:]
    @Published private(set) var searchResults: [Paper]?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSearching = false
    @Published private(set) var loadingFeeds: Set<FeedID> = []
    @Published var errorMessage: String?

    // MARK: UI 상태
    @Published private(set) var selected: FeedID = .trending
    @Published var sortMode: SortMode = .ranked
    @Published var query = "" {
        didSet { if query != oldValue { searchResults = nil } }  // 입력이 바뀌면 원격 검색 결과 해제
    }

    // MARK: 설정 (UserDefaults 에 저장)
    @Published var keywords: [String] {
        didSet { defaults.set(keywords, forKey: Keys.keywords) }
    }
    @Published var refreshHour: Int {
        didSet { defaults.set(refreshHour, forKey: Keys.refreshHour) }
    }
    /// 켜면: 키워드 탭과 검색 결과에서 키워드가 제목·초록 등에 실제로 들어있는 논문만 표시
    /// (HF 검색은 의미 기반이라 키워드가 없는 논문도 섞여 옴)
    @Published var strictMatch: Bool {
        didSet { defaults.set(strictMatch, forKey: Keys.strictMatch) }
    }
    /// 인용순 탭이 보는 기간(일)
    @Published var s2WindowDays: Int {
        didSet {
            defaults.set(s2WindowDays, forKey: Keys.s2WindowDays)
            if s2WindowDays != oldValue { Task { await refresh(.semanticScholar) } }
        }
    }
    /// Semantic Scholar API 키는 키체인에만 저장
    @Published private(set) var hasS2Key = false
    private var s2Key: String?

    /// 앱 표시 언어. 바꾸면 화면이 바로 다시 그려짐.
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: AppLanguage.defaultsKey)
            s = language.strings
        }
    }
    /// 현재 언어의 문구 테이블
    @Published private(set) var s: Strings

    // MARK: 새 논문 추적
    @Published private(set) var unseenCount = 0
    @Published private(set) var highlightedNew: Set<String> = []
    private var seen: [String: Double]

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private enum Keys {
        static let keywords = "keywords"
        static let refreshHour = "refreshHour"
        static let strictMatch = "strictMatch"
        static let s2WindowDays = "s2WindowDays"
        static let s2KeychainAccount = "semanticScholarAPIKey"
        static let seen = "seenPaperIDs"
    }

    init() {
        _keywords = Published(initialValue: defaults.stringArray(forKey: Keys.keywords) ?? [])
        _refreshHour = Published(initialValue: defaults.object(forKey: Keys.refreshHour) as? Int ?? 9)
        _strictMatch = Published(initialValue: defaults.object(forKey: Keys.strictMatch) as? Bool ?? true)
        let lang = AppLanguage.stored
        _language = Published(initialValue: lang)
        _s = Published(initialValue: lang.strings)
        _s2WindowDays = Published(initialValue: defaults.object(forKey: Keys.s2WindowDays) as? Int ?? 60)
        seen = defaults.dictionary(forKey: Keys.seen) as? [String: Double] ?? [:]
        s2Key = Keychain.read(Keys.s2KeychainAccount)
        hasS2Key = s2Key != nil

        loadCache()
        recomputeUnseen()
        startScheduler()
        Task { await refreshIfNeeded() }
    }

    // MARK: - 화면에 보여줄 목록

    func feed(for id: FeedID) -> [Paper] {
        switch id {
        case .trending: return trending
        case .hackerNews: return hackerNews
        case .semanticScholar: return semanticScholar
        case let .keyword(kw): return keywordFeeds[kw] ?? []
        }
    }

    var listState: ListState {
        var papers: [Paper]
        var hidden = 0

        if let results = searchResults {
            papers = results
            if strictMatch {
                let q = SearchQuery(query)
                papers = results.filter(q.matches)
                hidden = results.count - papers.count
            }
        } else {
            papers = feed(for: selected)
            if strictMatch, case let .keyword(kw) = selected {
                let q = SearchQuery(kw)
                let kept = papers.filter(q.matches)
                hidden = papers.count - kept.count
                papers = kept
            }
            let filter = SearchQuery(query)
            if !filter.isEmpty { papers = papers.filter(filter.matches) }
        }

        switch sortMode {
        case .ranked:
            break
        case .popular:
            papers.sort { $0.popularity > $1.popularity }
        case .cited:
            papers.sort { ($0.citationCount ?? -1) > ($1.citationCount ?? -1) }
        case .newest:
            papers.sort { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        }
        return ListState(papers: papers, hiddenByStrict: hidden)
    }

    /// 목록에서 하이라이트할 검색어: 키워드 탭이면 키워드 + 입력한 필터
    var highlightQuery: SearchQuery? {
        var parts: [String] = []
        if searchResults == nil {
            switch selected {
            case let .keyword(kw): parts.append(kw)
            case .semanticScholar: parts.append(contentsOf: keywords)   // 저장한 키워드 아무거나 걸린 곳 표시
            default: break
            }
        }
        if !query.isEmpty { parts.append(query) }
        let q = SearchQuery(parts.joined(separator: " "))
        return q.includes.isEmpty ? nil : q
    }

    func isSelected(_ id: FeedID) -> Bool { searchResults == nil && selected == id }

    func newCount(for id: FeedID) -> Int {
        feed(for: id).reduce(0) { $0 + (highlightedNew.contains($1.id) ? 1 : 0) }
    }

    // MARK: - 탭 · 키워드

    func select(_ id: FeedID) {
        selected = id
        query = ""
        searchResults = nil
    }

    func addKeyword(_ raw: String) {
        let kw = collapseWhitespace(raw)
        guard !SearchQuery(kw).includes.isEmpty else { return }
        if let existing = keywords.first(where: { $0.caseInsensitiveCompare(kw) == .orderedSame }) {
            select(.keyword(existing))
            return
        }
        keywords.append(kw)
        select(.keyword(kw))
        Task { await refreshKeyword(kw, markAsSeen: true) }
    }

    func removeKeyword(_ kw: String) {
        keywords.removeAll { $0 == kw }
        keywordFeeds[kw] = nil
        if selected == .keyword(kw) { select(.trending) }
        saveCache()
        recomputeUnseen()
    }

    // MARK: - 네트워크

    /// 검색창에서 Enter: Hugging Face 전체 검색
    func runSearch() async {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = SearchQuery(raw)
        guard !q.plainText.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let results = try await HFClient.search(q.plainText, limit: 50)
            // 기다리는 동안 입력이 바뀌었으면 버림
            if query.trimmingCharacters(in: .whitespacesAndNewlines) == raw {
                searchResults = results
            }
        } catch {
            errorMessage = s.searchFailed(error.localizedDescription)
        }
    }

    func refresh(_ id: FeedID) async {
        switch id {
        case .trending: await refreshAll()
        case .hackerNews: errorMessage = await refreshHackerNews()
        case .semanticScholar: errorMessage = await refreshSemanticScholar()
        case let .keyword(kw): await refreshKeyword(kw, markAsSeen: false)
        }
        saveCache()
        recomputeUnseen()
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let firstRun = seen.isEmpty
        var errors: [String] = []

        loadingFeeds.insert(.trending)
        do {
            trending = try await HFClient.trending(limit: 50)
            lastUpdated = Date()
        } catch {
            errors.append("\(s.tabTrending): \(error.localizedDescription)")
        }
        loadingFeeds.remove(.trending)

        if let message = await refreshHackerNews() { errors.append(message) }

        // arXiv 요청 간격은 ArxivClient 가 알아서 지킴
        for kw in keywords {
            if let message = await refreshKeyword(kw, markAsSeen: false) { errors.append(message) }
        }

        if let message = await refreshSemanticScholar() { errors.append(message) }
        await enrichCitations()

        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
        saveCache()

        // 맨 처음 실행 때는 전부 '새 논문' 배지가 뜨지 않도록 조용히 본 것으로 처리
        if firstRun { markSeen(allIDs) }
        recomputeUnseen()
    }

    /// 실패하면 에러 문구를 돌려줌
    private func refreshHackerNews() async -> String? {
        loadingFeeds.insert(.hackerNews)
        defer { loadingFeeds.remove(.hackerNews) }
        do {
            let stories = try await HNClient.arxivStories(days: 7)
            let meta = try await ArxivClient.papers(ids: stories.map(\.arxivID))
            let byID = Dictionary(meta.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            hackerNews = stories.compactMap { story in
                guard var paper = byID[story.arxivID] else { return nil }
                paper.hnItemID = story.itemID
                paper.hnPoints = story.points
                paper.hnComments = story.comments
                return paper
            }
            return nil
        } catch {
            return "\(s.tabHackerNews): \(error.localizedDescription)"
        }
    }

    /// 인용순 탭이 쓰는 질의: 저장한 키워드들을 OR 로 묶음. 키워드가 없으면 nil(컴퓨터과학 전체).
    var s2Query: String? {
        let parts = keywords.compactMap { SearchQuery($0).semanticScholarQuery }
        guard !parts.isEmpty else { return nil }
        return parts.count == 1 ? parts[0] : parts.map { "(\($0))" }.joined(separator: " | ")
    }

    private func refreshSemanticScholar() async -> String? {
        loadingFeeds.insert(.semanticScholar)
        defer { loadingFeeds.remove(.semanticScholar) }
        do {
            semanticScholar = try await S2Client.mostCited(query: s2Query, days: s2WindowDays, apiKey: s2Key)
            return nil
        } catch {
            return "\(s.tabMostCited): \(error.localizedDescription)"
        }
    }

    /// 다른 탭 논문에도 인용수를 붙임. 부가 정보라 키가 있을 때만, 실패해도 조용히 넘어감.
    private func enrichCitations() async {
        guard let key = s2Key else { return }
        let ids = Set(trending.map(\.id) + hackerNews.map(\.id) + keywordFeeds.values.flatMap { $0.map(\.id) })
            .filter { !$0.hasPrefix("s2:") }
        guard !ids.isEmpty,
              let counts = try? await S2Client.citationCounts(arxivIDs: Array(ids), apiKey: key) else { return }

        func apply(_ list: [Paper]) -> [Paper] {
            list.map { paper in
                var p = paper
                if let count = counts[p.id] { p.citationCount = count }
                return p
            }
        }
        trending = apply(trending)
        hackerNews = apply(hackerNews)
        keywordFeeds = keywordFeeds.mapValues(apply)
    }

    func saveS2Key(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if Keychain.save(key, account: Keys.s2KeychainAccount) {
            s2Key = key
            hasS2Key = true
            Task {
                await refresh(.semanticScholar)
                await enrichCitations()
                saveCache()
            }
        } else {
            errorMessage = s.keychainSaveFailed
        }
    }

    func deleteS2Key() {
        Keychain.delete(Keys.s2KeychainAccount)
        s2Key = nil
        hasS2Key = false
    }

    @discardableResult
    private func refreshKeyword(_ kw: String, markAsSeen: Bool) async -> String? {
        loadingFeeds.insert(.keyword(kw))
        defer { loadingFeeds.remove(.keyword(kw)) }
        do {
            let feed = try await fetchKeywordFeed(kw)
            guard keywords.contains(kw) else { return nil }   // 그새 삭제된 경우
            keywordFeeds[kw] = feed
            if markAsSeen {
                markSeen(Set(feed.map(\.id)))
                saveCache()
                recomputeUnseen()
            }
            return nil
        } catch {
            let message = "‘\(kw)’: \(error.localizedDescription)"
            if markAsSeen { errorMessage = message }
            return message
        }
    }

    private func fetchKeywordFeed(_ kw: String) async throws -> [Paper] {
        let q = SearchQuery(kw)
        var firstError: Error?

        let hf: [Paper]
        do { hf = q.plainText.isEmpty ? [] : try await HFClient.search(q.plainText, limit: 30) }
        catch { hf = []; firstError = error }

        let arxiv: [Paper]
        do { arxiv = try await ArxivClient.latest(matching: q) }
        catch { arxiv = []; firstError = firstError ?? error }

        if hf.isEmpty, arxiv.isEmpty, let error = firstError { throw error }

        // 같은 논문이면 HF 버전(추천수·코드 링크)을 우선, 날짜는 arXiv 것으로 보완
        var byID: [String: Paper] = [:]
        for p in arxiv { byID[p.id] = p }
        for p in hf {
            var merged = p
            if merged.publishedAt == nil { merged.publishedAt = byID[p.id]?.publishedAt }
            byID[p.id] = merged
        }
        // 엄격 필터는 화면에서 적용 (설정을 바꾸면 바로 반영되도록 원본은 그대로 저장)
        return byID.values
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .prefix(50)
            .map { $0 }
    }

    // MARK: - 매일 자동 갱신

    /// 오늘의 갱신 시각을 지났는데 그 이후 갱신이 없거나, 26시간 넘게 갱신이 없으면 true
    var needsRefresh: Bool {
        guard let last = lastUpdated else { return true }
        let now = Date()
        if now.timeIntervalSince(last) > 26 * 3600 { return true }
        guard let target = Calendar.current.date(bySettingHour: refreshHour, minute: 0, second: 0, of: now) else {
            return false
        }
        return now >= target && last < target
    }

    func refreshIfNeeded() async {
        if needsRefresh { await refreshAll() }
    }

    private func startScheduler() {
        // weak self 는 var 라서 Task 로 바로 넘기면 Swift 6 컴파일러가 막음 → let 으로 꺼내서 넘김
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in await store.refreshIfNeeded() }
        }
        // 맥북을 덮었다 열었을 때도 확인 (네트워크 재연결을 잠깐 기다림)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await store.refreshIfNeeded()
            }
        }
    }

    // MARK: - 새 논문 표시

    private var allIDs: Set<String> {
        Set(trending.map(\.id))
            .union(hackerNews.map(\.id))
            .union(semanticScholar.map(\.id))
            .union(keywordFeeds.values.flatMap { $0.map(\.id) })
    }

    /// 메뉴바 창을 열 때 호출: 안 본 논문을 NEW 로 표시하고 배지를 지움
    func markOpened() {
        let unseen = allIDs.subtracting(seen.keys)
        guard !unseen.isEmpty else { return }
        highlightedNew = unseen
        markSeen(unseen)
        recomputeUnseen()
    }

    private func markSeen(_ ids: Set<String>) {
        let now = Date().timeIntervalSince1970
        for id in ids where seen[id] == nil { seen[id] = now }
        let cutoff = now - 90 * 24 * 3600   // 90일 지난 기록은 정리
        seen = seen.filter { $0.value > cutoff }
        defaults.set(seen, forKey: Keys.seen)
    }

    private func recomputeUnseen() {
        unseenCount = allIDs.subtracting(seen.keys).count
    }

    // MARK: - 로그인 시 실행 (.app 번들로 실행할 때만 동작)

    var canLaunchAtLogin: Bool { Bundle.main.bundleIdentifier != nil }

    var launchAtLogin: Bool {
        canLaunchAtLogin && SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = s.launchAtLoginFailed(error.localizedDescription)
        }
        objectWillChange.send()
    }

    // MARK: - 디스크 캐시

    private struct Cache: Codable {
        var trending: [Paper]
        var hackerNews: [Paper]?        // 예전 캐시에는 없을 수 있음
        var semanticScholar: [Paper]?
        var keywordFeeds: [String: [Paper]]
        var lastUpdated: Date?
    }

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        trending = cache.trending
        hackerNews = cache.hackerNews ?? []
        semanticScholar = cache.semanticScholar ?? []
        keywordFeeds = cache.keywordFeeds.filter { keywords.contains($0.key) }
        lastUpdated = cache.lastUpdated
    }

    private func saveCache() {
        let cache = Cache(trending: trending, hackerNews: hackerNews, semanticScholar: semanticScholar,
                          keywordFeeds: keywordFeeds, lastUpdated: lastUpdated)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
