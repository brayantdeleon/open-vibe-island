import AppKit
import MarkdownUI
import SwiftMath
import SwiftUI

enum CompletionMessageSegment: Equatable, Sendable {
    case markdown(String)
    case math(String, display: Bool)
}

enum CompletionMessageParser {
    static func segments(in source: String) -> [CompletionMessageSegment] {
        var result: [CompletionMessageSegment] = []
        var markdownStart = source.startIndex
        var cursor = source.startIndex

        func appendMarkdown(endingAt end: String.Index) {
            guard markdownStart < end else { return }
            append(.markdown(String(source[markdownStart..<end])), to: &result)
        }

        while cursor < source.endIndex {
            if let match = mathMatch(in: source, startingAt: cursor) {
                appendMarkdown(endingAt: cursor)
                result.append(.math(match.contents, display: match.display))
                cursor = match.endIndex
                markdownStart = cursor
                continue
            }

            if source[cursor] == "`" {
                cursor = endOfCodeSpanOrFence(in: source, startingAt: cursor)
                continue
            }

            cursor = source.index(after: cursor)
        }

        appendMarkdown(endingAt: source.endIndex)
        return result
    }

    private struct MathMatch {
        let contents: String
        let display: Bool
        let endIndex: String.Index
    }

    private static func mathMatch(in source: String, startingAt start: String.Index) -> MathMatch? {
        guard !isEscaped(start, in: source) else { return nil }

        if source[start...].hasPrefix("```math") && isAtLineStart(start, in: source) {
            let headerEnd = source.index(start, offsetBy: 7)
            guard headerEnd == source.endIndex || source[headerEnd].isNewline else { return nil }
            let contentsStart = headerEnd < source.endIndex ? source.index(after: headerEnd) : headerEnd
            guard let closing = source[contentsStart...].range(of: "```"),
                  isAtLineStart(closing.lowerBound, in: source)
            else { return nil }
            let contents = source[contentsStart..<closing.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !contents.isEmpty else { return nil }
            return MathMatch(
                contents: contents,
                display: true,
                endIndex: closing.upperBound
            )
        }

        let opening: String
        let closing: String
        let display: Bool
        if source[start...].hasPrefix("$$") {
            opening = "$$"
            closing = "$$"
            display = true
        } else if source[start...].hasPrefix("\\[") {
            opening = "\\["
            closing = "\\]"
            display = true
        } else if source[start...].hasPrefix("\\(") {
            opening = "\\("
            closing = "\\)"
            display = false
        } else if source[start] == "$" {
            opening = "$"
            closing = "$"
            display = false
        } else {
            return nil
        }

        let contentsStart = source.index(start, offsetBy: opening.count)
        guard contentsStart < source.endIndex,
              !source[contentsStart].isWhitespace,
              let closingRange = firstUnescapedRange(of: closing, in: source, startingAt: contentsStart)
        else { return nil }

        let contents = source[contentsStart..<closingRange.lowerBound]
        guard !contents.isEmpty,
              contents.last?.isWhitespace != true,
              !contents.contains("\n") || display
        else { return nil }

        return MathMatch(
            contents: String(contents),
            display: display,
            endIndex: closingRange.upperBound
        )
    }

    private static func firstUnescapedRange(
        of delimiter: String,
        in source: String,
        startingAt start: String.Index
    ) -> Range<String.Index>? {
        var searchStart = start
        while searchStart < source.endIndex,
              let range = source[searchStart...].range(of: delimiter)
        {
            if !isEscaped(range.lowerBound, in: source) {
                return range
            }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func endOfCodeSpanOrFence(in source: String, startingAt start: String.Index) -> String.Index {
        var openingEnd = start
        while openingEnd < source.endIndex, source[openingEnd] == "`" {
            openingEnd = source.index(after: openingEnd)
        }
        let delimiter = String(source[start..<openingEnd])
        guard let closing = source[openingEnd...].range(of: delimiter) else {
            return openingEnd
        }
        return closing.upperBound
    }

    private static func isEscaped(_ index: String.Index, in source: String) -> Bool {
        var cursor = index
        var slashCount = 0
        while cursor > source.startIndex {
            let previous = source.index(before: cursor)
            guard source[previous] == "\\" else { break }
            slashCount += 1
            cursor = previous
        }
        return slashCount.isMultiple(of: 2) == false
    }

    private static func isAtLineStart(_ index: String.Index, in source: String) -> Bool {
        index == source.startIndex || source[source.index(before: index)].isNewline
    }

    private static func append(_ segment: CompletionMessageSegment, to result: inout [CompletionMessageSegment]) {
        if case let .markdown(newText) = segment,
           case let .markdown(existingText)? = result.last
        {
            result[result.count - 1] = .markdown(existingText + newText)
        } else {
            result.append(segment)
        }
    }
}

struct CompletionMessageView: View {
    let text: String

    var body: some View {
        let blocks = CompletionMessagePresentation.blocks(
            from: CompletionMessageParser.segments(in: text)
        )
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .markdown(markdown):
                    Markdown(markdown)
                        .markdownTheme(.completionCard)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .inline(pieces):
                    CompletionInlineMathText(pieces: pieces)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .displayMath(latex):
                    CompletionMathView(latex: latex, display: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                }
            }
        }
    }
}

private enum CompletionMessageBlock {
    case markdown(String)
    case inline([CompletionMessageSegment])
    case displayMath(String)
}

private enum CompletionMessagePresentation {
    static func blocks(from segments: [CompletionMessageSegment]) -> [CompletionMessageBlock] {
        var blocks: [CompletionMessageBlock] = []
        var index = 0

        while index < segments.count {
            switch segments[index] {
            case let .markdown(markdown):
                appendMarkdown(markdown, to: &blocks)
                index += 1

            case let .math(latex, display: true):
                blocks.append(.displayMath(latex))
                index += 1

            case .math(_, display: false):
                var pieces: [CompletionMessageSegment] = []
                pullCurrentLineFromLastMarkdownBlock(into: &pieces, blocks: &blocks)

                var trailingMarkdown: String?
                while index < segments.count {
                    switch segments[index] {
                    case let .math(latex, display: false):
                        pieces.append(.math(latex, display: false))
                        index += 1

                    case .math(_, display: true):
                        break

                    case let .markdown(markdown):
                        if let newline = markdown.firstIndex(where: \.isNewline) {
                            let line = String(markdown[..<newline])
                            if !line.isEmpty {
                                pieces.append(.markdown(line))
                            }
                            let remainderStart = markdown.index(after: newline)
                            trailingMarkdown = String(markdown[remainderStart...])
                            index += 1
                            break
                        }
                        pieces.append(.markdown(markdown))
                        index += 1
                        continue
                    }
                    break
                }

                blocks.append(.inline(pieces))
                if let trailingMarkdown {
                    appendMarkdown(trailingMarkdown, to: &blocks)
                }
            }
        }

        return blocks
    }

