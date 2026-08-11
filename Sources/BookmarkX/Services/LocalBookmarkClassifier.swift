import Foundation

/// Deterministic classifier used for bulk reclassify and as Grok fallback.
/// Scores keyword rules, then resolves the winning category against existing folders
/// so new topics can create folders while near-duplicates reuse existing ones.
enum LocalBookmarkClassifier {
    private struct Rule {
        let folder: String
        let weight: Double
        let keywords: [String]
    }

    /// Canonical folders produced by the local taxonomy (v2).
    static let canonicalFolders: [String] = [
        "人工智能",
        "软件开发",
        "开源项目",
        "前端开发",
        "产品与设计",
        "效率与工具",
        "商业与投资",
        "科技前沿",
        "网络与基础设施",
        "远程与职场",
        "教程与学习",
        "媒体与内容",
        "加密货币",
        "游戏娱乐",
        "生活兴趣",
        "待读"
    ]

    private static let aliases: [String: String] = [
        "ai": "人工智能",
        "artificial intelligence": "人工智能",
        "llm": "人工智能",
        "agent": "人工智能",
        "agents": "人工智能",
        "machine learning": "人工智能",
        "ml": "人工智能",
        "coding": "软件开发",
        "programming": "软件开发",
        "software": "软件开发",
        "dev": "软件开发",
        "development": "软件开发",
        "open source": "开源项目",
        "opensource": "开源项目",
        "github": "开源项目",
        "frontend": "前端开发",
        "front-end": "前端开发",
        "web": "前端开发",
        "design": "产品与设计",
        "product": "产品与设计",
        "ux": "产品与设计",
        "ui": "产品与设计",
        "productivity": "效率与工具",
        "tools": "效率与工具",
        "workflow": "效率与工具",
        "business": "商业与投资",
        "investing": "商业与投资",
        "investment": "商业与投资",
        "finance": "商业与投资",
        "tech": "科技前沿",
        "technology": "科技前沿",
        "hardware": "科技前沿",
        "vpn": "网络与基础设施",
        "vps": "网络与基础设施",
        "networking": "网络与基础设施",
        "remote": "远程与职场",
        "career": "远程与职场",
        "tutorial": "教程与学习",
        "guide": "教程与学习",
        "learning": "教程与学习",
        "media": "媒体与内容",
        "content": "媒体与内容",
        "marketing": "媒体与内容",
        "crypto": "加密货币",
        "web3": "加密货币",
        "bitcoin": "加密货币",
        "gaming": "游戏娱乐",
        "games": "游戏娱乐",
        "life": "生活兴趣",
        "lifestyle": "生活兴趣",
        "inbox": "待读",
        "uncategorized": "待读",
        "misc": "待读"
    ]

