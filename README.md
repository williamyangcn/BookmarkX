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
- **集成登录**：X 账号授权 + Grok（xAI）模型接入，凭证存储于 macOS Keychain

## 技术栈

| 组件 | 选型 |
| --- | --- |
| 应用框架 | Swift + SwiftUI（macOS 14+） |
| 数据库 | SQLite（GRDB.swift）+ FTS5 全文索引 |
| AI 模型 | xAI Grok API |
| X 数据 | X API v2（OAuth 2.0 PKCE） |
| 凭证存储 | macOS Keychain |

## 项目状态

🚧 **开发中（v1.0 尚未发布）**

- [ ] M1：项目骨架、数据库 Schema、X 登录与书签同步
- [ ] M2：书签列表 / 详情 / 搜索 / 文件夹与标签管理
- [ ] M3：Grok 集成：自动分类、摘要、打标
- [ ] M4：导出、多语言、设置页、发布 v1.0

详细规划见 [PRD.md](./PRD.md)。

## 快速开始（开发者）

```bash
git clone https://github.com/williamyangcn/BookmarkX.git
cd BookmarkX
# Xcode 项目搭建中，敬请期待
```

运行前你需要准备：

1. **X API 凭证**：在 [X Developer Portal](https://developer.x.com/) 创建应用，获取 OAuth 2.0 Client ID
2. **Grok API Key**：在 [xAI Console](https://console.x.ai/) 创建 API Key（支持用 X 账号登录）

## 隐私

- 所有书签数据仅存储在本地
- 网络请求仅用于：X 书签同步、Grok API 调用
- 无任何统计或追踪 SDK
- 数据随时可导出、可删除

## License

[MIT](./LICENSE)
