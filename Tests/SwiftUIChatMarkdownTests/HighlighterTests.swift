import XCTest
@testable import SwiftUIChatMarkdown

final class HighlighterTests: XCTestCase {
    func testHighlightLimits() {
        let shortCode = "let a = 1"
        XCTAssertTrue(ChatCodeHighlighter.isWithinHighlightLimits(shortCode))
        
        let longCode = String(repeating: "let a = 1\n", count: 205)
        XCTAssertFalse(ChatCodeHighlighter.isWithinHighlightLimits(longCode))
        
        let longByteCode = String(repeating: "a", count: 20001)
        XCTAssertFalse(ChatCodeHighlighter.isWithinHighlightLimits(longByteCode))
    }

    func testTokenization() {
        let code = "let x = 42 // comment"
        guard let language = ChatCodeHighlighter.language(for: "swift") else {
            XCTFail("Swift language should be supported")
            return
        }
        let tokens = ChatCodeHighlighter.tokens(code: code, language: language)
        
        XCTAssertEqual(tokens.count, 5)
        XCTAssertEqual(tokens[0].kind, .keyword)
        XCTAssertEqual(tokens[0].text, "let")
        
        XCTAssertEqual(tokens[1].kind, .plain)
        XCTAssertEqual(tokens[1].text, " x = ")
        
        XCTAssertEqual(tokens[2].kind, .number)
        XCTAssertEqual(tokens[2].text, "42")
        
        XCTAssertEqual(tokens[3].kind, .plain)
        XCTAssertEqual(tokens[3].text, " ")
        
        XCTAssertEqual(tokens[4].kind, .comment)
        XCTAssertEqual(tokens[4].text, "// comment")
    }

    @MainActor
    func testHighlighterCache() {
        let code = "func hello() {}"
        let highlighted1 = ChatCodeHighlightCache.highlighted(code: code, languageId: "swift")
        let highlighted2 = ChatCodeHighlightCache.highlighted(code: code, languageId: "swift")
        XCTAssertEqual(highlighted1, highlighted2)
    }

    func testCRLFHandling() {
        let crlfCode = "let x = 42\r\n// comment\r\nlet y = 24"
        guard let language = ChatCodeHighlighter.language(for: "swift") else {
            XCTFail("Swift language should be supported")
            return
        }
        let tokens = ChatCodeHighlighter.tokens(code: crlfCode, language: language)
        // Check that the comment is recognized correctly and does not swallow the next line
        let commentToken = tokens.first(where: { $0.kind == .comment })
        XCTAssertNotNil(commentToken)
        XCTAssertEqual(commentToken?.text, "// comment")
        
        // Verify that keywords and variables are correctly tokenized on the next line
        XCTAssertTrue(tokens.contains(where: { $0.kind == .keyword && $0.text == "let" }))
        XCTAssertTrue(tokens.contains(where: { $0.kind == .plain && $0.text.contains("y") }))
    }

    func testCRLFHighlightLimits() {
        let longCRLFCode = String(repeating: "let a = 1\r\n", count: 205)
        XCTAssertFalse(ChatCodeHighlighter.isWithinHighlightLimits(longCRLFCode))
    }
}
