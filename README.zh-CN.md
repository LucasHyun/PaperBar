# PaperBar

[English](README.md) · [한국어](README.ko.md) · **简体中文**

一个小巧的 macOS 菜单栏应用，每天从 Hugging Face、Hacker News、Semantic Scholar 和 arXiv 收集热门机器学习论文，并按你保存的关键词在标题和**摘要**中筛选。完全在本机运行，不需要服务器。

## 功能

| 标签 | 内容 | 来源 |
|---|---|---|
| HF 热门 | 今日点赞最多的 50 篇论文 | Hugging Face Daily Papers |
| HN 热议 | 近 7 天发到 Hacker News 的 arXiv 论文，按分数排序 | HN Algolia API + arXiv |
| 高引用 | 近 30–180 天论文按引用数排序。有关键词时按关键词，否则覆盖整个计算机科学 | Semantic Scholar |
| 关键词标签 | 每个已保存关键词的最新论文 | Hugging Face 搜索 + arXiv 最新提交 |

- **连摘要一起筛选。** 在标题、摘要、AI 摘要、关键词和作者中查找，并高亮显示摘要中匹配的位置。
- **检索语法。** 空格表示 AND，`"world model"` 匹配短语（也能匹配 `world-model`），`-robot` 表示排除。英文按词首匹配，所以 `agent` 能匹配 *agents*，而 `RL` 不会匹配 *world*。中日韩文字不要求词边界。关键词也使用同样的语法。
- **严格筛选。** Hugging Face 的搜索基于语义，会返回不含关键词的论文；严格筛选会把它们隐藏（可关闭）。
- **每日自动更新。** 在你设定的时间（默认 09:00）之后以及 Mac 唤醒时更新，菜单栏图标显示尚未查看的新论文数量。
- **引用数。** 填入 Semantic Scholar API 密钥后，所有标签的论文都会显示引用数，并可按引用排序。
- **English、한국어、简体中文。** 默认跟随系统语言，也可以在设置中手动选择。

## 安装

### 下载发布版
从 [Releases](../../releases) 下载 `PaperBar-vX.Y.Z.zip`，解压后把 `PaperBar.app` 移到“应用程序”文件夹。
本应用未经 Apple 公证。如果首次打开被拦截，请右键点击应用并选择**打开**，或运行：

```bash
xattr -dr com.apple.quarantine /Applications/PaperBar.app
```

### 从源码构建
需要 macOS 13 Ventura 或更高版本，以及 Xcode 或命令行工具（`xcode-select --install`）。

```bash
git clone https://github.com/LucasHyun/PaperBar.git
cd PaperBar
./build.sh --install      # 构建、复制到 /Applications 并启动
```

开发时可以用 `swift run` 直接启动（仅“登录时自动打开”不可用）。如需使用 Xcode，运行 `open Package.swift`。

## Semantic Scholar API 密钥（可选）
不填密钥也能使用，但所有匿名用户共享同一限额，请求经常被拒绝。
[申请免费密钥](https://www.semanticscholar.org/product/api#api-key-form)后，粘贴到 ⚙︎ 设置 → Semantic Scholar。
密钥**只保存在 macOS 钥匙串中**，不会出现在仓库或配置文件里。
如果从源码构建，新版本首次运行时系统可能会请求钥匙串访问权限，请选择“始终允许”。

## 数据来源

| 用途 | 接口 | 密钥 |
|---|---|---|
| 热门 | `huggingface.co/api/daily_papers?sort=trending` | 不需要 |
| 搜索 | `huggingface.co/api/papers/search?q=…` | 不需要 |
| 关键词订阅 | `export.arxiv.org/api/query?search_query=…&sortBy=submittedDate` | 不需要 |
| HN 热议 | `hn.algolia.com/api/v1/search?query=arxiv.org&restrictSearchableAttributes=url` | 不需要 |
| HN 论文摘要 | `export.arxiv.org/api/query?id_list=…` | 不需要 |
| 高引用 | `api.semanticscholar.org/graph/v1/paper/search/bulk?sort=citationCount:desc` | 建议 |
| 引用数补充 | `api.semanticscholar.org/graph/v1/paper/batch` | 仅在有密钥时 |

为遵守各服务的使用政策，应用全局保持 arXiv 请求间隔 3 秒、Semantic Scholar 请求间隔 1.1 秒（`RequestPacer`）。Hugging Face API 文档较少，解码器能容忍字段缺失或改名。

## 数据存放位置
- 设置和关键词：`UserDefaults`（`com.paperbar.app`）
- 论文缓存：`~/Library/Application Support/PaperBar/cache.json`
- Semantic Scholar 密钥：登录钥匙串，服务名 `PaperBar`

## 项目结构
```
Sources/PaperBar/
  PaperBarApp.swift   菜单栏入口和角标
  ContentView.swift   主窗口：搜索、标签、列表、论文行
  SettingsPane.swift  设置界面
  PaperStore.swift    状态、每日调度、缓存、新论文追踪
  SearchQuery.swift   检索语法解析、词边界匹配、高亮
  Localization.swift  英语 / 韩语 / 简体中文文案
  HFClient.swift      Hugging Face API
  ArxivClient.swift   arXiv API、Atom 解析、请求节流
  HNClient.swift      Hacker News（Algolia）API
  S2Client.swift      Semantic Scholar API
  Keychain.swift      API 密钥存储
  Models.swift        Paper 模型和通用工具
```

### 添加新语言
在 `Localization.swift` 中为 `AppLanguage` 添加一个 case，并新建一个覆盖英文默认值的 `static var` 文案表。未翻译的文案会显示英文。

## 发布
推送以 `v` 开头的标签后，GitHub Actions 会构建通用版（Apple 芯片 + Intel）应用并附加到 Release。

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 许可证
MIT。论文元数据的权利归各来源（arXiv、Hugging Face、Hacker News、Semantic Scholar）所有。