    private static let rules: [Rule] = [
        Rule(folder: "人工智能", weight: 3.0, keywords: [
            "人工智能", "大模型", "llm", "chatgpt", "openai", "gpt-", "claude", "anthropic",
            "deepseek", "grok", "gemini", "midjourney", "stable diffusion", "codex", "cursor",
            "agent", "智能体", "skill", "harness", "prompt", "提示词", "aigc", "生成式",
            "机器学习", "machine learning", "neural", "transformer"
        ]),
        Rule(folder: "软件开发", weight: 2.4, keywords: [
            "编程", "代码", "coding", "developer", "开发者", "程序员", "api", "sdk",
            "swift", "swiftui", "xcode", "python", "pytorch", "django", "fastapi",
            "rust", "golang", "java", "kotlin", "refactor", "debug", "测试", "unit test",
            "ci/cd", "docker", "kubernetes", "数据库", "sql", "postgres"
        ]),
        Rule(folder: "开源项目", weight: 2.2, keywords: [
            "开源", "open source", "opensource", "github.com", "github ", "gitlab",
            "pull request", " pr ", "repo", "repository", "mit license"
        ]),
        Rule(folder: "前端开发", weight: 2.2, keywords: [
            "前端", "react", "vue", "next.js", "nextjs", "typescript", "javascript",
            "three.js", "threejs", "css", "tailwind", "webpack", "vite", "html"
        ]),
        Rule(folder: "产品与设计", weight: 2.0, keywords: [
            "产品", "用户体验", "ux", "ui设计", "设计", "figma", "原型", "交互设计",
            "design system", "配图", "画风", "视觉"
        ]),
        Rule(folder: "效率与工具", weight: 2.1, keywords: [
            "效率", "workflow", "自动化", "automation", "模板", "obsidian", "notion",
            "飞书", "插件", "shortcut", "alfred", "raycast", "知识库", "笔记"
        ]),
        Rule(folder: "商业与投资", weight: 2.3, keywords: [
            "投资", "股票", "股价", "估值", "财报", "invest", "stock", "k线", "证券",
            "商业", "创业", "startup", "融资", "营收", "tesla", "tsla", "特斯拉",
            "港股", "美股", "基金"
        ]),
        Rule(folder: "科技前沿", weight: 1.8, keywords: [
            "科技", "technology", "芯片", "半导体", "robot", "机器人", "航天", "spaceX",
            "量子", "硬件", "iphone", "macbook", "nvidia", "gpu"
        ]),
        Rule(folder: "网络与基础设施", weight: 2.4, keywords: [
            "vpn", "vps", "cdn", "云服务器", "代理", "proxy", "v2ray", "clash",
            "shadowsocks", "wireguard", "域名", "dns", "服务器", "带宽", "延迟"
        ]),
        Rule(folder: "远程与职场", weight: 1.9, keywords: [
            "远程", "remote", "居家办公", "职场", "招聘", "面试", "freelance",
            "mac mini", "远控", "办公"
        ]),
        Rule(folder: "教程与学习", weight: 1.9, keywords: [
            "教程", "指南", "how to", "guide", "入门", "从0到1", "手把手",
            "学会", "学习路径", "课程", "cheat sheet"
        ]),
        Rule(folder: "媒体与内容", weight: 2.0, keywords: [
            "小红书", "口播", "seo", "博客", "自媒体", "内容创作", "榜单", "kol",
            "流量", "运营", "短视频", "剪辑", "newsletter", "推特", "twitter growth"
        ]),
        Rule(folder: "加密货币", weight: 2.2, keywords: [
            "crypto", "bitcoin", "btc", "ethereum", "eth", "web3", "nft",
            "区块链", "deFi", "solana", "币安", "交易所"
        ]),
        Rule(folder: "游戏娱乐", weight: 1.7, keywords: [
            "游戏", "game", "steam", "playstation", "xbox", "nintendo", "电竞", "meme"
        ]),
        Rule(folder: "生活兴趣", weight: 1.5, keywords: [
            "生活", "健康", "健身", "旅行", "美食", "读书", "电影", "音乐",
            "风水", "命理", "法术", "摄影"
        ])
    ]

    static func enrich(
        text: String,
        authorUsername: String?,
        existingFolders: [String] = [],
        hasMedia: Bool = false
    ) -> GrokEnrichment {
        let haystack = normalizedHaystack(text: text, authorUsername: authorUsername)
        var tagScores: [(tag: String, score: Double)] = []
        var folderScores: [String: Double] = [:]

        for rule in rules {
            var hitCount = 0
            var matchedTags: [String] = []
            for keyword in rule.keywords where containsTerm(haystack, keyword) {
                hitCount += 1
                let tag = displayTag(for: keyword)
                if !matchedTags.contains(tag) {
                    matchedTags.append(tag)
                }
            }
            guard hitCount > 0 else { continue }
            let score = rule.weight * Double(hitCount)
            folderScores[rule.folder, default: 0] += score
            for tag in matchedTags.prefix(3) {
                if let index = tagScores.firstIndex(where: { $0.tag == tag }) {
                    tagScores[index].score += score
                } else {
                    tagScores.append((tag, score))
                }
            }
        }

        let rankedFolders = folderScores.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }

        let rawCategory: String
        if let best = rankedFolders.first, best.value >= 1.5 {
            rawCategory = best.key
        } else {
            rawCategory = "待读"
        }

        let category = resolveCategory(rawCategory, existingFolders: existingFolders)

