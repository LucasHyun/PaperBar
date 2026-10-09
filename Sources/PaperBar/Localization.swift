import Foundation

// 앱 안에서 바로 언어를 바꿀 수 있도록 .strings 번들 대신 Swift 테이블로 관리한다.
// 기본값이 영어이고, 한국어·중국어는 아래에서 덮어쓴다. 빠진 문구는 영어로 보인다.

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    static let defaultsKey = "appLanguage"

    /// UserDefaults 에 저장된 선택 (뷰 바깥, 예: 오류 문구에서 사용)
    static var stored: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// "시스템 설정"을 실제 언어로 바꿈
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("ko") { return .korean }
        if preferred.hasPrefix("zh") { return .chinese }
        return .english
    }

    var strings: Strings {
        switch resolved {
        case .korean: return .korean
        case .chinese: return .chinese
        default: return .english
        }
    }

    /// 날짜·숫자 형식용
    var locale: Locale {
        switch resolved {
        case .korean: return Locale(identifier: "ko_KR")
        case .chinese: return Locale(identifier: "zh_Hans_CN")
        default: return Locale(identifier: "en_US")
        }
    }

    /// 선택지에 보일 이름. 각 언어는 자기 이름으로 표시.
    func displayName(in s: Strings) -> String {
        switch self {
        case .system: return s.languageSystem
        case .english: return "English"
        case .korean: return "한국어"
        case .chinese: return "简体中文"
        }
    }
}

enum L10n {
    static var current: Strings { AppLanguage.stored.strings }
}

struct Strings {
    // MARK: 공통
    var settings = "Settings"
    var refreshAll = "Refresh all"
    var updatedAt: (String) -> String = { "Updated \($0)" }

    // MARK: 검색
    var searchPlaceholder = "Search titles & abstracts   e.g. agent \"world model\" -robot"
    var searchHelp = "Space means AND, \"quotes\" match a phrase, -word excludes. Press Return to search all of Hugging Face."
    var saveAsKeyword = "Save as keyword"
    var saveAsKeywordHelp = "Collect new papers for this keyword every day"

    // MARK: 탭
    var tabTrending = "HF Trending"
    var tabHackerNews = "HN Buzz"
    var tabMostCited = "Most cited"
    var refreshThisTab = "Refresh this tab"
    var deleteKeyword: (String) -> String = { "Delete “\($0)”" }
    var keywordPlaceholder = "Keyword"
    var addKeywordHelp = "Add a keyword (right-click a tab to delete it)"

    // MARK: 목록 제목
    var titleSearch: (String, Int) -> String = { q, n in "Hugging Face results for “\(q)” · \(n)" }
    var titleTrending: (Int, Bool) -> String = { n, filtered in
        "Today's Hugging Face trending · \(n)\(filtered ? " matching" : "")"
    }
    var titleHackerNews: (Int, Bool) -> String = { n, filtered in
        "arXiv papers on Hacker News, last 7 days · \(n)\(filtered ? " matching" : "")"
    }
    var titleMostCited: (Bool, Int, Int, Bool) -> String = { byKeywords, days, n, filtered in
        "\(byKeywords ? "Your keywords" : "Computer science") · most cited, last \(days) days · \(n)\(filtered ? " matching" : "")"
    }
    var titleKeyword: (String, Int, Bool) -> String = { kw, n, filtered in
        "“\(kw)” latest · \(n)\(filtered ? " matching" : "") · HF + arXiv"
    }
    var hiddenByStrict: (Int) -> String = { "Hid \($0) without the keyword" }
    var hiddenByStrictHelp = "Turn off “Only papers that contain the keyword” in Settings to show them"
    var sortLabel = "Sort"
    var sortRanked = "Default"
    var sortPopular = "Popular"
    var sortCited = "Cited"
    var sortNewest = "Newest"

    // MARK: 빈 화면
    var loading = "Loading papers"
    var noFilterMatch = "No title or abstract contains this search"
    var pressReturnHint = "Press Return to search all of Hugging Face"
    var noKeywordPapers = "No recent papers contain this keyword"
    var noKeywordHint = "Try another phrasing, or turn off the strict filter in Settings"
    var emptyList = "Nothing here yet"
    var emptyNeedsKey = "Nothing here yet. Add a free API key in Settings to load this reliably"
    var loadNow = "Load now"

