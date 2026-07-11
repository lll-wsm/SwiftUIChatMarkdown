import XCTest
@testable import SwiftUIChatMarkdown

final class UITests: XCTestCase {
    @MainActor
    func testChatSessionEngineStreaming() async {
        let engine = ChatSessionEngine(sessionKey: "session-123")
        XCTAssertTrue(engine.messages.isEmpty)
        
        let messageId = UUID()
        engine.appendStreamChunk("Hello", forMessageID: messageId, isComplete: false)
        XCTAssertEqual(engine.messages.count, 1)
        XCTAssertEqual(engine.messages.first?.content.first?.text, "Hello")
        XCTAssertFalse(engine.messages.first?.isComplete ?? true)
        
        engine.appendStreamChunk(" World!", forMessageID: messageId, isComplete: true)
        XCTAssertEqual(engine.messages.count, 1)
        XCTAssertEqual(engine.messages.first?.content.first?.text, "Hello World!")
        XCTAssertTrue(engine.messages.first?.isComplete ?? false)
    }

    private final class MockCache: ChatMessageCache, @unchecked Sendable {
        var storedTranscriptCalled = false
        var storedMessages: [SDKChatMessage] = []

        func loadSessions() async -> [SDKChatSessionEntry] { [] }
        func loadTranscript(sessionKey: String) async -> [SDKChatMessage] { [] }
        func storeTranscript(sessionKey: String, messages: [SDKChatMessage]) async {
            storedTranscriptCalled = true
            storedMessages = messages
        }
        func storeSessions(_ sessions: [SDKChatSessionEntry]) async {}
    }

    @MainActor
    func testImmediateCompletionCaching() async {
        let mockCache = MockCache()
        let engine = ChatSessionEngine(sessionKey: "session-456", cache: mockCache)
        
        let messageId = UUID()
        engine.appendStreamChunk("Fast Response", forMessageID: messageId, isComplete: true)
        
        try? await Task.sleep(for: .milliseconds(50))
        
        XCTAssertTrue(mockCache.storedTranscriptCalled)
        XCTAssertEqual(mockCache.storedMessages.count, 1)
        XCTAssertEqual(mockCache.storedMessages.first?.content.first?.text, "Fast Response")
        XCTAssertTrue(mockCache.storedMessages.first?.isComplete ?? false)
    }

    func testTypingRevealStep() {
        let initial = ChatStreamingRevealState()
        let now: TimeInterval = 1000.0
        
        let state1 = step(state: initial, newText: "Hello World", now: now)
        XCTAssertEqual(state1.text, "Hello World")
        XCTAssertEqual(state1.words.count, 2)
        XCTAssertEqual(state1.words[0].fadeStart, now)
        XCTAssertEqual(state1.words[1].fadeStart, now + 0.04)
        
        let state2 = step(state: state1, newText: "Hello World Again", now: now + 0.1)
        XCTAssertEqual(state2.text, "Hello World Again")
        // Word count is now 3
        XCTAssertEqual(state2.words.count, 3)
    }

    func testRevealedOpacities() {
        let initial = ChatStreamingRevealState()
        let now: TimeInterval = 1000.0
        let state = step(state: initial, newText: "Hello", now: now)
        
        // Fading state at the start
        let frameAtStart = revealedOpacities(state: state, now: now)
        XCTAssertEqual(frameAtStart.fading.count, 1)
        XCTAssertEqual(frameAtStart.fading[0].opacity, 0.0)
        
        // Fading state at the end
        let deadline = state.words[0].deadline
        let frameAtEnd = revealedOpacities(state: state, now: deadline)
        XCTAssertEqual(frameAtEnd.fading.count, 0, "Deadline reached, should be fully revealed (removed from fading list)")
    }
}
