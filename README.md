# BookmarkX

[English](#english) · [中文](#中文)

Local-first macOS app for X (Twitter) bookmarks — sync, organize, search, and summarize with Grok.

本地优先的 X（Twitter）书签管理 macOS 应用：同步、整理、搜索，并用 Grok 自动摘要与分类。

<p>
  <a href="https://github.com/williamyangcn/BookmarkX/releases/latest">
    <img alt="Download DMG" src="https://img.shields.io/badge/Download-DMG-0A84FF?style=for-the-badge&logo=apple&logoColor=white" />
  </a>
  &nbsp;
  <a href="https://github.com/williamyangcn/BookmarkX/releases">
    <img alt="GitHub Releases" src="https://img.shields.io/github/v/release/williamyangcn/BookmarkX?style=for-the-badge&label=Releases" />
  </a>
  &nbsp;
  <a href="./LICENSE">
    <img alt="MIT License" src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" />
  </a>
</p>

---

## English

### Download

**macOS 14+ (Apple Silicon / Intel)**

| Package | Link |
| --- | --- |
| **Latest DMG** | [Download from GitHub Releases](https://github.com/williamyangcn/BookmarkX/releases/latest) |
| All versions | [Releases page](https://github.com/williamyangcn/BookmarkX/releases) |

1. Open the `.dmg` and drag **BookmarkX** into **Applications**.
2. On first launch, macOS may ask you to allow an unsigned/ad-hoc build: **System Settings → Privacy & Security → Open Anyway**.
3. Sign in with X inside the app, then click **Refresh** to sync bookmarks.

> If the latest release has no DMG asset yet, build one locally with `./Scripts/package-dmg.sh` (see below), or wait for the next published release.

### What it does

- Sync X bookmarks to a local SQLite database (IMAP-style: skip already synced, fetch up to 100 new ones per refresh)
- Four-column layout: shortcuts · folders · list · X post preview
- Unread workflow: read after 30s (font thins, count updates); next time you open Unread, read items move to Archive
- Group list by post time: Today / Yesterday / 7 days / 15 days / 1 month / This year / Last year…
- Importance, favorites, archive, delete (local or local + X)
- Grok enrichment: title, summary, category folder, tags (Premium quota, API key, or Auto)
- Full-text search (FTS5)
- UI languages: English and Simplified Chinese

### Requirements

- macOS 14 Sonoma or later
- An X account (in-app web login; no Developer Client ID required for the default path)
- Optional: X Premium for Grok quota, or an [xAI API Key](https://console.x.ai/)

### Build from source

```bash
git clone https://github.com/williamyangcn/BookmarkX.git
cd BookmarkX
./Scripts/generate.sh          # needs XcodeGen
open BookmarkX.xcodeproj
```

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -scheme BookmarkX -destination 'platform=macOS' test
```

### Package a DMG

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./Scripts/package-dmg.sh          # → dist/BookmarkX-<version>.dmg
./Scripts/package-dmg.sh 0.1.0    # optional version tag
```

Upload the DMG on [GitHub Releases](https://github.com/williamyangcn/BookmarkX/releases/new) so the Download badge above points at a real file.

### Privacy

- Bookmarks stay on your Mac (SQLite)
- Network use is limited to X sync / login and Grok calls
- No analytics SDK
- You can delete local data anytime

### License

[MIT](./LICENSE)

---

## 中文

### 下载

**macOS 14+（Apple Silicon / Intel）**

| 安装包 | 链接 |
| --- | --- |
| **最新 DMG** | [从 GitHub Releases 下载](https://github.com/williamyangcn/BookmarkX/releases/latest) |
| 历史版本 | [Releases 页面](https://github.com/williamyangcn/BookmarkX/releases) |

1. 打开 `.dmg`，把 **BookmarkX** 拖进 **应用程序**。
2. 首次打开若被拦截：系统设置 → 隐私与安全性 → 仍要打开（当前为 ad-hoc 签名）。
3. 在应用内用 X 登录，然后点 **刷新** 同步书签。

> 若最新 Release 还没有 DMG 附件，可先用 `./Scripts/package-dmg.sh` 本地打包，或等下一版发布。

### 功能

- 将 X 书签同步到本地 SQLite（类似 IMAP：跳过已同步，每次刷新最多新抓 100 条）
- 四栏界面：快捷方式 · 文件夹 · 列表 · X 帖子预览
- 未读流程：预览约 30 秒标为已读（字体变细、角标变化）；再次进入「未读」时，已读自动进入归档
- 按发帖时间分组：今天 / 昨天 / 7 天内 / 15 天内 / 1 个月内 / 今年 / 去年…
- 重要程度、收藏、归档、删除（仅本地或本地+X）
- Grok 整理：标题、摘要、分类文件夹、标签（Premium 额度 / API Key / 自动）
- FTS5 全文搜索
- 界面语言：简体中文、English

### 运行要求

- macOS 14 Sonoma 或更高
- X 账号（默认应用内网页登录，无需 Developer Client ID）
- 可选：X Premium（Grok 额度），或 [xAI API Key](https://console.x.ai/)

### 从源码构建

```bash
git clone https://github.com/williamyangcn/BookmarkX.git
cd BookmarkX
./Scripts/generate.sh          # 需要安装 XcodeGen
open BookmarkX.xcodeproj
```

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -scheme BookmarkX -destination 'platform=macOS' test
```

### 打包 DMG

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./Scripts/package-dmg.sh          # 输出 dist/BookmarkX-<version>.dmg
./Scripts/package-dmg.sh 0.1.0    # 可指定版本号
```

把生成的 DMG 上传到 [GitHub Releases](https://github.com/williamyangcn/BookmarkX/releases/new)，上方下载按钮即可指向真实安装包。

### 隐私

- 书签只存在你的 Mac（SQLite）
- 网络请求仅用于 X 同步/登录与 Grok 调用
- 无统计或追踪 SDK
- 可随时删除本地数据

### 许可证

[MIT](./LICENSE)
