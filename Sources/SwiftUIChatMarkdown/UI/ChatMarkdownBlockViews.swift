import Markdown
import SwiftMath
import SwiftUI
import BeautifulMermaid

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum ChatMarkdownVariant: String, CaseIterable, Sendable {
    case standard
    case compact
}

@MainActor
public struct ChatCodeBlockView: View {
    let block: ChatCodeBlock
    let theme: SDKMarkdownTheme

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        if self.block.language?.lowercased() == "mermaid", self.block.isComplete {
            MermaidDiagramView(source: self.block.code, theme: colorScheme == .dark ? .zincDark : .zincLight)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let language = self.block.language {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(self.attributedCode)
                        .font(theme.monoFont)
                        .foregroundStyle(theme.textColor)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.codeBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
        }
    }

    private var attributedCode: AttributedString {
        guard self.block.isComplete else { return AttributedString(self.block.code) }
        return ChatCodeHighlightCache.highlighted(
            code: self.block.code,
            languageId: self.block.language,
            theme: theme)
    }
}

@MainActor
public struct ChatMathBlockView: View {
    let block: ChatMathBlock
    let theme: SDKMarkdownTheme

    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 16

    public var body: some View {
        if self.block.isComplete,
           ChatMathParseCache.mathList(latex: self.block.latex) != nil
        {
            ScrollView(.horizontal, showsIndicators: false) {
                ChatMathPlatformView(
                    latex: self.block.latex,
                    fontSize: self.fontSize,
                    textColor: theme.textColor)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(self.block.latex))
            }
            .defaultScrollAnchor(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        } else {
            ChatCodeBlockView(block: ChatCodeBlock(
                language: nil,
                code: self.block.latex,
                isComplete: false), theme: theme)
        }
    }
}

#if os(macOS)
@MainActor
private struct ChatMathPlatformView: NSViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let textColor: Color

    func makeNSView(context: Context) -> MTMathUILabel {
        MTMathUILabel()
    }

    func updateNSView(_ view: MTMathUILabel, context: Context) {
        self.configure(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
        nsView.fittingSize
    }

    private func configure(_ view: MTMathUILabel) {
        view.displayErrorInline = false
        view.labelMode = .display
        view.textAlignment = .center
        
        var changed = false
        if view.fontSize != self.fontSize {
            view.fontSize = self.fontSize
            changed = true
        }
        let nsColor = NSColor(self.textColor)
        if view.textColor != nsColor {
            view.textColor = nsColor
            changed = true
        }
        if view.latex != self.latex {
            view.latex = self.latex
            changed = true
        }
        
        if changed {
            view.invalidateIntrinsicContentSize()
        }
    }
}
#else
@MainActor
private struct ChatMathPlatformView: UIViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let textColor: Color

    func makeUIView(context: Context) -> MTMathUILabel {
        MTMathUILabel()
    }

    func updateUIView(_ view: MTMathUILabel, context: Context) {
        self.configure(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }

    private func configure(_ view: MTMathUILabel) {
        view.displayErrorInline = false
        view.labelMode = .display
        view.textAlignment = .center
        
        var changed = false
        if view.fontSize != self.fontSize {
            view.fontSize = self.fontSize
            changed = true
        }
        let uiColor = UIColor(self.textColor)
        if view.textColor != uiColor {
            view.textColor = uiColor
            changed = true
        }
        if view.latex != self.latex {
            view.latex = self.latex
            changed = true
        }
        
        if changed {
            view.invalidateIntrinsicContentSize()
        }
    }
}
#endif

