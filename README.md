# SwiftUIChatMarkdown

SwiftUIChatMarkdown 是一个专为 **AI 聊天/对话场景优化** 的 SwiftUI Markdown 渲染库。它不仅支持标准的 Markdown 语法，还集成了流式打字机效果、数学公式渲染 (LaTeX)、Mermaid 关系图渲染以及基于 SQLite 的对话历史本地持久化缓存。

## 🌟 核心特性

- 💬 **AI 对话优化**：专为流式文本输出设计的打字机平滑过渡效果（Reveal Effect）。
- 📐 **LaTeX 数学公式**：集成 `SwiftMath`，支持行内和块级数学公式的完美渲染。
- 📊 **Mermaid 图表**：通过 `beautiful-mermaid-swift` 支持流程图、时序图等 Mermaid 语法可视化。
- 💻 **高性能语法高亮**：内置 `ChatCodeHighlighter`，支持代码块的主题高亮和一键复制代码。
- 💾 **SQLite 历史缓存**：内置 `SQLiteChatMessageCache`，自动对消息进行轻量化本地持久化。
- 🎨 **高度可定制主题**：通过 `SDKMarkdownTheme` 自由配置前景色、高亮色、代码背景及多种字体。

## 🛠 环境要求

- **iOS 18.0+**
- **macOS 15.0+**
- **Xcode 16.0+**
- **Swift 6.0**

## 📦 安装指南 (SPM)

在 Xcode 项目中，选择 `File -> Add Package Dependencies`，并输入本项目仓库地址：
`https://github.com/openclaw/SwiftUIChatMarkdown`

或者在您的 `Package.swift` 中添加依赖：
```swift
dependencies: [
    .package(url: "https://github.com/openclaw/SwiftUIChatMarkdown", exact: "1.0.0")
]
```

## 🚀 快速开始

### 1. 实现数据源协议与初始化本地缓存

实现 `ChatSessionDataSource` 协议，以对接您的 AI 对话接口。使用 `SQLiteChatMessageCache` 来保存会话和聊天记录：

```swift
import SwiftUI
import SwiftUIChatMarkdown

// 实现数据源，拉取远端历史记录（按需实现）
class MyChatDataSource: ChatSessionDataSource, @unchecked Sendable {
    func fetchRemoteHistory(sessionKey: String) async throws -> [SDKChatMessage] {
        // 在此处调用 AI 接口的 Chat History API
        return []
    }
}
```

### 2. 在 SwiftUI 中渲染对话流

在您的 View 中初始化 `ChatSessionEngine`，并将其传给 `ChatSessionView`：

```swift
struct ChatRoomView: View {
    @State private var engine: ChatSessionEngine
    
    init() {
        // 1. 初始化 SQLite 缓存路径
        let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_cache.db")
        let cache = SQLiteChatMessageCache(databaseURL: dbURL)
        let dataSource = MyChatDataSource()
        
        // 2. 初始化对话引擎
        _engine = State(initialValue: ChatSessionEngine(
            sessionKey: "current_session_key",
            cache: cache,
            dataSource: dataSource
        ))
    }
    
    var body: some View {
        VStack {
            // 使用 ChatSessionView 渲染对话流
            ChatSessionView(engine: engine)
            
            Divider()
            
            // 示例：测试发送消息
            HStack {
                Button("发送测试消息") {
                    engine.appendUserMessage("你好，请用 LaTeX 公式 $\\sum_{i=1}^n i = \\frac{n(n+1)}{2}$ 解释等差数列求和。")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .task {
            // 3. 载入本地缓存并同步远端记录
            await engine.coldOpen()
            await engine.syncRemote()
        }
    }
}
```

## 📁 目录结构说明

```text
Sources/SwiftUIChatMarkdown/
├── Core/
│   ├── Models.swift          # SDKChatMessage, SDKMarkdownTheme 等模型定义
│   └── Protocols.swift       # ChatSessionDataSource, ChatMessageCache 等协议定义
├── Parser/
│   ├── ChatMarkdownBlockSegmenter.swift # 增量内容分块解析器
│   └── ChatMarkdownPreprocessor.swift   # Markdown 预处理转换
├── UI/
│   ├── ChatSessionView.swift # 聊天会话主 ScrollView
│   ├── ChatSessionEngine.swift # 管理消息状态和流式更新的 Observable 引擎
│   └── ChatMarkdownBlockViews.swift # 渲染各类 Markdown 块的组件
├── Storage/
│   └── SQLiteChatMessageCache.swift # 基于 SQLite 的本地历史记录缓存
└── Highlighting/
    ├── ChatCodeHighlighter.swift # 语法高亮器
    └── ChatInlineMath.swift      # LaTeX 公式高亮和识别
```

## 📄 许可证

本项目采用 MIT 许可证。详情请参阅 [LICENSE](LICENSE)。
