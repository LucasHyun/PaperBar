# PaperBar

[English](README.md) · **한국어** · [简体中文](README.zh-CN.md)

매일 아침 메뉴바에서 오늘 뜨는 ML 논문을 확인하는 macOS 앱이에요. Hugging Face, Hacker News, Semantic Scholar, arXiv에서 논문을 모으고, 저장한 키워드로 제목은 물론 **초록까지** 걸러 줘요. 서버 없이 맥 안에서만 동작해요.

## 기능

| 탭 | 내용 | 소스 |
|---|---|---|
| HF 트렌딩 | 오늘 추천이 가장 많이 몰린 논문 50편 | Hugging Face Daily Papers |
| HN 화제 | 최근 7일 Hacker News에 올라온 arXiv 논문, 점수순 | HN Algolia API + arXiv |
| 인용순 | 최근 30–180일 논문 중 인용 많은 순. 키워드가 있으면 그 키워드로, 없으면 컴퓨터과학 전체 | Semantic Scholar |
| 키워드 탭 | 저장한 키워드별 최신 논문 | Hugging Face 검색 + arXiv 최신 제출순 |

- **초록까지 보는 필터.** 제목·초록·AI 요약·키워드·저자 전체에서 찾고, 초록에서 걸린 부분은 형광펜으로 보여 줘요.
- **검색 문법.** 공백은 AND, `"world model"`은 구문(world-model도 매치), `-robot`은 제외예요. 단어 시작 기준으로 매칭해서 `agent`는 agents와 맞지만 `RL`은 world와 안 맞아요. 키워드에도 같은 문법을 써요.
- **엄격 필터.** Hugging Face 검색은 의미 기반이라 키워드가 없는 논문도 섞여 오는데, 그런 논문을 숨겨요(끌 수 있음).
- **매일 자동 갱신.** 설정한 시각(기본 09:00) 이후와 맥을 깨웠을 때 갱신하고, 안 본 새 논문 수를 메뉴바에 표시해요.
- **인용수.** Semantic Scholar API 키를 넣으면 모든 탭의 논문에 인용수가 붙고 인용순 정렬을 쓸 수 있어요.
- **English, 한국어, 简体中文.** 시스템 언어를 따르고, 설정에서 직접 고를 수도 있어요.

## 설치

### 릴리스에서 받기
[Releases](../../releases)에서 `PaperBar-vX.Y.Z.zip`을 받아 압축을 풀고 `PaperBar.app`을 `/응용 프로그램`으로 옮기세요.
Apple 공증을 받지 않은 앱이라 처음 실행이 막히면, 앱을 우클릭해서 **열기**를 누르거나 아래를 실행하세요.

```bash
xattr -dr com.apple.quarantine /Applications/PaperBar.app
```

### 직접 빌드
macOS 13 Ventura 이상, Xcode 또는 Command Line Tools(`xcode-select --install`)가 필요해요.

```bash
git clone https://github.com/LucasHyun/PaperBar.git
cd PaperBar
./build.sh --install      # 빌드 → /Applications 설치 → 실행
```

개발 중에는 `swift run`으로 번들 없이 바로 띄울 수 있어요(로그인 시 자동 실행만 비활성). Xcode로 열려면 `open Package.swift`.

## Semantic Scholar API 키 (선택)
키 없이도 동작하지만 모든 비인증 사용자가 한도를 나눠 써서 자주 거절돼요.
[무료 키를 신청](https://www.semanticscholar.org/product/api#api-key-form)한 뒤 ⚙︎ 설정 → Semantic Scholar에 붙여넣으세요.
키는 **macOS 키체인에만** 저장되고 레포나 설정 파일에는 남지 않아요.
직접 빌드하면 새 빌드를 처음 실행할 때 키체인 접근 허용 창이 뜰 수 있어요. *항상 허용*을 누르세요.

## 데이터 소스

| 용도 | 엔드포인트 | 키 |
|---|---|---|
| 트렌딩 | `huggingface.co/api/daily_papers?sort=trending` | 불필요 |
| 검색 | `huggingface.co/api/papers/search?q=…` | 불필요 |
| 키워드 피드 | `export.arxiv.org/api/query?search_query=…&sortBy=submittedDate` | 불필요 |
| HN 화제 | `hn.algolia.com/api/v1/search?query=arxiv.org&restrictSearchableAttributes=url` | 불필요 |
| HN 논문 초록 | `export.arxiv.org/api/query?id_list=…` | 불필요 |
| 인용순 | `api.semanticscholar.org/graph/v1/paper/search/bulk?sort=citationCount:desc` | 권장 |
| 인용수 보강 | `api.semanticscholar.org/graph/v1/paper/batch` | 키 있을 때만 |

각 서비스의 이용 정책을 지키도록 arXiv는 요청 간 3초, Semantic Scholar는 1.1초 간격을 앱 전체에서 유지해요(`RequestPacer`). Hugging Face API는 문서가 얇아서 필드가 빠지거나 이름이 바뀌어도 버티도록 디코더를 짰어요.

## 저장 위치
- 설정·키워드: `UserDefaults` (`com.paperbar.app`)
- 논문 캐시: `~/Library/Application Support/PaperBar/cache.json`
- Semantic Scholar 키: 로그인 키체인, 서비스 이름 `PaperBar`

## 구조
```
Sources/PaperBar/
  PaperBarApp.swift   메뉴바 진입점, 아이콘 배지
  ContentView.swift   메인 창: 검색, 탭, 목록, 논문 행
  SettingsPane.swift  설정 화면
  PaperStore.swift    상태, 매일 갱신 스케줄러, 캐시, 새 논문 추적
  SearchQuery.swift   검색 문법 파서, 단어 경계 매칭, 하이라이트
  Localization.swift  영어 / 한국어 / 중국어(간체) 문구
  HFClient.swift      Hugging Face API
  ArxivClient.swift   arXiv API, Atom 파서, 요청 간격 조절
  HNClient.swift      Hacker News(Algolia) API
  S2Client.swift      Semantic Scholar API
  Keychain.swift      API 키 저장
  Models.swift        Paper 모델, 공용 유틸
```

### 언어 추가하기
`Localization.swift`에서 `AppLanguage`에 케이스를 추가하고, 영어 기본값을 덮어쓰는 `static var` 테이블을 만들면 돼요. 빠뜨린 문구는 영어로 보여요.

## 릴리스 만들기
`v`로 시작하는 태그를 push하면 GitHub Actions가 Apple Silicon·Intel 겸용 앱을 빌드해 Release에 올려요.

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 라이선스
MIT. 논문 메타데이터의 권리는 각 출처(arXiv, Hugging Face, Hacker News, Semantic Scholar)에 있어요.