@MainActor
public struct ChatMarkdownTableView: View {
    let table: ChatMarkdownTable
    let theme: SDKMarkdownTheme

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    ForEach(self.table.header.indices, id: \.self) { column in
                        self.cell(self.table.header[column], column: column, isHeader: true)
                            .gridColumnAlignment(self.columnAlignment(column))
                    }
                }
                Divider()
                ForEach(self.table.rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(self.table.rows[rowIndex].indices, id: \.self) { column in
                            self.cell(self.table.rows[rowIndex][column], column: column, isHeader: false)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.codeBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
    }

    private func cell(_ text: String, column: Int, isHeader: Bool) -> some View {
        Text(self.inlineMarkdown(text))
            .font(isHeader ? theme.font.weight(.semibold) : theme.font)
            .foregroundStyle(theme.textColor)
            .textSelection(.enabled)
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func columnAlignment(_ column: Int) -> HorizontalAlignment {
        guard column < self.table.alignments.count else { return .leading }
        switch self.table.alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

@MainActor
public struct ChatMarkdownRenderer: View {
    public enum Context {
        case user
        case assistant
    }

    public struct InlineMathTypography: Sendable {
        public static let body = Self(size: 16, relativeTo: .body)
        public static let callout = Self(size: 16, relativeTo: .callout)

        let size: CGFloat
        let relativeTo: Font.TextStyle

        public init(size: CGFloat, relativeTo: Font.TextStyle) {
            self.size = size
            self.relativeTo = relativeTo
        }
    }

    let snapshot: ChatMarkdownRenderSnapshot
    let context: Context
    let variant: ChatMarkdownVariant
    let theme: SDKMarkdownTheme
    var reveal: ChatMarkdownProseReveal?

    @ScaledMetric private var inlineMathFontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(
        text: String,
        context: Context,
        variant: ChatMarkdownVariant,
        theme: SDKMarkdownTheme,
        inlineMathTypography: InlineMathTypography = .body,
        isComplete: Bool = true)
    {
        self.init(
            snapshot: ChatMarkdownRenderSnapshot(text: text, isComplete: isComplete),
            context: context,
            variant: variant,
            theme: theme,
            inlineMathTypography: inlineMathTypography)
    }

    public init(
        snapshot: ChatMarkdownRenderSnapshot,
        context: Context,
        variant: ChatMarkdownVariant,
        theme: SDKMarkdownTheme,
        inlineMathTypography: InlineMathTypography = .body,
        reveal: ChatMarkdownProseReveal? = nil)
    {
        self.snapshot = snapshot
        self.context = context
        self.variant = variant
        self.theme = theme
        self.reveal = reveal
        self._inlineMathFontSize = ScaledMetric(
            wrappedValue: inlineMathTypography.size,
            relativeTo: inlineMathTypography.relativeTo)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(self.snapshot.blocks.enumerated()), id: \.offset) { entry in
                self.blockView(entry.element, index: entry.offset)
            }

            if !self.snapshot.images.isEmpty {
                InlineImageList(images: self.snapshot.images)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ChatMarkdownRenderedBlock, index: Int) -> some View {
        switch block {
        case let .prose(prose):
            self.proseText(prose, index: index)
                .foregroundStyle(theme.textColor)
                .tint(self.linkColor)
                .textSelection(.enabled)
                .lineSpacing(self.variant == .compact ? 2 : 4)
                .modifier(ChatInlineMathAccessibilityModifier(label: prose.inlineAccessibilityText))
        case let .header(level, prose):
            self.proseText(prose, index: index)
                .font(self.headerFont(level: level))
                .foregroundStyle(theme.textColor)
                .tint(self.linkColor)
                .textSelection(.enabled)
                .lineSpacing(4)
                .padding(.top, level == 1 ? 20 : 12)
                .padding(.bottom, 4)
        case let .blockquote(prose):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(theme.accentColor.opacity(0.5))
                    .frame(width: 4)
                    .padding(.trailing, 12)
                self.proseText(prose, index: index)
                    .foregroundStyle(theme.textColor.opacity(0.85))
                    .tint(self.linkColor)
                    .textSelection(.enabled)
                    .lineSpacing(4)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(theme.codeBackgroundColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        case let .list(_, items):
            ChatNestedListView(
                nodes: ChatNestedListView.buildTree(from: items),
                theme: theme,
                rowContent: { item in
                    AnyView(
                        self.proseText(item.prose, index: index)
                            .foregroundStyle(theme.textColor)
                            .tint(self.linkColor)
                            .textSelection(.enabled)
                            .lineSpacing(4)
                    )
                })
            .padding(.vertical, 2)
            .padding(.leading, 16)
        case let .code(code):
            ChatCodeBlockView(block: code, theme: theme)
        case let .math(math):
            ChatMathBlockView(block: math, theme: theme)
        case let .table(table):
            ChatMarkdownTableView(table: table, theme: theme)
        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func headerFont(level: Int) -> Font {
        switch level {
        case 1: .system(.title, design: .default).bold()
        case 2: .system(.title2, design: .default).bold()
        case 3: .system(.title3, design: .default).bold()
        case 4: .system(.headline, design: .default)
        default: .system(.subheadline, design: .default).bold()
        }
    }

    private func proseText(_ prose: ChatMarkdownProse, index: Int) -> SwiftUI.Text {
        guard let reveal = self.reveal, reveal.blockIndex == index else {
            return prose.renderedText(
                font: theme.font,
                fontSize: self.inlineMathFontSize,
                textColor: theme.textColor,
                colorScheme: self.colorScheme)
        }
        return prose.revealedText(
            frame: revealedOpacities(state: reveal.state, now: reveal.now),
            font: theme.font,
            textColor: theme.textColor)
    }

    private var linkColor: Color {
        self.context == .user ? theme.textColor : theme.accentColor
    }
}

/// Renders a (possibly nested) list as a tree, drawing one continuous guide
/// line per nesting level so depth is legible at a glance.
@MainActor
private struct ChatNestedListView: View {
    final class Node: Identifiable {
        let id = UUID()
        let item: ChatMarkdownListItem
        var children: [Node] = []
        init(item: ChatMarkdownListItem) { self.item = item }
    }

    let nodes: [Node]
    let theme: SDKMarkdownTheme
    let rowContent: (ChatMarkdownListItem) -> AnyView

    /// Rebuilds the flat `indentLevel`-tagged item list into a tree so each
    /// level can draw its own continuous guide line.
    static func buildTree(from items: [ChatMarkdownListItem]) -> [Node] {
        var roots: [Node] = []
        var stack: [Node] = []
        for item in items {
            let node = Node(item: item)
            while stack.count > item.indentLevel {
                stack.removeLast()
            }
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        }
        return roots
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(nodes) { node in
                HStack(alignment: .top, spacing: 8) {
                    Text(node.item.bullet)
                        .font(theme.monoFont)
                        .foregroundStyle(theme.accentColor)
                    rowContent(node.item)
                }
                if !node.children.isEmpty {
                    ChatNestedListView(
                        nodes: node.children,
                        theme: theme,
                        rowContent: rowContent)
                        .padding(.leading, 20)
                }
            }
        }
    }
}

public struct ChatMarkdownProseReveal {
    let blockIndex: Int
    let state: ChatStreamingRevealState
    let now: TimeInterval

    public init(blockIndex: Int, state: ChatStreamingRevealState, now: TimeInterval) {
        self.blockIndex = blockIndex
        self.state = state
        self.now = now
    }
}

@MainActor
public struct ChatMarkdownRenderSnapshot {
    public let blocks: [ChatMarkdownRenderedBlock]
    public let images: [ChatMarkdownPreprocessor.InlineImage]

    public init(text: String, isComplete: Bool, preparesReveal: Bool = false) {
        let processed = ChatMarkdownPreprocessor.preprocess(markdown: text)
        self.blocks = ChatMarkdownBlockSegmenter.segments(
            markdown: processed.cleaned,
            isComplete: isComplete).map { block in
            switch block {
            case let .prose(markdown):
                .prose(ChatMarkdownProse(
                    markdown: markdown,
                    isComplete: isComplete,
                    preparesReveal: preparesReveal))
            case let .header(level, markdown):
                .header(level: level, prose: ChatMarkdownProse(
                    markdown: markdown,
                    isComplete: isComplete,
                    preparesReveal: preparesReveal))
            case let .blockquote(markdown):
                .blockquote(prose: ChatMarkdownProse(
                    markdown: markdown,
                    isComplete: isComplete,
                    preparesReveal: preparesReveal))
            case let .list(ordered, items):
                .list(ordered: ordered, items: items.map { item in
                    ChatMarkdownListItem(
                        prose: ChatMarkdownProse(
                            markdown: item.markdown,
                            isComplete: isComplete,
                            preparesReveal: preparesReveal),
                        bullet: item.bullet,
                        indentLevel: item.indentLevel
                    )
                })
            case let .code(code):
                .code(code)
            case let .math(math):
                .math(math)
            case let .table(table):
                .table(table)
            case .thematicBreak:
                .thematicBreak
            }
        }
        self.images = processed.images
    }

    public var lastProseIndex: Int? {
        self.blocks.lastIndex {
            switch $0 {
            case .prose, .header, .blockquote:
                return true
            default:
                return false
            }
        }
    }
}

public struct ChatMarkdownListItem: Sendable {
    public let prose: ChatMarkdownProse
    public let bullet: String
    public let indentLevel: Int

    public init(prose: ChatMarkdownProse, bullet: String, indentLevel: Int) {
        self.prose = prose
        self.bullet = bullet
        self.indentLevel = indentLevel
    }
}

public enum ChatMarkdownRenderedBlock {
    case prose(ChatMarkdownProse)
    case header(level: Int, prose: ChatMarkdownProse)
    case list(ordered: Bool, items: [ChatMarkdownListItem])
    case blockquote(prose: ChatMarkdownProse)
    case code(ChatCodeBlock)
    case math(ChatMathBlock)
    case table(ChatMarkdownTable)
    case thematicBreak
}

@MainActor
public struct ChatMarkdownProse {
    public struct TailPiece {
        let attributed: AttributedString
        let wordRange: Range<Int>?
    }

    let attributed: AttributedString
    public let plainText: String
    let prefix: AttributedString
    let tail: [TailPiece]
    let inlineContent: [InlineContent]?

    enum InlineContent {
        case text(AttributedString)
        case math(ChatInlineMathSpan)
    }

    public init(markdown: String, isComplete: Bool, preparesReveal: Bool) {
        let inlineContent = isComplete && !preparesReveal
            ? Self.makeInlineContent(markdown: markdown)
            : nil
        let attributed = inlineContent == nil
            ? Self.parseMarkdown(markdown)
            : AttributedString()
        let plainText = preparesReveal ? String(attributed.characters) : ""
        let wordRanges = preparesReveal
            ? Array(chatStreamingWordRanges(in: plainText).suffix(24))
            : []
        let tailStart = wordRanges.first?.lowerBound ?? plainText.count

        self.attributed = attributed
        self.plainText = plainText
        self.inlineContent = inlineContent
        if preparesReveal {
            self.prefix = Self.slice(attributed, characterRange: 0..<tailStart)
            self.tail = Self.tailPieces(
                attributed: attributed,
                textLength: plainText.count,
                wordRanges: wordRanges,
                tailStart: tailStart)
        } else {
            self.prefix = AttributedString()
            self.tail = []
        }
    }

    var inlineAccessibilityText: String? {
        guard let inlineContent else { return nil }
        return inlineContent.reduce(into: "") { text, content in
            switch content {
            case let .text(attributed):
                text += String(attributed.characters)
            case let .math(span):
                text += span.latex
            }
        }
    }

    func renderedText(
        font: Font,
        fontSize: CGFloat,
        textColor: Color,
        colorScheme: ColorScheme) -> SwiftUI.Text
    {
        guard let inlineContent else {
            var attr = self.attributed
            attr.font = font
            return SwiftUI.Text(attr)
        }
        return inlineContent.reduce(SwiftUI.Text("")) { text, content in
            switch content {
            case let .text(attributed):
                var attr = attributed
                attr.font = font
                return text + SwiftUI.Text(attr)
            case let .math(span):
                guard let rendered = ChatInlineMathImageCache.image(
                    latex: span.latex,
                    fontSize: fontSize,
                    textColor: textColor,
                    colorScheme: colorScheme)
                else {
                    var raw = AttributedString(span.source)
                    raw.font = font
                    return text + SwiftUI.Text(raw)
                }
                #if os(macOS)
                let image = Image(nsImage: rendered.image)
                #else
                let image = Image(uiImage: rendered.image)
                #endif
                return text + SwiftUI.Text(image).baselineOffset(rendered.baselineOffset)
            }
        }
    }

    func revealedText(frame: ChatStreamingRevealFrame, font: Font, textColor: Color) -> SwiftUI.Text {
        var prefixAttr = self.prefix
        prefixAttr.font = font
        return self.tail.reduce(SwiftUI.Text(prefixAttr)) { text, piece in
            var attributed = piece.attributed
            attributed.font = font
            if let wordRange = piece.wordRange,
               let fading = frame.fading.first(where: { $0.characterRange == wordRange })
            {
                attributed.foregroundColor = textColor.opacity(fading.opacity)
            }
            return text + SwiftUI.Text(attributed)
        }
    }

    private static func makeInlineContent(markdown: String) -> [InlineContent]? {
        let pieces = ChatInlineMathScanner.pieces(in: markdown)
        guard pieces.contains(where: { piece in
            if case .markdown = piece {
                return false
            }
            return true
        }) else { return nil }

        var substitutedMarkdown = ""
        var replacements: [InlineReplacement] = []
        var markerValue: UInt32 = 0xE000
        var occupiedMarkerValues = Set(markdown.unicodeScalars.map(\.value))
        for piece in pieces {
            switch piece {
            case let .markdown(source):
                substitutedMarkdown += source
            case let .literal(source):
                substitutedMarkdown += Self.markdownEscapedLiteral(source)
            case let .math(latex, source):
                guard ChatMathParseCache.mathList(latex: latex) != nil else {
                    substitutedMarkdown += Self.markdownEscapedLiteral(source)
                    continue
                }
                let marker = Self.nextMarker(
                    startingAt: &markerValue,
                    occupiedValues: &occupiedMarkerValues)
                substitutedMarkdown.append(marker)
                replacements.append(InlineReplacement(
                    marker: marker,
                    span: ChatInlineMathSpan(latex: latex, source: source)))
            }
        }

        let attributed = self.parseMarkdown(substitutedMarkdown)
        var content: [InlineContent] = []
        var cursor = attributed.startIndex
        for replacement in replacements {
            guard let markerIndex = attributed.characters[cursor...]
                .firstIndex(of: replacement.marker)
            else { return nil }
            if cursor < markerIndex {
                content.append(.text(AttributedString(attributed[cursor..<markerIndex])))
            }
            let markerEnd = attributed.characters.index(after: markerIndex)
            let attributes = attributed[markerIndex..<markerEnd].runs.first?.attributes
            if attributes?.link != nil {
                var literal = AttributedString(replacement.span.source)
                if let attributes {
                    literal.mergeAttributes(attributes)
                }
                content.append(.text(literal))
            } else {
                content.append(.math(replacement.span))
            }
            cursor = markerEnd
        }
        if cursor < attributed.endIndex {
            content.append(.text(AttributedString(attributed[cursor...])))
        }
        return content
    }

    private struct InlineReplacement {
        let marker: Character
        let span: ChatInlineMathSpan
    }

    private static func nextMarker(
        startingAt value: inout UInt32,
        occupiedValues: inout Set<UInt32>) -> Character
    {
        while occupiedValues.contains(value) {
            value += 1
        }
        guard let scalar = UnicodeScalar(value) else {
            preconditionFailure("inline math marker range exhausted")
        }
        occupiedValues.insert(value)
        let marker = Character(String(scalar))
        value += 1
        return marker
    }

    private static func markdownEscapedLiteral(_ source: String) -> String {
        source.reduce(into: "") { escaped, character in
            if character.unicodeScalars.count == 1,
               let scalar = character.unicodeScalars.first,
               scalar.isASCII,
               (33...47).contains(scalar.value) ||
               (58...64).contains(scalar.value) ||
               (91...96).contains(scalar.value) ||
               (123...126).contains(scalar.value)
            {
                escaped.append("\\")
            }
            escaped.append(character)
        }
    }

    private static func parseMarkdown(_ markdown: String) -> AttributedString {
        let displayMarkdown = ChatMarkdownDisplayPreprocessor.preserveChatSoftBreaks(in: markdown)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: displayMarkdown, options: options))
            ?? AttributedString(displayMarkdown)
    }

    private static func tailPieces(
        attributed: AttributedString,
        textLength: Int,
        wordRanges: [Range<Int>],
        tailStart: Int) -> [TailPiece]
    {
        guard !wordRanges.isEmpty else { return [] }
        var pieces: [TailPiece] = []
        var cursor = tailStart
        for wordRange in wordRanges {
            if cursor < wordRange.lowerBound {
                pieces.append(TailPiece(
                    attributed: self.slice(attributed, characterRange: cursor..<wordRange.lowerBound),
                    wordRange: nil))
            }
            pieces.append(TailPiece(
                attributed: self.slice(attributed, characterRange: wordRange),
                wordRange: wordRange))
            cursor = wordRange.upperBound
        }
        if cursor < textLength {
            pieces.append(TailPiece(
                attributed: self.slice(attributed, characterRange: cursor..<textLength),
                wordRange: nil))
        }
        return pieces
    }

    private static func slice(
        _ attributed: AttributedString,
        characterRange: Range<Int>) -> AttributedString
    {
        let lower = attributed.characters.index(
            attributed.startIndex,
            offsetBy: characterRange.lowerBound)
        let upper = attributed.characters.index(
            attributed.startIndex,
            offsetBy: characterRange.upperBound)
        return AttributedString(attributed[lower..<upper])
    }
}

private struct ChatInlineMathAccessibilityModifier: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(Text(label))
        } else {
            content
        }
    }
}