    private static func pullCurrentLineFromLastMarkdownBlock(
        into pieces: inout [CompletionMessageSegment],
        blocks: inout [CompletionMessageBlock]
    ) {
        guard case let .markdown(markdown)? = blocks.last else { return }
        blocks.removeLast()

        if let newline = markdown.lastIndex(where: \.isNewline) {
            let prefix = String(markdown[..<newline])
            let lineStart = markdown.index(after: newline)
            let line = String(markdown[lineStart...])
            appendMarkdown(prefix, to: &blocks)
            if !line.isEmpty {
                pieces.append(.markdown(line))
            }
        } else if !markdown.isEmpty {
            pieces.append(.markdown(markdown))
        }
    }

    private static func appendMarkdown(_ markdown: String, to blocks: inout [CompletionMessageBlock]) {
        guard !markdown.isEmpty else { return }
        if case let .markdown(existing)? = blocks.last {
            blocks[blocks.count - 1] = .markdown(existing + "\n" + markdown)
        } else {
            blocks.append(.markdown(markdown))
        }
    }
}

private struct CompletionInlineMathText: View {
    let pieces: [CompletionMessageSegment]

    var body: some View {
        renderedText
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.88))
    }

    private var renderedText: Text {
        pieces.reduce(Text("")) { partial, piece in
            switch piece {
            case let .markdown(markdown):
                let attributed = (try? AttributedString(
                    markdown: markdown,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )) ?? AttributedString(markdown)
                return partial + Text(attributed)

            case let .math(latex, display: false):
                let renderer = MTMathImage(
                    latex: latex,
                    fontSize: 14,
                    textColor: NSColor.white.withAlphaComponent(0.88),
                    labelMode: .text,
                    textAlignment: .left
                )
                guard let image = renderer.asImage().1 else {
                    return partial + Text("$\(latex)$")
                }
                return partial + Text(Image(nsImage: image)).baselineOffset(-2)

            case let .math(latex, display: true):
                return partial + Text("$$\(latex)$$")
            }
        }
    }
}

private struct CompletionMathView: NSViewRepresentable {
    let latex: String
    let display: Bool

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateNSView(_ label: MTMathUILabel, context: Context) {
        let fontSize: CGFloat = display ? 16 : 14
        let font = MTFontManager().font(withName: MathFont.latinModernFont.rawValue, size: fontSize)
        label.font = font
        label.latex = latex
        label.labelMode = display ? .display : .text
        label.textAlignment = .left
        label.textColor = NSColor.white.withAlphaComponent(0.88)
        label.contentInsets = MTEdgeInsets()
        label.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MTMathUILabel,
        context: Context
    ) -> CGSize? {
        nsView.fittingSize
    }
}
