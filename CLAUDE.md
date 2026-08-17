# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

SwiftUIChatMarkdown is a SwiftUI Markdown rendering library optimized for AI chat streaming. It supports a typewriter reveal effect for streaming output, LaTeX math (SwiftMath), Mermaid diagrams, custom syntax highlighting, and SQLite-backed chat history caching. Documentation (README) is in Chinese; code comments are in English.

## Commands

```bash
swift build          # build the package
swift test           # run all tests (XCTest target in Tests/SwiftUIChatMarkdownTests)
swift test --filter ParserTests                      # run one test class
swift test --filter ParserTests/testPreprocessorInlineImage   # run one test
```

- Swift 6.0 tools version (toolchain 6.2.4 works); platforms: iOS 18+, macOS 15+.
- Tests run on macOS host by default. UI-layer types are `@MainActor`; test files use `@MainActor` test methods where needed.
- There is no linter/formatter configured; match the existing style (4-space indent, no semicolons).

## Architecture

The rendering pipeline flows in one direction:

```
SDKChatMessage (engine) → ChatSessionView → ChatMarkdownRenderer
    → ChatMarkdownPreprocessor → ChatMarkdownBlockSegmenter → block views
```

### State & session layer (UI/)

- `ChatSessionEngine` (`@Observable`, `@MainActor`): owns `messages: [SDKChatMessage]`, streaming appends (`appendStreamChunk` appends to the *last* text content node), and the cold-open/local-cache + remote-sync lifecycle. All mutations happen on the main actor.
- `ChatSessionView`: ScrollView + LazyVStack over messages; auto-scrolls to the newest message; per-message "查看原文/复制全文" raw-source toggle. Incomplete assistant messages render through `ChatStreamingAssistantTextBody` (reveal effect) instead of the full renderer.

### Parsing pipeline (Parser/)

- `ChatMarkdownPreprocessor`: runs first on raw text. Strips YAML frontmatter, `[message_id: ...]` hint lines, and leading `[Mon 2026-.. GMT+8]`-style timestamps; fixes bold/emphasis punctuation spacing; extracts base64 `data:image` inline images out of the markdown (returned separately, rendered as `InlineImageList`); normalizes newlines. Keep this order in mind when adding preprocess steps — image extraction happens after punctuation fixes.
- `ChatMarkdownBlockSegmenter`: parses with swift-markdown (`Document(parsing:)`) and extracts only **top-level** blocks into `ChatMarkdownBlock` (prose/header/list/blockquote/code/math/table/thematicBreak). Container and reference semantics stay with the swift-markdown parser; nested blocks remain inside the surrounding prose range.
- Hard limits guard streaming performance: `maxMathBytes` (5000), `maxTableBytes/Rows/Columns/Cells`. Oversized tables fall back to prose (covered by tests).
- `isComplete` propagation is the core streaming contract: open code fences and unclosed math delimiters render as plain mono text (cheap) while `isComplete == false`, and upgrade to highlighted/rendered views once closed or the message completes.

### Rendering (UI/ChatMarkdownBlockViews.swift)

- `ChatMarkdownRenderer` switches over `ChatMarkdownRenderedBlock`. Prose/header/blockquote/list use the `AttributedString` pipeline (`ChatMarkdownProse`); code/math/table get dedicated views (`ChatCodeBlockView`, `ChatMathBlockView`, `ChatMarkdownTableView`).
- Mermaid: `ChatCodeBlockView` renders `MermaidDiagramView` when `language == "mermaid"` **and** `isComplete`.
- The typewriter effect works via `ChatMarkdownProseReveal` / `ChatStreamingRevealState`: per-block revealed text with opacity frames.
- Expensive work is memoized in three static caches: `ChatCodeHighlightCache`, `ChatMathParseCache` (also used as a validity check before rendering math), and `ChatInlineMathImageCache` (rasterized inline math images at screen scale). Inline math in prose is scanned by `ChatInlineMathScanner`.

### Highlighting (Highlighting/)

- `ChatCodeHighlighter`: custom regex/keyword-based tokenizer (no third-party highlighter) producing `ChatCodeToken` runs colored via `SDKMarkdownTheme`.

### Storage (Storage/)

- `SQLiteChatMessageCache`: a `public actor` implementing `ChatMessageCache` (C API SQLite3). Binary attachment `data` is stripped before DB writes to keep rows light; text content is persisted.
- `ChatSessionDataSource` and `ChatMessageCache` (Core/Protocols.swift) are the integration points for host apps; both require `Sendable` since they run across actors.

### Cross-platform

iOS/macOS differences are handled via `#if os(macOS)` blocks and the `SDKPlatformImage` typealias (NSImage/UIImage) in Core/Models.swift. `SDKMarkdownTheme.adaptive(light:dark:)` builds dynamic colors for both platforms.

## Concurrency

The package is built with Swift 6 strict concurrency: views and the engine are `@MainActor`, caches are static enums with internal locking (or actors), and public model types are `Sendable`/`Codable`. Preserve these annotations when adding API.