public enum ChatMarkdownDisplayPreprocessor {
    public static func preserveChatSoftBreaks(in markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > 1 else { return normalized }
        let codeLines = self.codeLineIndices(in: normalized)

        var output = ""
        for index in lines.indices {
            output += lines[index]

            guard index < lines.index(before: lines.endIndex) else {
                continue
            }

            if !codeLines.contains(index),
               !codeLines.contains(index + 1),
               self.shouldPreserveSoftBreak(after: lines[index], before: lines[index + 1])
            {
                output += "  \n"
            } else {
                output += "\n"
            }
        }

        return output
    }

    private static func codeLineIndices(in markdown: String) -> Set<Int> {
        guard markdown.contains("```")
            || markdown.contains("~~~")
            || markdown.hasPrefix("    ")
            || markdown.contains("\n    ")
        else { return [] }

        var indices = Set<Int>()
        func collect(from markup: any Markup) {
            if markup is Markdown.CodeBlock, let range = markup.range {
                indices.formUnion((range.lowerBound.line - 1)..<range.upperBound.line)
            }
            for child in markup.children {
                collect(from: child)
            }
        }
        collect(from: Document(parsing: markdown))
        return indices
    }

    private static func shouldPreserveSoftBreak(after line: String, before nextLine: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTrimmed = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !nextTrimmed.isEmpty else { return false }
        guard !self.hasMarkdownHardBreak(line) else { return false }
        return true
    }

