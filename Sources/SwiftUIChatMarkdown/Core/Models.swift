import Foundation
import SwiftUI

#if os(macOS)
import AppKit
/// Platform-specific image type alias for AppKit.
public typealias SDKPlatformImage = NSImage
#else
import UIKit
/// Platform-specific image type alias for UIKit.
public typealias SDKPlatformImage = UIImage
#endif

/// A structures representing a single chat message in the session history.
/// Conforms to `Identifiable`, `Equatable`, `Sendable`, and `Codable` for safe concurrent operations and persistence.
public struct SDKChatMessage: Identifiable, Equatable, Sendable, Codable {
    /// Unique identifier for the message.
    public let id: UUID
    /// The role of the sender (e.g., "user", "assistant", "system").
    public let role: String
    /// An array of content nodes representing text, code, or binary attachments.
    public let content: [SDKChatMessageContent]
    /// The timestamp when the message was created or received.
    public let timestamp: Date
    /// A flag indicating whether the message stream is complete or still generating.
    public let isComplete: Bool

    public init(id: UUID = UUID(), role: String, content: [SDKChatMessageContent], timestamp: Date = Date(), isComplete: Bool = true) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isComplete = isComplete
    }
}

/// A structured content node within an `SDKChatMessage`.
/// Supports multi-modal content types such as text, images, or files.
public struct SDKChatMessageContent: Equatable, Sendable, Codable {
    /// The mime type classification of the content (e.g. "text", "image", "file").
    public let type: String
    /// The plain text representation of the content node.
    public let text: String?
    /// The internet media type (MIME type) of the attached file, if applicable.
    public let mimeType: String?
    /// The original file name of the attachment, if applicable.
    public let fileName: String?
    /// The raw binary data of the attachment, stripped prior to database write to keep tables light.
    public let data: Data?

    public init(type: String, text: String? = nil, mimeType: String? = nil, fileName: String? = nil, data: Data? = nil) {
        self.type = type
        self.text = text
        self.mimeType = mimeType
        self.fileName = fileName
        self.data = data
    }
}

public struct SDKMarkdownTheme: Sendable {
    public let textColor: Color
    public let accentColor: Color
    public let codeBackgroundColor: Color
    public let font: Font
    public let monoFont: Font
    public let keywordColor: Color
    public let stringColor: Color
    public let commentColor: Color
    public let numberColor: Color

    public static let `default` = SDKMarkdownTheme(
        textColor: .primary,
        accentColor: .blue,
        codeBackgroundColor: {
            #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
            #else
            return Color(.secondarySystemBackground)
            #endif
        }(),
        font: .body,
        monoFont: .system(.footnote, design: .monospaced),
        keywordColor: SDKMarkdownTheme.adaptive(light: (0.68, 0.24, 0.64), dark: (1.00, 0.48, 0.70)),
        stringColor: SDKMarkdownTheme.adaptive(light: (0.82, 0.18, 0.11), dark: (1.00, 0.51, 0.44)),
        commentColor: SDKMarkdownTheme.adaptive(light: (0.44, 0.50, 0.55), dark: (0.50, 0.55, 0.60)),
        numberColor: SDKMarkdownTheme.adaptive(light: (0.15, 0.16, 0.85), dark: (0.85, 0.79, 0.49))
    )

    public init(
        textColor: Color,
        accentColor: Color,
        codeBackgroundColor: Color,
        font: Font,
        monoFont: Font,
        keywordColor: Color = SDKMarkdownTheme.adaptive(light: (0.68, 0.24, 0.64), dark: (1.00, 0.48, 0.70)),
        stringColor: Color = SDKMarkdownTheme.adaptive(light: (0.82, 0.18, 0.11), dark: (1.00, 0.51, 0.44)),
        commentColor: Color = SDKMarkdownTheme.adaptive(light: (0.44, 0.50, 0.55), dark: (0.50, 0.55, 0.60)),
        numberColor: Color = SDKMarkdownTheme.adaptive(light: (0.15, 0.16, 0.85), dark: (0.85, 0.79, 0.49))
    ) {
        self.textColor = textColor
        self.accentColor = accentColor
        self.codeBackgroundColor = codeBackgroundColor
        self.font = font
        self.monoFont = monoFont
        self.keywordColor = keywordColor
        self.stringColor = stringColor
        self.commentColor = commentColor
        self.numberColor = numberColor
    }

    public static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(calibratedRed: value.0, green: value.1, blue: value.2, alpha: 1)
        }))
        #else
        return Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
        #endif
    }
}
