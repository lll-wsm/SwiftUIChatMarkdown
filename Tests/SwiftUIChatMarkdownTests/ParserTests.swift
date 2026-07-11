import XCTest
@testable import SwiftUIChatMarkdown

final class ParserTests: XCTestCase {
    func testTableLimits() {
        // 验证超宽表格（列数大于12）降级回普通 prose
        let wideHeader = (1...14).map { "Col\($0)" }.joined(separator: " | ")
        let divider = (1...14).map { _ in "---" }.joined(separator: " | ")
        let md = "\n| \(wideHeader) |\n| \(divider) |\n"
        let blocks = ChatMarkdownBlockSegmenter.segments(markdown: md, isComplete: true)
        // 预期：被降级为 prose，而不是 table 结构
        if case .table = blocks.first {
            XCTFail("Should fall back to prose")
        }
    }
    
    func testNormalTable() {
        let normalHeader = (1...5).map { "Col\($0)" }.joined(separator: " | ")
        let divider = (1...5).map { _ in "---" }.joined(separator: " | ")
        let md = "\n| \(normalHeader) |\n| \(divider) |\n"
        let blocks = ChatMarkdownBlockSegmenter.segments(markdown: md, isComplete: true)
        
        guard case let .table(table) = blocks.first else {
            XCTFail("Should parse as table")
            return
        }
        XCTAssertEqual(table.header.count, 5)
    }

    func testPreprocessorFrontmatter() {
        let rawMarkdown = "---\ntitle: Hello\nauthor: OpenClaw\n---\n# Body text"
        let result = ChatMarkdownPreprocessor.preprocess(markdown: rawMarkdown)
        XCTAssertEqual(result.cleaned, "# Body text")
    }

    func testPreprocessorInlineImage() {
        // Simple base64 image (1x1 transparent png)
        let base64Png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        let markdown = "This is a picture: ![test image](\(base64Png))"
        let result = ChatMarkdownPreprocessor.preprocess(markdown: markdown)
        XCTAssertEqual(result.cleaned, "This is a picture:")
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images.first?.label, "test image")
        XCTAssertNotNil(result.images.first?.image)
    }
}