    private static func hasMarkdownHardBreak(_ line: String) -> Bool {
        line.hasSuffix("\\") || line.hasSuffix("  ")
    }
}

@MainActor
private struct InlineImageList: View {
    let images: [ChatMarkdownPreprocessor.InlineImage]

    var body: some View {
        ForEach(self.images, id: \.id) { item in
            if let img = item.image {
                #if os(macOS)
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                #else
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                #endif
            } else {
                Text(item.label.isEmpty ? "Image" : item.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

public struct ChatStreamingRevealState: Equatable, Sendable {
    public struct Word: Equatable, Sendable {
        public let characterRange: Range<Int>
        public let fadeStart: TimeInterval
        public let deadline: TimeInterval
    }

    public var text: String
    public var words: [Word]

    public init(text: String = "", words: [Word] = []) {
        self.text = text
        self.words = words
    }

    public var latestDeadline: TimeInterval? {
        self.words.map(\.deadline).max()
    }
}

public struct ChatStreamingRevealFrame: Equatable, Sendable {
    public struct FadingWord: Equatable, Sendable {
        public let characterRange: Range<Int>
        public let opacity: Double
    }

    public let fullyRevealedPrefixCharacterOffset: Int
    public let fading: [FadingWord]
}

private enum ChatStreamingRevealConstants {
    static let wordInterval: TimeInterval = 0.04
    static let fadeDuration: TimeInterval = 0.12
    static let maximumCatchUpDuration: TimeInterval = 0.4
    static let maximumFadingWords = 24
}

public func step(
    state: ChatStreamingRevealState,
    newText: String,
    now: TimeInterval) -> ChatStreamingRevealState
{
    guard newText.hasPrefix(state.text) else {
        return ChatStreamingRevealState(text: newText)
    }
    guard newText != state.text else {
        return ChatStreamingRevealState(
            text: newText,
            words: state.words.filter { $0.deadline > now })
    }

    let oldCharacterCount = state.text.count
    let ranges = chatStreamingWordRanges(in: newText)
    let rangesByStart = Dictionary(uniqueKeysWithValues: ranges.map { ($0.lowerBound, $0) })

    var words = state.words.compactMap { word -> ChatStreamingRevealState.Word? in
        guard word.deadline > now,
              let updatedRange = rangesByStart[word.characterRange.lowerBound]
        else { return nil }
        return ChatStreamingRevealState.Word(
            characterRange: updatedRange,
            fadeStart: word.fadeStart,
            deadline: word.deadline)
    }

    let trackedStarts = Set(words.map(\.characterRange.lowerBound))
    let appendedRanges = ranges.filter {
        $0.lowerBound >= oldCharacterCount && !trackedStarts.contains($0.lowerBound)
    }
    words.append(contentsOf: appendedRanges.map {
        ChatStreamingRevealState.Word(
            characterRange: $0,
            fadeStart: now,
            deadline: now + ChatStreamingRevealConstants.fadeDuration)
    })
    words.sort { $0.characterRange.lowerBound < $1.characterRange.lowerBound }

    if words.count > ChatStreamingRevealConstants.maximumFadingWords {
        words.removeFirst(words.count - ChatStreamingRevealConstants.maximumFadingWords)
    }

    let spacing: TimeInterval
    if words.count > 1 {
        let catchUpSpacing =
            (ChatStreamingRevealConstants.maximumCatchUpDuration - ChatStreamingRevealConstants.fadeDuration)
            / Double(words.count - 1)
        spacing = min(ChatStreamingRevealConstants.wordInterval, catchUpSpacing)
    } else {
        spacing = 0
    }

    words = words.enumerated().map { index, word in
        let scheduledStart = now + Double(index) * spacing
        let scheduledDeadline = scheduledStart + ChatStreamingRevealConstants.fadeDuration
        let isExistingWord = trackedStarts.contains(word.characterRange.lowerBound)
        return ChatStreamingRevealState.Word(
            characterRange: word.characterRange,
            fadeStart: isExistingWord ? word.fadeStart : scheduledStart,
            deadline: isExistingWord ? min(word.deadline, scheduledDeadline) : scheduledDeadline)
    }

    return ChatStreamingRevealState(text: newText, words: words)
}

public func revealedOpacities(
    state: ChatStreamingRevealState,
    now: TimeInterval) -> ChatStreamingRevealFrame
{
    let fading = state.words.compactMap { word -> ChatStreamingRevealFrame.FadingWord? in
        guard now < word.deadline else { return nil }
        let duration = word.deadline - word.fadeStart
        let opacity = duration > 0
            ? min(1, max(0, (now - word.fadeStart) / duration))
            : 1
        return ChatStreamingRevealFrame.FadingWord(
            characterRange: word.characterRange,
            opacity: opacity)
    }
    return ChatStreamingRevealFrame(
        fullyRevealedPrefixCharacterOffset: fading.first?.characterRange.lowerBound ?? state.text.count,
        fading: fading)
}

public func chatStreamingWordRanges(in text: String) -> [Range<Int>] {
    var ranges: [Range<Int>] = []
    var wordStart: Int?

    for (offset, character) in text.enumerated() {
        if character.isWhitespace {
            if let start = wordStart {
                ranges.append(start..<offset)
                wordStart = nil
            }
        } else if wordStart == nil {
            wordStart = offset
        }
    }
    if let wordStart {
        ranges.append(wordStart..<text.count)
    }
    return ranges
}
