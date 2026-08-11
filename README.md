# BookmarkX

> 本地优先的 X（Twitter）书签管理 macOS 应用 —— 用 Grok 把你的书签变成个人知识库。
>
> A local-first macOS app that turns your X (Twitter) bookmarks into a personal knowledge base, powered by Grok.

## 为什么做 BookmarkX

X 内置的书签只是一个扁平列表：不能搜索、不能分类、不能导出，推文删了收藏就没了。BookmarkX 把你的书签全量同步到本地 SQLite 数据库，用 Grok 模型自动分类、生成摘要、打标签，让收藏真正可检索、可整理、可沉淀。

## 核心特性

- **书签全量备份**：一键把 X 书签同步到本地，增量更新，推文被删也不丢失
- **Grok 智能整理**：自动分类、自动生成内容摘要、自动打标签，结果均可人工编辑
- **本地优先**：数据只存在你 Mac 上的 SQLite 数据库中，不上云、无追踪
- **组织自由**：无限层级文件夹、拖拽移动、彩色标签、批量操作、个人备注
- **毫秒级全文搜索**：基于 SQLite FTS5，支持中英日等多语言，按作者 / 日期 / 媒体类型 / 标签组合筛选
- **多格式导出**：Markdown（兼容 Obsidian）/ CSV / JSON
- **多语言界面**：简体中文、English（持续扩展）
- **集成登录**：支持 X Premium Grok 额度、xAI API Key，以及自动优先 Premium / 回退 API Key；凭证存入 macOS Keychain

## 技术栈

| 组件 | 选型 |
| --- | --- |
| 应用框架 | Swift + SwiftUI（macOS 14+） |
| 数据库 | SQLite（GRDB.swift）+ FTS5 全文索引 |
| AI 模型 | Grok：X Premium 额度 / xAI API Key / 自动 |
| X 数据 | X API v2（OAuth 2.0 PKCE） |
| 凭证存储 | macOS Keychain |

## 项目状态

🚧 **开发中（v1.0 尚未发布）**

- [x] M1 骨架：SwiftUI App、SQLite/GRDB Schema、FTS5、Keychain、中英文本地化、基础界面
- [ ] M1 后续：X OAuth 登录与书签同步
- [ ] M2：书签列表增强 / 详情编辑 / 拖拽整理
- [ ] M3：Grok 自动分类、摘要、打标
- [ ] M4：导出、打磨与发布 v1.0

详细规划见 [PRD.md](./PRD.md)。

## 快速开始（开发者）

要求：macOS 14+、Xcode 16+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/williamyangcn/BookmarkX.git
cd BookmarkX
./Scripts/generate.sh
open BookmarkX.xcodeproj
```

如果本机 `xcode-select` 仍指向 Command Line Tools，可临时：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

运行测试：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -scheme BookmarkX -destination 'platform=macOS' test
```

运行前你需要准备：

1. **X API 凭证**：在 [X Developer Portal](https://developer.x.com/) 创建 OAuth 2.0 Native App，权限选择 Read，启用 `tweet.read users.read bookmark.read offline.access`，回调地址填写 `bookmarkx://oauth/x/callback`，然后把 Client ID 填入 App 设置页
2. **Grok（三选一）**：
   - **X Premium Grok**：连接 X 后使用会员自带额度
   - **xAI API Key**：在 [xAI Console](https://console.x.ai/) 创建 Key（单独计费）
   - **自动**：优先 Premium，失败则回退 API Key

X 与 Grok 凭证均存入 macOS Keychain。设置页可一键测试 Grok。可用工具栏「添加示例」验证本地数据库与界面。

## 隐私

- 所有书签数据仅存储在本地
- 网络请求仅用于：X 书签同步、Grok API 调用
- 无任何统计或追踪 SDK
- 数据随时可导出、可删除

## License

[MIT](./LICENSE)
