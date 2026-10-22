import Foundation
import Testing
@testable import MartinKit

struct MarkdownTests {
    typealias Line = Markdown.Line

    static func spans(_ text: String) -> [String] {
        Line(text).spans.map { span in
            let role = switch span.role {
            case .link(let destination): "link→" + (text as NSString).substring(with: destination)
            default: "\(span.role)"
            }
            return role + " " + (text as NSString).substring(with: span.range)
        }
    }

    static func continuation(_ text: String) -> String? {
        Line(text).continuation(in: text)
    }

    @Test func blocksAndTheirPrefixes() {
        let expectations: [(String, Line.Block, Int)] = [
            ("# Title", .heading(1), 2),
            ("### Third", .heading(3), 4),
            ("#hashtag", .text, 0),
            ("- item", .list, 2),
            ("  - nested", .list, 4),
            ("12. twelve", .list, 4),
            ("- [ ] todo", .task(done: false), 6),
            ("* [x] done", .task(done: true), 6),
            ("> quoted", .quote, 2),
            ("> > nested", .quote, 4),
            ("---", .rule, 0),
            ("* * *", .rule, 0),
            ("```swift", .fence, 0),
            ("   ", .blank, 3),
            ("plain words", .text, 0),
            ("    indented", .text, 4),
        ]
        for (text, block, prefix) in expectations {
            let line = Line(text)
            #expect(line.block == block, "\(text)")
            #expect(line.prefix == prefix, "\(text)")
        }
        #expect(Line("  - nested").indent == 2)
        #expect(Line("**not code**", code: true).block == .code)
        #expect(Line("**not code**", code: true).spans.isEmpty)
        #expect(Line("   - inside a fence", code: true).prefix == 3)
    }

    @Test func markersAreSeparateFromContent() {
        #expect(Self.spans("## Notes") == ["marker ##"])
        #expect(Self.spans("- [x] Ship it") == ["marker -", "checkbox [x]"])
        #expect(Self.spans("**bold** and *it*") == [
            "strong **bold**", "marker **", "marker **",
            "emphasis *it*", "marker *", "marker *",
        ])
        #expect(Self.spans("~~gone~~") == ["strikethrough ~~gone~~", "marker ~~", "marker ~~"])
        #expect(Self.spans("***both***") == ["strong ***both***", "emphasis ***both***", "marker ***", "marker ***"])
    }

    @Test func codeSpansShieldTheirContents() {
        #expect(Self.spans("`**not bold**`") == ["code `**not bold**`", "marker `", "marker `"])
        #expect(Self.spans("``a ` tick``") == ["code ``a ` tick``", "marker ``", "marker ``"])
    }

    @Test func linksPointAtTheirDestination() {
        #expect(Self.spans("- Fix [#1](https://github.com/acme/api/pull/1)") == [
            "marker -",
            "marker [", "link→https://github.com/acme/api/pull/1 #1", "marker ](", "url https://github.com/acme/api/pull/1", "marker )",
        ])
        #expect(Self.spans("see https://example.com/a_b_c.") == ["link→https://example.com/a_b_c https://example.com/a_b_c"])
    }

    @Test func intrawordDelimitersStayPlain() {
        #expect(Self.spans("snake_case_name and 2 * 3 * 4").isEmpty)
        #expect(Self.spans("an **unclosed bold").isEmpty)
    }

    @Test func codeBlocksSpanFenceToFence() {
        let text = "a\n```swift\nlet x = 1\n```\nb\n~~~\nopen"
        let blocks = Markdown.codeBlocks(in: text).map { (text as NSString).substring(with: $0) }
        #expect(blocks == ["```swift\nlet x = 1\n```\n", "~~~\nopen"])
        #expect(Markdown.codeBlocks(in: "````\n```\n````").count == 1)
        #expect(Markdown.codeBlocks(in: "~~~\n```\n").map(\.length) == [8])
    }

    @Test func continuationRepeatsListMarkers() {
        #expect(Self.continuation("- item") == "- ")
        #expect(Self.continuation("  * deep") == "  * ")
        #expect(Self.continuation("- [x] done") == "- [ ] ")
        #expect(Self.continuation("9. nine") == "10. ")
        #expect(Self.continuation("1) [X] first") == "2) [ ] ")
        #expect(Self.continuation("> said") == "> ")
        #expect(Self.continuation("# Heading") == nil)
        #expect(Self.continuation("words") == nil)
        #expect(Line("- not a list", code: true).continuation(in: "- not a list") == nil)
    }

    @Test func toggleWrapsAndUnwraps() {
        let wrapped = Markdown.toggle("**", in: "say word now", selection: NSRange(location: 4, length: 4))
        #expect(wrapped == Markdown.Edit(range: NSRange(location: 4, length: 4), replacement: "**word**", selection: NSRange(location: 6, length: 4)))
        let unwrapped = Markdown.toggle("**", in: "say **word** now", selection: NSRange(location: 6, length: 4))
        #expect(unwrapped == Markdown.Edit(range: NSRange(location: 4, length: 8), replacement: "word", selection: NSRange(location: 4, length: 4)))
        let inner = Markdown.toggle("`", in: "`x`", selection: NSRange(location: 0, length: 3))
        #expect(inner == Markdown.Edit(range: NSRange(location: 0, length: 3), replacement: "x", selection: NSRange(location: 0, length: 1)))
        let empty = Markdown.toggle("~~", in: "", selection: NSRange(location: 0, length: 0))
        #expect(empty == Markdown.Edit(range: NSRange(location: 0, length: 0), replacement: "~~~~", selection: NSRange(location: 2, length: 0)))
    }

    @Test func linkWrapsTheSelection() {
        #expect(Markdown.link(in: "ask Martin", selection: NSRange(location: 4, length: 6)) == Markdown.Edit(range: NSRange(location: 4, length: 6), replacement: "[Martin]()", selection: NSRange(location: 13, length: 0)))
        #expect(Markdown.link(in: "", selection: NSRange(location: 0, length: 0)).selection == NSRange(location: 1, length: 0))
    }

    @Test func tenThousandWordsParseQuickly() {
        let section = """
        ## Section heading

        A paragraph with **bold**, *italic*, `code`, ~~struck~~ words and a [link](https://example.com/path) to read.
        - [ ] A task for someone with a few more words in it
        - A bullet point that runs on for a little while longer
        > A quote that someone said during the meeting today

        ```swift
        let answer = 42
        ```

        """
        let document = String(repeating: section, count: 10_000 / section.split(whereSeparator: \.isWhitespace).count + 1)
        #expect(document.split(whereSeparator: \.isWhitespace).count >= 10_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = Markdown.codeBlocks(in: document)
            document.enumerateLines { line, _ in _ = Line(line) }
        }
        #expect(elapsed < .milliseconds(500), "\(elapsed)")
    }
}
