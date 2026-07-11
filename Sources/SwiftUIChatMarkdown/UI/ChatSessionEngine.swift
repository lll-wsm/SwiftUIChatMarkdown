import Foundation
import Observation

/// The engine managing active chat state, streaming tokens, and loading/sync workflows.
/// Designed under the Swift Observation framework for reactive SwiftUI bindings.
/// Runs exclusively on the `@MainActor` to prevent race conditions during message mutations.
@Observable
@MainActor
public final class ChatSessionEngine {
    /// The current array of messages rendered in the chat session thread.
    public private(set) var messages: [SDKChatMessage] = []
    /// Reactive flag indicating whether a remote synchronization is in progress.
    public var isLoading = false
    private let sessionKey: String
    private let cache: ChatMessageCache?
    private let dataSource: ChatSessionDataSource?

    public init(sessionKey: String, cache: ChatMessageCache? = nil, dataSource: ChatSessionDataSource? = nil) {
        self.sessionKey = sessionKey
        self.cache = cache
        self.dataSource = dataSource
    }

    public func coldOpen() async {
        guard let cache else { return }
        let local = await cache.loadTranscript(sessionKey: sessionKey)
        if !local.isEmpty {
            self.messages = local
        }
    }

    public func syncRemote() async {
        guard let dataSource else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let remote = try await dataSource.fetchRemoteHistory(sessionKey: sessionKey)
            self.messages = remote
            if let cache {
                await cache.storeTranscript(sessionKey: sessionKey, messages: remote)
            }
        } catch {
            // Silence remote failure and keep using local cache data
        }
    }
    
    public func appendUserMessage(_ text: String) {
        let newMsg = SDKChatMessage(
            id: UUID(),
            role: "user",
            content: [SDKChatMessageContent(type: "text", text: text)],
            timestamp: Date(),
            isComplete: true
        )
        messages.append(newMsg)

        if let cache = cache {
            let currentMessages = messages
            let currentSessionKey = sessionKey
            Task {
                await cache.storeTranscript(sessionKey: currentSessionKey, messages: currentMessages)
            }
        }
    }
    
    public func appendStreamChunk(_ text: String, forMessageID id: UUID, isComplete: Bool) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let existing = messages[index]
            var content = existing.content
            
            if let lastIndex = content.lastIndex(where: { $0.type == "text" }) {
                let lastText = content[lastIndex]
                content[lastIndex] = SDKChatMessageContent(
                    type: "text",
                    text: (lastText.text ?? "") + text,
                    mimeType: lastText.mimeType,
                    fileName: lastText.fileName,
                    data: lastText.data
                )
            } else {
                content.append(SDKChatMessageContent(type: "text", text: text))
            }
            
            messages[index] = SDKChatMessage(
                id: existing.id,
                role: existing.role,
                content: content,
                timestamp: existing.timestamp,
                isComplete: isComplete
            )
        } else {
            let newMsg = SDKChatMessage(
                id: id,
                role: "assistant",
                content: [SDKChatMessageContent(type: "text", text: text)],
                timestamp: Date(),
                isComplete: isComplete
            )
            messages.append(newMsg)
        }

        if isComplete, let cache = cache {
            let currentMessages = messages
            let currentSessionKey = sessionKey
            Task {
                await cache.storeTranscript(sessionKey: currentSessionKey, messages: currentMessages)
            }
        }
    }
}
