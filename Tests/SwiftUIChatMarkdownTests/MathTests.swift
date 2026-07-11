import XCTest
@testable import SwiftUIChatMarkdown

final class MathTests: XCTestCase {
    @MainActor
    func testMathNestingLimits() {
        // Test curly brace nesting limits
        let nestedBraces = String(repeating: "{", count: 70) + String(repeating: "}", count: 70)
        XCTAssertNil(ChatMathParseCache.mathList(latex: nestedBraces))
        
        // Test \left / \right nesting limits
        let nestedLatex = String(repeating: "\\left(", count: 70) + String(repeating: "\\right)", count: 70)
        XCTAssertNil(ChatMathParseCache.mathList(latex: nestedLatex))
        
        // Test safe nesting
        let safeLatex = String(repeating: "\\left(", count: 10) + String(repeating: "\\right)", count: 10)
        XCTAssertNotNil(ChatMathParseCache.mathList(latex: safeLatex))
    }
    
    @MainActor
    func testMathCommandLimits() {
        // Test command limit (max 128)
        let tooManyCommands = String(repeating: "\\alpha ", count: 130)
        XCTAssertNil(ChatMathParseCache.mathList(latex: tooManyCommands))
        
        let safeCommands = String(repeating: "\\alpha ", count: 50)
        XCTAssertNotNil(ChatMathParseCache.mathList(latex: safeCommands))
    }

    @MainActor
    func testMathSizeLimits() {
        // Test source size limit (max 5000 bytes)
        let tooLongLatex = String(repeating: "x", count: 5001)
        XCTAssertNil(ChatMathParseCache.mathList(latex: tooLongLatex))
    }

    @MainActor
    func testUnsafeCommands() {
        XCTAssertNil(ChatMathParseCache.mathList(latex: "x \\color{red} y"))
        XCTAssertNil(ChatMathParseCache.mathList(latex: "\\textcolor{blue}{x}"))
    }

    func testScannerPieces() {
        let pieces = ChatInlineMathScanner.pieces(in: "before \\(x + 1\\) after")
        XCTAssertEqual(pieces.count, 3)
        
        guard case let .markdown(prefix) = pieces[0] else { XCTFail(); return }
        XCTAssertEqual(prefix, "before ")
        
        guard case let .math(latex, source) = pieces[1] else { XCTFail(); return }
        XCTAssertEqual(latex, "x + 1")
        XCTAssertEqual(source, "\\(x + 1\\)")
        
        guard case let .markdown(suffix) = pieces[2] else { XCTFail(); return }
        XCTAssertEqual(suffix, " after")
    }

    func testScannerBackticksAndEscapes() {
        let backticks = "use `\\(not math\\)` here"
        let pieces = ChatInlineMathScanner.pieces(in: backticks)
        XCTAssertEqual(pieces.count, 1)
        guard case let .markdown(text) = pieces[0] else { XCTFail(); return }
        XCTAssertEqual(text, backticks)
        
        let escaped = "escaped \\\\(x\\\\)"
        let piecesEscaped = ChatInlineMathScanner.pieces(in: escaped)
        XCTAssertEqual(piecesEscaped.count, 1)
    }
}
