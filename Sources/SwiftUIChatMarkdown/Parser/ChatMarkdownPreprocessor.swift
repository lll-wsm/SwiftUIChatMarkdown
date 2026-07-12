import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum ChatMarkdownPreprocessor {
    public struct InlineImage: Identifiable, @unchecked Sendable {
        public let id: UUID
        public let label: String
        public let image: SDKPlatformImage?

        public init(id: UUID = UUID(), label: String, image: SDKPlatformImage?) {
            self.id = id
            self.label = label
            self.image = image
        }
    }

    public struct Result: Sendable {
        public let cleaned: String
        public let images: [InlineImage]

        public init(cleaned: String, images: [InlineImage]) {
            self.cleaned = cleaned
            self.images = images
        }
    }

    private static let markdownImagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
    private static let messageIdHintPattern = #"^\s*\[message_id:\s*[^\]]+\]\s*$"#

    public static func preprocess(markdown raw: String) -> Result {
        let withoutFrontmatter = self.stripFrontmatter(raw)
        let withoutMessageIdHints = self.stripMessageIdHints(withoutFrontmatter)
        let withoutTimestamps = self.stripPrefixedTimestamps(withoutMessageIdHints)
        let fixedPunctuation = self.fixBoldPunctuation(withoutTimestamps)
        
        guard let re = try? NSRegularExpression(pattern: self.markdownImagePattern) else {
            return Result(cleaned: self.normalize(fixedPunctuation), images: [])
        }

        let ns = fixedPunctuation as NSString
        let matches = re.matches(
            in: fixedPunctuation,
            range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return Result(cleaned: self.normalize(fixedPunctuation), images: []) }

        var images: [InlineImage] = []
        let cleaned = NSMutableString(string: fixedPunctuation)

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let label = ns.substring(with: match.range(at: 1))
            let source = ns.substring(with: match.range(at: 2))

            if let inlineImage = self.inlineImage(label: label, source: source) {
                images.append(inlineImage)
                cleaned.replaceCharacters(in: match.range, with: "")
            } else {
                cleaned.replaceCharacters(in: match.range, with: self.fallbackImageLabel(label))
            }
        }

        return Result(cleaned: self.normalize(cleaned as String), images: images.reversed())
    }

    private static func fixBoldPunctuation(_ raw: String) -> String {
        let rawWithBold = self.cleanEmphasisRuns(
            in: raw,
            pattern: #"(\*\*)([^\*]*[^\*\s][^\*]*)(\*\*)"#,
            delimiter: "**"
        )
        let finalResult = self.cleanEmphasisRuns(
            in: rawWithBold,
            pattern: #"(?<!\*)(\*)([^\*]*[^\*\s][^\*]*)(\*)(?!\*)"#,
            delimiter: "*"
        )
        return finalResult
    }

    private static func cleanEmphasisRuns(in raw: String, pattern: String, delimiter: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return raw }
        var result = raw
        var offset = 0
        let ns = result as NSString
        let matches = re.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
            guard adjustedRange.location != NSNotFound,
                  adjustedRange.location + adjustedRange.length <= (result as NSString).length
            else { continue }
            
            let currentNs = result as NSString
            let openingRange = NSRange(location: match.range(at: 1).location + offset, length: match.range(at: 1).length)
            let contentRange = NSRange(location: match.range(at: 2).location + offset, length: match.range(at: 2).length)
            let closingRange = NSRange(location: match.range(at: 3).location + offset, length: match.range(at: 3).length)
            
            let content = currentNs.substring(with: contentRange)
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            var prefix = ""
            if openingRange.location > 0 {
                let prevCharRange = NSRange(location: openingRange.location - 1, length: 1)
                let prevChar = currentNs.substring(with: prevCharRange)
                if !prevChar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    prefix = " "
                }
            }
            
            var suffix = ""
            let closingEnd = closingRange.location + closingRange.length
            if closingEnd < currentNs.length {
                let nextCharRange = NSRange(location: closingEnd, length: 1)
                let nextChar = currentNs.substring(with: nextCharRange)
                if !nextChar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let rePunct = try! NSRegularExpression(pattern: #"[\p{P}]"#, options: [])
                    let isPunct = rePunct.firstMatch(in: nextChar, options: [], range: NSRange(location: 0, length: 1)) != nil
                    if !isPunct {
                        suffix = " "
                    }
                }
            }
            
            let replacement = "\(prefix)\(delimiter)\(trimmedContent)\(delimiter)\(suffix)"
            let originalLength = currentNs.substring(with: adjustedRange).count
            
            result = currentNs.replacingCharacters(in: adjustedRange, with: replacement)
            offset += replacement.count - originalLength
        }
        return result
    }

    private static func inlineImage(label: String, source: String) -> InlineImage? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = trimmed.firstIndex(of: ","),
              trimmed[..<comma].range(
                  of: #"^data:image\/[^;]+;base64$"#,
                  options: [.regularExpression, .caseInsensitive]) != nil
        else {
            return nil
        }

        let b64 = String(trimmed[trimmed.index(after: comma)...])
        let image = Data(base64Encoded: b64).flatMap(SDKPlatformImage.init(data:))
        return InlineImage(label: label, image: image)
    }

    private static func fallbackImageLabel(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "image" : trimmed
    }

    private static func stripFrontmatter(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
        guard lines.count > 2, lines[0] == "---" else { return raw }
        var index = 1
        while index < lines.count {
            if lines[index] == "---" {
                return lines[(index + 1)...].joined(separator: "\n")
            }
            index += 1
        }
        return raw
    }

    private static func stripMessageIdHints(_ raw: String) -> String {
        guard raw.contains("[message_id:") else {
            return raw
        }
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false)
        let filtered = lines.filter { line in
            String(line).range(of: self.messageIdHintPattern, options: .regularExpression) == nil
        }
        guard filtered.count != lines.count else {
            return raw
        }
        return filtered.map(String.init).joined(separator: "\n")
    }

    private static func stripPrefixedTimestamps(_ raw: String) -> String {
        let pattern = #"(?m)^\[[A-Za-z]{3}\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?\s+(?:GMT|UTC)[+-]?\d{0,2}\]\s*"#
        return raw.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func normalize(_ raw: String) -> String {
        var output = raw
        output = output.replacingOccurrences(of: "\r\n", with: "\n")
        output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
