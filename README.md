# PaperBar

**English** · [한국어](README.ko.md) · [简体中文](README.zh-CN.md)

A small macOS menu bar app that gathers trending ML papers every day from Hugging Face, Hacker News, Semantic Scholar, and arXiv, with keyword feeds that search titles **and abstracts**. It runs entirely on your Mac, with no server.

## Features

| Tab | What it shows | Source |
|---|---|---|
| HF Trending | Today's 50 most upvoted papers | Hugging Face Daily Papers |
| HN Buzz | arXiv papers posted to Hacker News in the last 7 days, by points | HN Algolia API + arXiv |
| Most cited | Papers from the last 30–180 days, most cited first. Uses your keywords, or all of computer science if you have none | Semantic Scholar |
| Keyword tabs | Latest papers for each saved keyword | Hugging Face search + arXiv newest submissions |

- **Filters that read abstracts.** Searches title, abstract, AI summary, keywords, and authors, and highlights where the abstract matched.
- **Search syntax.** Space means AND, `"world model"` matches a phrase (also `world-model`), `-robot` excludes. Matching starts at word boundaries, so `agent` finds *agents* but `RL` does not match *world*. Keywords use the same syntax.
- **Strict filter.** Hugging Face search is semantic and returns papers without your keyword; the strict filter hides them (can be turned off).
- **Daily refresh.** Refreshes after the time you choose (09:00 by default) and when your Mac wakes. The menu bar icon shows how many new papers you haven't seen.
- **Citation counts.** With a Semantic Scholar API key, papers in every tab get citation counts and you can sort by citations.
- **English, 한국어, 简体中文.** Follows the system language, or pick one in Settings.

## Install

### Download a release
Download `PaperBar-vX.Y.Z.zip` from [Releases](../../releases), unzip it, and move `PaperBar.app` to `/Applications`.
The app is not notarized by Apple. If macOS blocks it on first launch, right-click the app and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/PaperBar.app
```

### Build from source
Requires macOS 13 Ventura or later and Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/LucasHyun/PaperBar.git
cd PaperBar
./build.sh --install      # build, copy to /Applications, and launch
```

During development, `swift run` launches the app without a bundle (only *Open at login* is disabled). To use Xcode, run `open Package.swift`.

## Semantic Scholar API key (optional)
PaperBar works without a key, but all anonymous users share one rate limit, so requests are often refused.
[Request a free key](https://www.semanticscholar.org/product/api#api-key-form), then paste it into ⚙︎ Settings → Semantic Scholar.
The key is stored **only in the macOS Keychain**, never in the repository or a settings file.
If you build from source, macOS may ask for Keychain access the first time a new build runs; choose *Always Allow*.

## Data sources

| Purpose | Endpoint | Key |
|---|---|---|
| Trending | `huggingface.co/api/daily_papers?sort=trending` | Not needed |
| Search | `huggingface.co/api/papers/search?q=…` | Not needed |
| Keyword feeds | `export.arxiv.org/api/query?search_query=…&sortBy=submittedDate` | Not needed |
| HN Buzz | `hn.algolia.com/api/v1/search?query=arxiv.org&restrictSearchableAttributes=url` | Not needed |
| Abstracts for HN papers | `export.arxiv.org/api/query?id_list=…` | Not needed |
| Most cited | `api.semanticscholar.org/graph/v1/paper/search/bulk?sort=citationCount:desc` | Recommended |
| Citation counts | `api.semanticscholar.org/graph/v1/paper/batch` | Only with a key |

To respect each service's usage policy, PaperBar keeps 3 seconds between arXiv requests and 1.1 seconds between Semantic Scholar requests across the whole app (`RequestPacer`). The Hugging Face API is lightly documented, so its decoder tolerates missing or renamed fields.

## Where data is stored
- Settings and keywords: `UserDefaults` (`com.paperbar.app`)
- Paper cache: `~/Library/Application Support/PaperBar/cache.json`
- Semantic Scholar key: login Keychain, service `PaperBar`

## Project layout
```
Sources/PaperBar/
  PaperBarApp.swift   Menu bar entry point and badge
  ContentView.swift   Main window: search, tabs, list, paper rows
  SettingsPane.swift  Settings screen
  PaperStore.swift    State, daily scheduler, cache, unseen tracking
  SearchQuery.swift   Search syntax parser, word-boundary matching, highlighting
  Localization.swift  English / Korean / Simplified Chinese strings
  HFClient.swift      Hugging Face API
  ArxivClient.swift   arXiv API, Atom parser, request pacer
  HNClient.swift      Hacker News (Algolia) API
  S2Client.swift      Semantic Scholar API
  Keychain.swift      API key storage
  Models.swift        Paper model and shared helpers
```

### Adding a language
Add a case to `AppLanguage` and a `static var` table in `Localization.swift` that overrides the English defaults. Any string you leave out falls back to English.

## Releasing
Push a tag that starts with `v`, and GitHub Actions builds a universal (Apple silicon + Intel) app and attaches it to a release.

```bash
git tag v1.0.0
git push origin v1.0.0
```

## License
MIT. Paper metadata belongs to its sources (arXiv, Hugging Face, Hacker News, Semantic Scholar).
