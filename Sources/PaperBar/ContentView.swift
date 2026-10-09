import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PaperStore
    @State private var addingKeyword = false
    @State private var newKeyword = ""
    @State private var showingSettings = false

    private var s: Strings { store.s }

    var body: some View {
        Group {
            if showingSettings {
                SettingsPane { showingSettings = false }
            } else {
                mainView
            }
        }
        .frame(width: 460, height: 620)
        .environment(\.locale, store.language.locale)
        .onAppear { store.markOpened() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.markOpened()
        }
    }

    private var mainView: some View {
        let state = store.listState
        return VStack(spacing: 0) {
            header
            searchBar
            tabs
            Divider()
            listHeader(state)
            list(state)
            if let message = store.errorMessage {
                errorBar(message)
            }
        }
    }

    // MARK: 상단

    private var header: some View {
        HStack(spacing: 8) {
            Text("PaperBar")
                .font(.system(size: 14, weight: .bold))
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if let updated = store.lastUpdated {
                let style = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(store.language.locale)
                Text(s.updatedAt(updated.formatted(style)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help(s.refreshAll)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(s.settings)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: 검색

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(s.searchPlaceholder, text: $store.query)
                .textFieldStyle(.plain)
                .onSubmit { Task { await store.runSearch() } }
                .help(s.searchHelp)
            if store.isSearching {
                ProgressView().controlSize(.small)
            }
            if !store.query.isEmpty {
                Button(s.saveAsKeyword) {
                    store.addKeyword(store.query)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(s.saveAsKeywordHelp)

                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: 탭

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BuiltInFeed.all) { feed in
                    feedChip(feed.id, title: feed.title(s), systemImage: feed.icon)
                        .contextMenu {
                            Button(s.refreshThisTab) { Task { await store.refresh(feed.id) } }
                        }
                }

                ForEach(store.keywords, id: \.self) { kw in
                    feedChip(.keyword(kw), title: kw)
                        .contextMenu {
                            Button(s.refreshThisTab) { Task { await store.refresh(.keyword(kw)) } }
                            Button(s.deleteKeyword(kw), role: .destructive) { store.removeKeyword(kw) }
                        }
                }

                if addingKeyword {
                    TextField(s.keywordPlaceholder, text: $newKeyword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onSubmit {
                            store.addKeyword(newKeyword)
                            newKeyword = ""
                            addingKeyword = false
                        }
                        .onExitCommand {
                            newKeyword = ""
                            addingKeyword = false
                        }
                } else {
                    Button {
                        addingKeyword = true
                    } label: {
                        Image(systemName: "plus")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderless)
                    .help(s.addKeywordHelp)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }

    private func feedChip(_ id: FeedID, title: String, systemImage: String? = nil) -> some View {
        Chip(title: title,
             systemImage: systemImage,
             badge: store.newCount(for: id),
             isLoading: store.loadingFeeds.contains(id),
             isSelected: store.isSelected(id)) {
            store.select(id)
        }
    }

    // MARK: 목록

    private func listHeader(_ state: ListState) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if state.hiddenByStrict > 0 {
                    Text(s.hiddenByStrict(state.hiddenByStrict))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help(s.hiddenByStrictHelp)
                }
            }
            Spacer()
            Picker(s.sortLabel, selection: $store.sortMode) {
                ForEach(SortMode.allCases) { mode in
                    Text(mode.label(s)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func title(for state: ListState) -> String {
        let n = state.papers.count
        if store.searchResults != nil {
            return s.titleSearch(store.query, n)
        }
        let filtered = !store.query.isEmpty
        switch store.selected {
        case .trending:
            return s.titleTrending(n, filtered)
        case .hackerNews:
            return s.titleHackerNews(n, filtered)
        case .semanticScholar:
            return s.titleMostCited(!store.keywords.isEmpty, store.s2WindowDays, n, filtered)
        case let .keyword(kw):
            return s.titleKeyword(kw, n, filtered)
        }
    }

    @ViewBuilder
    private func list(_ state: ListState) -> some View {
        if state.papers.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let highlight = store.highlightQuery
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.papers) { paper in
                        PaperRow(paper: paper,
                                 isNew: store.highlightedNew.contains(paper.id),
                                 highlight: highlight,
                                 strings: s,
                                 locale: store.language.locale)
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if store.isSearching || store.loadingFeeds.contains(store.selected) {
                ProgressView()
                Text(s.loading)
            } else if !store.query.isEmpty {
                Text(s.noFilterMatch)
                Text(s.pressReturnHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isKeywordTab {
                Text(s.noKeywordPapers)
                Text(s.noKeywordHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(store.selected == .semanticScholar && !store.hasS2Key ? s.emptyNeedsKey : s.emptyList)
                Button(s.loadNow) { Task { await store.refresh(store.selected) } }
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding()
    }

    private var isKeywordTab: Bool {
        if case .keyword = store.selected { return true }
        return false
    }

    private func errorBar(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer()
            Button {
                store.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - 논문 한 줄

struct PaperRow: View {
    let paper: Paper
    let isNew: Bool
    let highlight: SearchQuery?
    let strings: Strings
    let locale: Locale
    @State private var hovering = false
    @State private var expanded = false

    private var s: Strings { strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isNew {
                    Text(s.newBadge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundColor(.white)
                }
                Text(marked(paper.title))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let authorLine = s.authors(paper.authors)
            if !authorLine.isEmpty {
                Text(authorLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let tldr = paper.aiSummary, !tldr.isEmpty {
                        Text(marked(tldr))
                            .font(.caption.weight(.medium))
                    }
                    if !paper.summary.isEmpty {
                        Text(marked(paper.summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
                .padding(.top, 2)
            } else if let snippet = highlight?.snippet(from: paper.summary) {
                // 초록 어디에서 걸렸는지 보여줌
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                if let up = paper.upvotes {
                    Label("\(up)", systemImage: "arrowtriangle.up.fill")
                        .help(s.hfUpvotes)
                }
                if let points = paper.hnPoints {
                    Label("\(points)", systemImage: "y.square.fill")
                        .help(s.hnPoints)
                }
                if let comments = (paper.hnComments ?? paper.numComments), comments > 0 {
                    Label("\(comments)", systemImage: "bubble.left")
                }
                if let cited = paper.citationCount {
                    Label(cited.formatted(.number.notation(.compactName).locale(locale)), systemImage: "quote.bubble")
                        .help(s.citations(cited, paper.influentialCitations))
                }
                if let stars = paper.githubStars, stars > 0 {
                    Label(stars.formatted(.number.notation(.compactName).locale(locale)), systemImage: "star")
                }
                if let date = paper.publishedAt {
                    Text(date.formatted(.dateTime.month().day().locale(locale)))
                }
                Text(paper.sourceLabel)

                Spacer()

                if hovering || expanded {
                    linkButton("doc.text", paper.arxivURL, help: s.linkArxiv)
                    linkButton("arrow.down.doc", paper.pdfURL, help: s.linkPDF)
                    if let github = paper.githubURL {
                        linkButton("chevron.left.forwardslash.chevron.right", github, help: s.linkGitHub)
                    }
                    if let s2 = paper.s2URL {
                        linkButton("quote.bubble", s2, help: s.linkS2)
                    }
                    if let hn = paper.hnURL {
                        linkButton("bubble.left.and.bubble.right", hn, help: s.linkHN)
                    }
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help(expanded ? s.collapse : s.expand)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(TightLabelStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let url = paper.primaryURL { NSWorkspace.shared.open(url) }
        }
    }

    private func marked(_ text: String) -> AttributedString {
        highlight?.highlighted(text) ?? AttributedString(text)
    }

    @ViewBuilder
    private func linkButton(_ icon: String, _ url: URL?, help: String) -> some View {
        if let url {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: icon)
            }
            .buttonStyle(.borderless)
            .help(help)
        }
    }
}

// MARK: - 작은 구성 요소

struct BuiltInFeed: Identifiable {
    let id: FeedID
    let icon: String

    func title(_ s: Strings) -> String {
        switch id {
        case .trending: return s.tabTrending
        case .hackerNews: return s.tabHackerNews
        case .semanticScholar: return s.tabMostCited
        case let .keyword(kw): return kw
        }
    }

    static let all: [BuiltInFeed] = [
        BuiltInFeed(id: .trending, icon: "flame"),
        BuiltInFeed(id: .hackerNews, icon: "bubble.left.and.bubble.right"),
        BuiltInFeed(id: .semanticScholar, icon: "quote.bubble"),
    ]
}

struct Chip: View {
    let title: String
    var systemImage: String?
    var badge: Int = 0
    var isLoading = false
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).lineLimit(1)
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.3)
                                                              : Color.accentColor.opacity(0.2)))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.07)))
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}
