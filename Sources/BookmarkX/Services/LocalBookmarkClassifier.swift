import Foundation

/// Deterministic fallback when X Premium's undocumented Grok endpoint changes.
/// Uses a small canonical taxonomy so equivalent terms converge on the same tags.
enum LocalBookmarkClassifier {
    static func enrich(
        text: String,
        authorUsername: String?
    ) -> GrokEnrichment {
        let normalized = text.lowercased()
        var tags: [String] = []

        func add(_ tag: String, when terms: [String]) {
            guard terms.contains(where: normalized.contains), !tags.contains(tag) else { return }
            tags.append(tag)
        }

        add("人工智能", when: [" ai ", "ai驱动", "人工智能", "llm", "大模型"])
        add("Grok", when: ["grok"])
        add("ChatGPT", when: ["chatgpt", "openai", "gpt-"])
        add("Claude", when: ["claude", "anthropic"])
        add("DeepSeek", when: ["deepseek"])
        add("Agent", when: ["agent", "智能体"])
        add("编程", when: ["代码", "编程", "coding", "developer", "开发"])
        add("Swift", when: ["swiftui", "swift ", "xcode", "ios ", "macos"])
        add("Python", when: ["python", "pytorch", "django", "fastapi"])
        add("前端", when: ["react", "vue", "typescript", "javascript", "前端"])
        add("开源", when: ["github.com", "open source", "opensource", "开源"])
        add("产品", when: ["产品", "product", "用户体验", "ux"])
        add("设计", when: ["设计", "design", "figma", "ui "])
        add("效率工具", when: ["效率", "workflow", "自动化", "automation", "模板"])
        add("投资", when: ["投资", "股票", "股价", "估值", "财报", "invest", "stock"])
        add("Tesla", when: ["tesla", "tsla", "特斯拉"])
        add("商业", when: ["商业", "创业", "公司", "business", "startup"])
        add("科技", when: ["科技", "technology", "芯片", "robot", "机器人"])
        add("远程工作", when: ["远程", "remote", "mac mini", "远控"])
        add("教程", when: ["教程", "指南", "how to", "guide", "入门"])

        let category: String
        if tags.contains(where: { ["人工智能", "Grok", "ChatGPT", "Claude", "DeepSeek", "Agent"].contains($0) }) {
            category = "人工智能"
        } else if tags.contains(where: { ["编程", "Swift", "Python", "前端", "开源"].contains($0) }) {
            category = "软件开发"
        } else if tags.contains(where: { ["投资", "Tesla", "商业"].contains($0) }) {
            category = "商业与投资"
        } else if tags.contains(where: { ["产品", "设计"].contains($0) }) {
            category = "产品与设计"
        } else if tags.contains("效率工具") || tags.contains("远程工作") {
            category = "效率与工具"
        } else if tags.contains("科技") {
            category = "科技"
        } else {
            category = "待读"
        }

        if tags.isEmpty {
            tags = [category]
        } else if !tags.contains(category) {
            tags.insert(category, at: 0)
        }

        let cleanText = text
            .replacingOccurrences(
                of: #"https?://\S+"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSentence = cleanText
            .split(whereSeparator: { ".!?。！？\n".contains($0) })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String((firstSentence?.isEmpty == false ? firstSentence! : cleanText).prefix(80))
        let summary = String(cleanText.prefix(220))

        return GrokEnrichment(
            title: title.isEmpty ? "X Bookmark" : title,
            summary: summary.isEmpty ? text : summary,
            category: category,
            tags: Array(tags.prefix(5)),
            model: "local-fallback-v1",
            provider: .xPremium
        )
    }
}
