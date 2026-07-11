import SwiftUI

@MainActor
public struct ChatSessionView: View {
    private let engine: ChatSessionEngine
    private let theme: SDKMarkdownTheme
    
    @State private var showRawSources: Set<UUID> = []
    @State private var copiedMessageIds: Set<UUID> = []

    public init(engine: ChatSessionEngine, theme: SDKMarkdownTheme = .default) {
        self.engine = engine
        self.theme = theme
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(engine.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: engine.messages) { _, newMessages in
                if let lastMessage = newMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: SDKChatMessage) -> some View {
        if message.role == "user" {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("User")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading) {
                        ForEach(message.content.indices, id: \.self) { index in
                            let part = message.content[index]
                            if part.type == "text", let text = part.text {
                                ChatMarkdownRenderer(
                                    text: text,
                                    context: .user,
                                    variant: .standard,
                                    theme: theme,
                                    isComplete: true
                                )
                            }
                        }
                    }
                    .padding(12)
                    .background(theme.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Assistant")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if message.isComplete {
                        HStack(spacing: 12) {
                            Button(action: {
                                let textToCopy = self.fullMessageText(message)
                                self.copyToClipboard(textToCopy)
                                self.copiedMessageIds.insert(message.id)
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    self.copiedMessageIds.remove(message.id)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedMessageIds.contains(message.id) ? "checkmark" : "doc.on.doc")
                                    Text(copiedMessageIds.contains(message.id) ? "已复制" : "复制全文")
                                }
                                .font(.caption2)
                                .foregroundStyle(copiedMessageIds.contains(message.id) ? .green : theme.accentColor)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                if showRawSources.contains(message.id) {
                                    showRawSources.remove(message.id)
                                } else {
                                    showRawSources.insert(message.id)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: showRawSources.contains(message.id) ? "eye.fill" : "code.horizontal")
                                    Text(showRawSources.contains(message.id) ? "显示排版" : "查看原文")
                                }
                                .font(.caption2)
                                .foregroundStyle(theme.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(message.content.indices, id: \.self) { index in
                        let part = message.content[index]
                        if part.type == "text", let text = part.text {
                            if showRawSources.contains(message.id) {
                                ScrollView(.horizontal, showsIndicators: true) {
                                    Text(text)
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(theme.textColor)
                                        .textSelection(.enabled)
                                        .padding(.vertical, 4)
                                }
                            } else {
                                if !message.isComplete {
                                    ChatStreamingAssistantTextBody(text: text, theme: theme)
                                } else {
                                    ChatMarkdownRenderer(
                                        text: text,
                                        context: .assistant,
                                        variant: .standard,
                                        theme: theme,
                                        isComplete: true
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(theme.codeBackgroundColor.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func fullMessageText(_ message: SDKChatMessage) -> String {
        message.content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined(separator: "\n")
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
        #endif
    }
}

private struct ChatStreamingAssistantTextBody: View {
    let text: String
    let theme: SDKMarkdownTheme
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: Snapshot
    @State private var revealState: ChatStreamingRevealState
    @State private var revealLocation: Snapshot.ProseLocation?
    @State private var pendingUntil: TimeInterval?

    init(text: String, theme: SDKMarkdownTheme) {
        self.text = text
        self.theme = theme
        
        let now = Date.timeIntervalSinceReferenceDate
        let snapshot = Snapshot(text: text)
        let location = snapshot.lastProseLocation
        let revealState = location.map {
            step(state: ChatStreamingRevealState(), newText: snapshot.prose(at: $0).plainText, now: now)
        } ?? ChatStreamingRevealState()
        
        self._snapshot = State(initialValue: snapshot)
        self._revealState = State(initialValue: revealState)
        self._revealLocation = State(initialValue: location)
        self._pendingUntil = State(initialValue: revealState.latestDeadline)
    }

    var body: some View {
        Group {
            if self.reduceMotion || self.pendingUntil == nil {
                self.render(now: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    self.render(now: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .onChange(of: self.text) { _, _ in
            self.updateSnapshot()
        }
        .onChange(of: self.reduceMotion) { _, reduceMotion in
            self.pendingUntil = reduceMotion ? nil : self.futureDeadline()
        }
        .onAppear {
            if self.snapshot.sourceText != self.text {
                self.updateSnapshot()
            }
        }
        .task(id: self.pendingUntil) {
            guard let pendingUntil = self.pendingUntil else { return }
            let delay = max(0, pendingUntil - Date.timeIntervalSinceReferenceDate)
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, self.pendingUntil == pendingUntil else { return }
            self.pendingUntil = nil
        }
    }

    private func render(now: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(self.snapshot.segments.enumerated()), id: \.offset) { entry in
                let segment = entry.element
                let reveal = self.reveal(segmentIndex: entry.offset, now: now)
                ChatMarkdownRenderer(
                    snapshot: segment.markdown,
                    context: .assistant,
                    variant: .standard,
                    theme: theme,
                    reveal: reveal
                )
            }
        }
    }

    private func reveal(segmentIndex: Int, now: TimeInterval?) -> ChatMarkdownProseReveal? {
        guard let now,
              let location = self.revealLocation,
              location.segmentIndex == segmentIndex
        else { return nil }
        return ChatMarkdownProseReveal(
            blockIndex: location.blockIndex,
            state: self.revealState,
            now: now
        )
    }

    private func updateSnapshot() {
        let now = Date.timeIntervalSinceReferenceDate
        let nextSnapshot = Snapshot(text: self.text)
        let nextLocation = nextSnapshot.lastProseLocation
        let nextRevealState: ChatStreamingRevealState
        if let nextLocation {
            let nextText = nextSnapshot.prose(at: nextLocation).plainText
            if nextLocation == self.revealLocation {
                nextRevealState = step(state: self.revealState, newText: nextText, now: now)
            } else {
                nextRevealState = step(state: ChatStreamingRevealState(), newText: nextText, now: now)
            }
        } else {
            nextRevealState = ChatStreamingRevealState()
        }

        self.snapshot = nextSnapshot
        self.revealLocation = nextLocation
        self.revealState = nextRevealState
        self.pendingUntil = self.reduceMotion ? nil : self.futureDeadline(now: now, state: nextRevealState)
    }

    private func futureDeadline(
        now: TimeInterval = Date.timeIntervalSinceReferenceDate,
        state: ChatStreamingRevealState? = nil) -> TimeInterval?
    {
        guard let deadline = (state ?? self.revealState).latestDeadline, deadline > now else {
            return nil
        }
        return deadline
    }

    @MainActor
    private struct Snapshot {
        struct Segment {
            let markdown: ChatMarkdownRenderSnapshot
        }

        struct ProseLocation: Equatable {
            let segmentIndex: Int
            let blockIndex: Int
        }

        let segments: [Segment]
        let lastProseLocation: ProseLocation?
        let sourceText: String

        init(text: String) {
            let markdown = ChatMarkdownRenderSnapshot(
                text: text,
                isComplete: false,
                preparesReveal: true
            )
            self.segments = [Segment(markdown: markdown)]
            self.sourceText = text
            self.lastProseLocation = markdown.lastProseIndex.map {
                ProseLocation(segmentIndex: 0, blockIndex: $0)
            }
        }

        func prose(at location: ProseLocation) -> ChatMarkdownProse {
            switch self.segments[location.segmentIndex].markdown.blocks[location.blockIndex] {
            case let .prose(prose):
                return prose
            case let .header(_, prose):
                return prose
            case let .blockquote(prose):
                return prose
            default:
                preconditionFailure("Streaming reveal location must identify prose")
            }
        }
    }

    private func fullMessageText(_ message: SDKChatMessage) -> String {
        message.content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined(separator: "\n")
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
        #endif
    }
}