    // MARK: 논문 행
    var newBadge = "NEW"
    var hfUpvotes = "Hugging Face upvotes"
    var hnPoints = "Hacker News points"
    var citations: (Int, Int?) -> String = { n, influential in
        influential.map { "Cited \(n) times (\($0) influential)" } ?? "Cited \(n) times"
    }
    var linkArxiv = "arXiv abstract"
    var linkPDF = "PDF"
    var linkGitHub = "GitHub code"
    var linkS2 = "Semantic Scholar (citations)"
    var linkHN = "Hacker News discussion"
    var expand = "Show full abstract"
    var collapse = "Collapse"
    var authors: ([String]) -> String = { names in
        switch names.count {
        case 0: return ""
        case 1, 2: return names.joined(separator: ", ")
        default: return "\(names[0]), \(names[1]) +\(names.count - 2) more"
        }
    }
    var untitled = "(untitled)"

    // MARK: 설정
    var back = "Back"
    var language = "Language"
    var languageSystem = "System"
    var s2KeySaved = "API key saved in Keychain"
    var deleteKey = "Delete key"
    var apiKey = "API key"
    var paste = "Paste"
    var save = "Save"
    var s2Explainer = "Works without a key, but all anonymous users share one rate limit, so requests are often refused. With a free key the Most cited tab loads reliably and papers in other tabs get citation counts. The key is stored only in this Mac's Keychain."
    var getFreeKey = "Get a free API key"
    var citedWindow = "Most cited window"
    var lastNDays: (Int) -> String = { "Last \($0) days" }
    var sectionFilter = "Filter"
    var strictToggle = "Only papers that contain the keyword"
    var strictExplainer = "Hugging Face search is semantic, so it also returns papers without the keyword. When this is on, keyword tabs and search results hide them."
    var sectionUpdates = "Updates"
    var dailyRefreshTime = "Daily refresh time"
    var launchAtLogin = "Open at login"
    var openHFTrending = "Open Hugging Face trending page"
    var quit = "Quit PaperBar"

    // MARK: 오류
    var searchFailed: (String) -> String = { "Search failed: \($0)" }
    var launchAtLoginFailed: (String) -> String = { "Couldn't change Open at login: \($0)" }
    var keychainSaveFailed = "Couldn't save the API key to Keychain"
    var httpError: (Int, String) -> String = { code, host in "\(host) returned an error (HTTP \(code))" }
    var rateLimitedWithKey = "Rate limit reached. Try again in a moment."
    var rateLimitedNoKey = "The shared rate limit is busy, so the request was refused. Add a free API key in Settings for reliable access."
    var badAPIKey = "The API key was rejected. Check it in Settings."

    // MARK: - 언어별 테이블

    static var english: Strings { Strings() }

