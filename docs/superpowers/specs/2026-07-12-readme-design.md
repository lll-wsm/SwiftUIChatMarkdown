# 设计规约：添加 README.md 描述文档

*   **文档日期**: 2026-07-12
*   **目标文件**: [README.md](file:///Users/lll/Projects.localized/AgentsProjects/openclaw-main/SwiftUIChatMarkdown/README.md)
*   **语言**: 简体中文 (Chinese)

## 1. 目标
为 `SwiftUIChatMarkdown` 库创建一个结构清晰、信息完整的 `README.md`，使开发者能够快速了解此库的核心特性，并在一分钟内通过 SPM 安装并在 SwiftUI 项目中接入。

## 2. 核心架构与功能描述
README 中将包含以下核心特性介绍：
*   **流式打字机效果**：通过 `ChatMarkdownBlockSegmenter` 和 `ChatStreamingRevealState` 实现的 AI 打字机平滑过渡（Reveal Effect）效果。
*   **LaTeX 渲染**：利用 `SwiftMath` 支持行内公式和独立块级公式渲染。
*   **Mermaid 图表**：通过 `beautiful-mermaid-swift` 支持时序图、流程图渲染。
*   **代码高亮**：提供包含自动识别语言与一键复制功能的高性能代码块渲染。
*   **SQLite 本地缓存**：利用 `SQLiteChatMessageCache` 对会话列表及历史消息载体（限制 200 条并自动剔除 binary data 以减负）进行持久化。

## 3. 安装与使用示例 (Quick Start)
设计一段完整的、可直接运行的代码示例。例如：

```swift
import SwiftUI
import SwiftUIChatMarkdown

// 1. 实现数据源协议
class MyChatDataSource: ChatSessionDataSource, @unchecked Sendable {
    func fetchRemoteHistory(sessionKey: String) async throws -> [SDKChatMessage] {
        // 从您的 AI API 接口拉取历史记录
        return []
    }
}

// 2. 初始化 View
struct ChatRoomView: View {
    @State private var engine: ChatSessionEngine
    
    init() {
        let cache = SQLiteChatMessageCache(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("chat.db"))
        let dataSource = MyChatDataSource()
        
        _engine = State(initialValue: ChatSessionEngine(
            sessionKey: "session_123",
            cache: cache,
            dataSource: dataSource
        ))
    }
    
    var body: some View {
        VStack {
            ChatSessionView(engine: engine)
            
            Button("发送测试消息") {
                engine.appendUserMessage("你好，请用数学公式 $\\sum_{i=1}^n i = \\frac{n(n+1)}{2}$ 解释等差数列求和。")
            }
            .padding()
        }
        .task {
            // 加载本地缓存并同步远端历史记录
            await engine.coldOpen()
            await engine.syncRemote()
        }
    }
}
```

## 4. 目录结构大纲
*   `Core`: `SDKChatMessage`、`SDKChatMessageContent`、`SDKMarkdownTheme`
*   `Parser`: `ChatMarkdownBlockSegmenter`、`ChatMarkdownPreprocessor`
*   `UI`: `ChatSessionView`、`ChatSessionEngine`
*   `Storage`: `SQLiteChatMessageCache`
*   `Highlighting`: `ChatCodeHighlighter`、`ChatInlineMath`