        var tags = tagScores
            .sorted { $0.score > $1.score }
            .map(\.tag)
            .filter { $0.caseInsensitiveCompare(category) != .orderedSame }
        if tags.isEmpty {
            tags = [category]
        } else if !tags.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) {
            tags.insert(category, at: 0)
        }
        tags = Array(tags.prefix(5))

        let title = makeTitle(text: text, authorUsername: authorUsername, hasMedia: hasMedia)
        let summary = makeSummary(text: text)

        return GrokEnrichment(
            title: title,
            summary: summary,
            category: category,
            tags: tags,
            model: "local-fallback-v2",
            provider: .xPremium
        )
    }

    /// Placeholder / junk titles produced by older classifiers or empty posts.
    static func isWeakTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lowered = trimmed.lowercased()
        if lowered == "x bookmark" || lowered == "bookmark" || lowered == "untitled" {
            return true
        }
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return true
        }
        if trimmed.count <= 2 { return true }
        let interjections: Set<String> = [
            "卧槽", "我天", "我靠", "我去", "哈哈", "哈哈哈", "嘿", "嗯", "啊", "哦",
            "哇", "唉", "嗯嗯", "好的", "是的", "对", "yes", "ok", "lol", "wtf", "omg"
        ]
        return interjections.contains(lowered) || interjections.contains(trimmed)
    }

    static func makeTitle(text: String, authorUsername: String?, hasMedia: Bool = false) -> String {
        let clean = stripURLs(text)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !clean.isEmpty {
            let sentences = clean
                .split(whereSeparator: { ".!?。！？\n".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for sentence in sentences {
                if !isWeakTitle(sentence) {
                    return String(sentence.prefix(80))
                }
            }
            if clean.count >= 3 {
                return String(clean.prefix(80))
            }
        }

        let handle = authorUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if hasMedia {
            return handle.isEmpty ? "媒体分享" : "媒体分享 · @\(handle)"
        }
        if text.range(of: #"https?://"#, options: .regularExpression) != nil {
            return handle.isEmpty ? "链接分享" : "链接分享 · @\(handle)"
        }
        return handle.isEmpty ? "未命名书签" : "@\(handle) 的书签"
    }

    static func makeSummary(text: String) -> String {
        let clean = stripURLs(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            return String(clean.prefix(220))
        }
        // Pure link / media posts — don't surface raw t.co as the summary.
        if text.range(of: #"https?://"#, options: .regularExpression) != nil {
            return "（无文字，仅链接或媒体）"
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "（无文字内容）" : String(trimmed.prefix(220))
    }

    private static func stripURLs(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"https?://\S+"#,
            with: "",
            options: .regularExpression
        )
    }

    /// Map a proposed category onto an existing folder when possible; otherwise keep it
    /// so folders can grow from new topics.
    static func resolveCategory(_ proposed: String, existingFolders: [String]) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "待读" }

        let lowered = trimmed.lowercased()
        if let existing = existingFolders.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }

        if let alias = aliases[lowered] {
            if let existing = existingFolders.first(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
                return existing
            }
            return alias
        }

        // Prefer an existing folder that contains / is contained by the proposal.
        if let fuzzy = existingFolders.first(where: {
            let name = $0.lowercased()
            return name.contains(lowered) || lowered.contains(name)
        }), fuzzy.count >= 2 {
            return fuzzy
        }

        return trimmed
    }

    private static func normalizedHaystack(text: String, authorUsername: String?) -> String {
        var parts = [text.lowercased()]
        if let authorUsername, !authorUsername.isEmpty {
            parts.append("@\(authorUsername.lowercased())")
        }
        // Pad so short tokens like "ai" can be matched with spaces.
        return " " + parts.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            + " "
    }

    private static func containsTerm(_ haystack: String, _ keyword: String) -> Bool {
        let needle = keyword.lowercased()
        if needle.hasPrefix(" ") || needle.hasSuffix(" ") || needle.contains(" ") {
            return haystack.contains(needle)
        }
        if needle.count <= 3 {
            // Short tokens: require non-letter boundaries to reduce false positives.
            let pattern = #"(?<![a-z0-9\u4e00-\u9fff])"#
                + NSRegularExpression.escapedPattern(for: needle)
                + #"(?![a-z0-9\u4e00-\u9fff])"#
            return haystack.range(of: pattern, options: .regularExpression) != nil
        }
        return haystack.contains(needle)
    }

    private static func displayTag(for keyword: String) -> String {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "ai", "llm", "人工智能", "大模型", "生成式", "aigc":
            return "人工智能"
        case "chatgpt", "openai", "gpt-":
            return "ChatGPT"
        case "claude", "anthropic":
            return "Claude"
        case "deepseek":
            return "DeepSeek"
        case "grok":
            return "Grok"
        case "codex", "cursor", "skill", "harness", "agent", "智能体", "prompt", "提示词":
            return "Agent"
        case "swift", "swiftui", "xcode":
            return "Swift"
        case "python", "pytorch", "django", "fastapi":
            return "Python"
        case "react", "vue", "typescript", "javascript", "three.js", "threejs", "前端":
            return "前端"
        case "github.com", "github ", "开源", "open source", "opensource":
            return "开源"
        case "vpn", "vps", "v2ray", "clash", "代理":
            return "网络"
        case "obsidian", "notion", "飞书", "效率", "自动化":
            return "效率工具"
        case "小红书", "seo", "口播", "榜单", "kol":
            return "内容"
        case "投资", "股票", "k线", "财报", "stock":
            return "投资"
        default:
            return String(trimmed.prefix(12))
        }
    }
}