    static var korean: Strings {
        var s = Strings()
        s.settings = "설정"
        s.refreshAll = "전체 새로고침"
        s.updatedAt = { "\($0) 갱신" }

        s.searchPlaceholder = "제목·초록에서 찾기   예: agent \"world model\" -robot"
        s.searchHelp = "공백은 AND, \"따옴표\"는 구문, -단어는 제외. Enter를 누르면 Hugging Face 전체에서 검색합니다."
        s.saveAsKeyword = "키워드로 저장"
        s.saveAsKeywordHelp = "이 키워드의 새 논문을 매일 따로 모아줍니다"

        s.tabTrending = "HF 트렌딩"
        s.tabHackerNews = "HN 화제"
        s.tabMostCited = "인용순"
        s.refreshThisTab = "이 탭 새로고침"
        s.deleteKeyword = { "‘\($0)’ 키워드 삭제" }
        s.keywordPlaceholder = "키워드"
        s.addKeywordHelp = "키워드 추가 (탭을 우클릭하면 삭제)"

        s.titleSearch = { q, n in "‘\(q)’ Hugging Face 검색 결과 \(n)편" }
        s.titleTrending = { n, filtered in "오늘의 Hugging Face 트렌딩\(filtered ? " 중 필터 일치" : "") \(n)편" }
        s.titleHackerNews = { n, filtered in "최근 7일 Hacker News에 올라온 arXiv 논문\(filtered ? " 중 필터 일치" : "") \(n)편" }
        s.titleMostCited = { byKeywords, days, n, filtered in
            "\(byKeywords ? "저장한 키워드" : "컴퓨터과학") · 최근 \(days)일 논문 인용 많은 순\(filtered ? " 중 필터 일치" : "") \(n)편"
        }
        s.titleKeyword = { kw, n, filtered in "‘\(kw)’ 최근 논문\(filtered ? " 중 필터 일치" : "") \(n)편 · HF + arXiv" }
        s.hiddenByStrict = { "키워드가 없는 \($0)편은 숨겼어요" }
        s.hiddenByStrictHelp = "⚙︎ 설정에서 ‘키워드가 제목·초록에 실제로 있는 논문만’을 끄면 모두 보여요"
        s.sortLabel = "정렬"
        s.sortRanked = "기본"
        s.sortPopular = "인기"
        s.sortCited = "인용"
        s.sortNewest = "최신"

        s.loading = "논문을 불러오는 중"
        s.noFilterMatch = "제목·초록에 이 검색어가 있는 논문이 없어요"
        s.pressReturnHint = "Enter를 누르면 Hugging Face 전체에서 찾아봅니다"
        s.noKeywordPapers = "이 키워드가 들어간 최근 논문이 없어요"
        s.noKeywordHint = "다른 표현으로 키워드를 추가하거나, ⚙︎ 설정에서 엄격 필터를 꺼 보세요"
        s.emptyList = "목록이 비어 있어요"
        s.emptyNeedsKey = "목록이 비어 있어요. ⚙︎ 설정에서 무료 API 키를 넣으면 안정적으로 불러와요"
        s.loadNow = "지금 불러오기"

        s.newBadge = "NEW"
        s.hfUpvotes = "Hugging Face 추천"
        s.hnPoints = "Hacker News 점수"
        s.citations = { n, influential in
            influential.map { "인용 \(n)회 (영향력 있는 인용 \($0)회)" } ?? "인용 \(n)회"
        }
        s.linkArxiv = "arXiv 초록"
        s.linkPDF = "PDF"
        s.linkGitHub = "GitHub 코드"
        s.linkS2 = "Semantic Scholar (인용 관계)"
        s.linkHN = "Hacker News 토론"
        s.expand = "초록 전체 보기"
        s.collapse = "접기"
        s.authors = { names in
            switch names.count {
            case 0: return ""
            case 1, 2: return names.joined(separator: ", ")
            default: return "\(names[0]), \(names[1]) 외 \(names.count - 2)명"
            }
        }
        s.untitled = "(제목 없음)"

        s.back = "목록으로"
        s.language = "언어"
        s.languageSystem = "시스템 설정"
        s.s2KeySaved = "API 키가 키체인에 저장돼 있어요"
        s.deleteKey = "키 삭제"
        s.apiKey = "API 키"
        s.paste = "붙여넣기"
        s.save = "저장"
        s.s2Explainer = "키 없이도 동작하지만 모든 비인증 사용자가 한도를 나눠 써서 자주 거절돼요. 무료 키를 넣으면 인용순 탭이 안정적으로 갱신되고, 다른 탭 논문에도 인용수가 붙어요. 키는 이 맥의 키체인에만 저장돼요."
        s.getFreeKey = "무료 API 키 신청하기"
        s.citedWindow = "인용순 탭 기간"
        s.lastNDays = { "최근 \($0)일" }
        s.sectionFilter = "필터"
        s.strictToggle = "키워드가 제목·초록에 실제로 있는 논문만"
        s.strictExplainer = "Hugging Face 검색은 의미 기반이라 키워드가 없는 논문도 섞여 와요. 켜 두면 키워드 탭과 검색 결과에서 그런 논문을 숨겨요."
        s.sectionUpdates = "갱신"
        s.dailyRefreshTime = "매일 자동 갱신 시각"
        s.launchAtLogin = "로그인할 때 자동 실행"
        s.openHFTrending = "Hugging Face 트렌딩 페이지 열기"
        s.quit = "PaperBar 종료"

        s.searchFailed = { "검색하지 못했어요: \($0)" }
        s.launchAtLoginFailed = { "로그인 시 실행을 설정하지 못했어요: \($0)" }
        s.keychainSaveFailed = "키체인에 API 키를 저장하지 못했어요"
        s.httpError = { code, host in "\(host) 응답 오류 (HTTP \(code))" }
        s.rateLimitedWithKey = "요청 한도를 넘었어요. 잠시 후 다시 시도해 주세요."
        s.rateLimitedNoKey = "공용 한도가 붐벼서 거절됐어요. ⚙︎ 설정에서 무료 API 키를 넣으면 안정적이에요."
        s.badAPIKey = "API 키가 거부됐어요. ⚙︎ 설정에서 키를 확인해 주세요."
        return s
    }

