import XCTest
@testable import SwiftUIChatMarkdown

final class CoreTests: XCTestCase {
    func testModelInitialization() {
        let content = SDKChatMessageContent(type: "text", text: "Hello math")
        let message = SDKChatMessage(role: "user", content: [content])
        XCTAssertEqual(message.role, "user")
        XCTAssertEqual(message.content.first?.text, "Hello math")
    }
}
