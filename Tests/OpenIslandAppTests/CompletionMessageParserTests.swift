import Testing
@testable import OpenIslandApp

struct CompletionMessageParserTests {
    @Test
    func leavesPlainMarkdownUntouched() {
        let source = "Implemented **three fixes** and updated `price = $5`."

        #expect(CompletionMessageParser.segments(in: source) == [.markdown(source)])
    }

    @Test
    func extractsInlineAndDisplayMath() {
        let source = "Euler wrote $e^{i\\pi} + 1 = 0$.\n\n$$\\int_0^1 x^2 dx$$"

        #expect(CompletionMessageParser.segments(in: source) == [
            .markdown("Euler wrote "),
            .math("e^{i\\pi} + 1 = 0", display: false),
            .markdown(".\n\n"),
            .math("\\int_0^1 x^2 dx", display: true),
        ])
    }

    @Test
    func supportsLatexStyleDelimiters() {
        let source = "Solve \\(x^2 = 4\\), then show:\n\\[x = \\pm 2\\]"

        #expect(CompletionMessageParser.segments(in: source) == [
            .markdown("Solve "),
            .math("x^2 = 4", display: false),
            .markdown(", then show:\n"),
            .math("x = \\pm 2", display: true),
        ])
    }

    @Test
    func supportsMathCodeFences() {
        let source = "Result:\n```math\n\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\n```\nDone."

        #expect(CompletionMessageParser.segments(in: source) == [
            .markdown("Result:\n"),
            .math("\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", display: true),
            .markdown("\nDone."),
        ])
    }

    @Test
    func ignoresMathDelimitersInsideCodeAndEscapedDollars() {
        let source = "Use `$x$`, then:\n```swift\nlet value = \"$$x$$\"\n```\nCost: \\$5"

        #expect(CompletionMessageParser.segments(in: source) == [.markdown(source)])
    }

    @Test
    func leavesMalformedAndMultilineInlineMathUntouched() {
        let source = "Unclosed $x and invalid $x\ny$ remain prose."

        #expect(CompletionMessageParser.segments(in: source) == [.markdown(source)])
    }
}