    static var chinese: Strings {
        var s = Strings()
        s.settings = "设置"
        s.refreshAll = "全部刷新"
        s.updatedAt = { "\($0) 更新" }

        s.searchPlaceholder = "在标题和摘要中查找   例：agent \"world model\" -robot"
        s.searchHelp = "空格表示 AND，\"引号\" 匹配短语，-词 表示排除。按回车在整个 Hugging Face 中搜索。"
        s.saveAsKeyword = "保存为关键词"
        s.saveAsKeywordHelp = "每天单独收集这个关键词的新论文"

        s.tabTrending = "HF 热门"
        s.tabHackerNews = "HN 热议"
        s.tabMostCited = "高引用"
        s.refreshThisTab = "刷新此标签"
        s.deleteKeyword = { "删除关键词“\($0)”" }
        s.keywordPlaceholder = "关键词"
        s.addKeywordHelp = "添加关键词（右键点击标签可删除）"

        s.titleSearch = { q, n in "“\(q)”的 Hugging Face 搜索结果 \(n) 篇" }
        s.titleTrending = { n, filtered in "今日 Hugging Face 热门\(filtered ? "中符合筛选的" : " · ")\(n) 篇" }
        s.titleHackerNews = { n, filtered in "近 7 天 Hacker News 上的 arXiv 论文\(filtered ? "中符合筛选的" : " · ")\(n) 篇" }
        s.titleMostCited = { byKeywords, days, n, filtered in
            "\(byKeywords ? "已保存的关键词" : "计算机科学") · 近 \(days) 天按引用排序\(filtered ? "中符合筛选的" : " · ")\(n) 篇"
        }
        s.titleKeyword = { kw, n, filtered in "“\(kw)”最新论文\(filtered ? "中符合筛选的" : " · ")\(n) 篇 · HF + arXiv" }
        s.hiddenByStrict = { "已隐藏 \($0) 篇不含关键词的论文" }
        s.hiddenByStrictHelp = "在设置中关闭“仅显示包含关键词的论文”即可全部显示"
        s.sortLabel = "排序"
        s.sortRanked = "默认"
        s.sortPopular = "热度"
        s.sortCited = "引用"
        s.sortNewest = "最新"

        s.loading = "正在加载论文"
        s.noFilterMatch = "没有标题或摘要包含该检索词的论文"
        s.pressReturnHint = "按回车在整个 Hugging Face 中查找"
        s.noKeywordPapers = "最近没有包含该关键词的论文"
        s.noKeywordHint = "换个说法添加关键词，或在设置中关闭严格筛选"
        s.emptyList = "列表为空"
        s.emptyNeedsKey = "列表为空。在设置中填入免费 API 密钥即可稳定加载"
        s.loadNow = "立即加载"

        s.newBadge = "新"
        s.hfUpvotes = "Hugging Face 点赞"
        s.hnPoints = "Hacker News 分数"
        s.citations = { n, influential in
            influential.map { "被引用 \(n) 次（其中有影响力的引用 \($0) 次）" } ?? "被引用 \(n) 次"
        }
        s.linkArxiv = "arXiv 摘要"
        s.linkPDF = "PDF"
        s.linkGitHub = "GitHub 代码"
        s.linkS2 = "Semantic Scholar（引用关系）"
        s.linkHN = "Hacker News 讨论"
        s.expand = "展开完整摘要"
        s.collapse = "收起"
        s.authors = { names in
            switch names.count {
            case 0: return ""
            case 1, 2: return names.joined(separator: "、")
            default: return "\(names[0])、\(names[1]) 等 \(names.count) 人"
            }
        }
        s.untitled = "（无标题）"

        s.back = "返回"
        s.language = "语言"
        s.languageSystem = "跟随系统"
        s.s2KeySaved = "API 密钥已保存在钥匙串中"
        s.deleteKey = "删除密钥"
        s.apiKey = "API 密钥"
        s.paste = "粘贴"
        s.save = "保存"
        s.s2Explainer = "不填密钥也能使用，但所有匿名用户共享同一限额，请求经常被拒绝。填入免费密钥后，“高引用”标签可以稳定刷新，其他标签的论文也会显示引用数。密钥只保存在本机的钥匙串中。"
        s.getFreeKey = "申请免费 API 密钥"
        s.citedWindow = "高引用统计范围"
        s.lastNDays = { "近 \($0) 天" }
        s.sectionFilter = "筛选"
        s.strictToggle = "仅显示标题或摘要包含关键词的论文"
        s.strictExplainer = "Hugging Face 的搜索基于语义，也会返回不含关键词的论文。开启后，关键词标签和搜索结果会隐藏这些论文。"
        s.sectionUpdates = "更新"
        s.dailyRefreshTime = "每日自动更新时间"
        s.launchAtLogin = "登录时自动打开"
        s.openHFTrending = "打开 Hugging Face 热门页面"
        s.quit = "退出 PaperBar"

        s.searchFailed = { "搜索失败：\($0)" }
        s.launchAtLoginFailed = { "无法设置登录时打开：\($0)" }
        s.keychainSaveFailed = "无法将 API 密钥保存到钥匙串"
        s.httpError = { code, host in "\(host) 返回错误（HTTP \(code)）" }
        s.rateLimitedWithKey = "已达到请求限额，请稍后再试。"
        s.rateLimitedNoKey = "共享限额繁忙，请求被拒绝。在设置中填入免费 API 密钥即可稳定访问。"
        s.badAPIKey = "API 密钥被拒绝，请在设置中检查。"
        return s
    }
}
