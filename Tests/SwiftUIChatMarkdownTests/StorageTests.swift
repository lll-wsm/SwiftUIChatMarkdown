import XCTest
@testable import SwiftUIChatMarkdown

final class StorageTests: XCTestCase {
    func testBinaryDataStripping() async {
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-chat-strip-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: testURL) }
        
        let cache = SQLiteChatMessageCache(databaseURL: testURL)
        let largeData = Data(repeating: 0, count: 50000)
        let message = SDKChatMessage(role: "user", content: [
            SDKChatMessageContent(type: "image", text: "desc", data: largeData)
        ])
        
        await cache.storeTranscript(sessionKey: "session-1", messages: [message])
        let loaded = await cache.loadTranscript(sessionKey: "session-1")
        
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded.first?.content.first?.data, "二进制数据在存入本地缓存时必须剥离")
    }

    func testMaxTranscriptLimit() async {
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-chat-limit-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: testURL) }
        
        let cache = SQLiteChatMessageCache(databaseURL: testURL)
        
        // Generate 250 dummy messages
        var messages: [SDKChatMessage] = []
        for i in 1...250 {
            messages.append(SDKChatMessage(role: "assistant", content: [
                SDKChatMessageContent(type: "text", text: "msg \(i)")
            ]))
        }
        
        await cache.storeTranscript(sessionKey: "session-2", messages: messages)
        let loaded = await cache.loadTranscript(sessionKey: "session-2")
        
        XCTAssertEqual(loaded.count, 200, "最多只保存最近的 200 条消息")
        XCTAssertEqual(loaded.first?.content.first?.text, "msg 51", "应当保留最近的（即后200条）第一条是 msg 51")
        XCTAssertEqual(loaded.last?.content.first?.text, "msg 250", "最后一条是 msg 250")
    }

    func testSessionStorage() async {
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-chat-sessions-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: testURL) }
        
        let cache = SQLiteChatMessageCache(databaseURL: testURL)
        
        let sessions = [
            SDKChatSessionEntry(sessionKey: "s1", title: "Session One", updatedAt: Date(timeIntervalSince1970: 1000)),
            SDKChatSessionEntry(sessionKey: "s2", title: "Session Two", updatedAt: Date(timeIntervalSince1970: 2000))
        ]
        
        await cache.storeSessions(sessions)
        let loaded = await cache.loadSessions()
        
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].sessionKey, "s2", "应该是按 updatedAt 降序排序")
        XCTAssertEqual(loaded[1].sessionKey, "s1")
    }
}
