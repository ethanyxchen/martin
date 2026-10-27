import Foundation
import Testing
@testable import MartinKit

struct MarkdownTests {
    typealias Line = Markdown.Line

    static func spans(_ text: String) -> [String] {
        Line(text).spans.map { span in
            let role = switch span.role {
            case .link(let destination): "link→" + (text as NSString).substring(with: destination)
            case .mention(let label): "mention→" + (text as NSString).substring(with: label)
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
            ("# Title", .heading, 2),
            ("### Third", .heading, 4),
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
        #expect(Line("- top").depth == 0)
        #expect(Line("  - nested").depth == 1)
        #expect(Line("\t\t- tabbed").depth == 2)
        #expect(Line("    - spaced").depth == 2)
        #expect(Line("   1. under a number").depth == 1)
        #expect(Line("**not code**", code: true).block == .code)
        #expect(Line("**not code**", code: true).spans.isEmpty)
        #expect(Line("   - inside a fence", code: true).prefix == 3)
    }

    @Test func markersAreSeparateFromContent() {
        #expect(Self.spans("## Notes") == ["marker ##"])
        #expect(Self.spans("- [x] Ship it") == ["bullet -", "checkbox [x]"])
        #expect(Self.spans("* item") == ["bullet *"])
        #expect(Self.spans("3. third") == ["marker 3."])
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
            "bullet -",
            "marker [", "link→https://github.com/acme/api/pull/1 #1", "marker ](", "url https://github.com/acme/api/pull/1", "marker )",
        ])
        #expect(Self.spans("see https://example.com/a_b_c.") == ["link→https://example.com/a_b_c https://example.com/a_b_c"])
    }

    @Test func mentionsShowTheirNameOrTheEmailsLocalPart() {
        #expect(Self.spans("- ask @{Kim K <kim.k@goodnotes.com>} **now**") == [
            "bullet -", "mention→Kim K @{Kim K <kim.k@goodnotes.com>}", "strong **now**", "marker **", "marker **",
        ])
        #expect(Self.spans("cc @{inamiy@goodnotes.com}, @{snake_case_dev@x.com}") == [
            "mention→inamiy @{inamiy@goodnotes.com}", "mention→snake_case_dev @{snake_case_dev@x.com}",
        ])
        #expect(Self.spans("@{Kim <kim.k@goodnotes.com}").isEmpty)
        #expect(Self.spans("@{no email}").isEmpty)
        #expect(Self.spans("`@{kim@x.com}`") == ["code `@{kim@x.com}`", "marker `", "marker `"])
    }

    @Test func mentionQueryIsTheAtWordBeforeTheCaret() {
        func query(_ text: String, at caret: Int? = nil, code: Bool = false) -> String? {
            Line(text, code: code).mentionQuery(in: text, at: caret ?? (text as NSString).length).map { (text as NSString).substring(with: $0) }
        }
        #expect(query("@") == "@")
        #expect(query("- [ ] ask @kim.k") == "@kim.k")
        #expect(query("(@ki") == "@ki")
        #expect(query("ask @kim later", at: 7) == "@ki")
        #expect(query("ask @kim later") == nil)
        #expect(query("mail kim@goodnotes") == nil)
        #expect(query("`@kim`", at: 5) == nil)
        #expect(query("@kim", code: true) == nil)
        #expect(query("@{kim@x.com}", at: 6) == nil)
        #expect(query("@{kim@x.com} @k") == "@k")
    }

    @Test func referenceLinksResolveOnlyWhenDefined() {
        let references = Markdown.references(in: "- Fix [#412]\n\n[#412]: https://x.dev/412\n[Docs]: https://x.dev/docs \"Title\"")
        #expect(references == ["#412": "https://x.dev/412", "docs": "https://x.dev/docs"])
        func spans(_ text: String) -> [String] {
            Line(text, references: references).spans.map { "\($0.role) " + (text as NSString).substring(with: $0.range) }
        }
        #expect(spans("Fix [#412] now") == ["marker [", "reference(destination: \"https://x.dev/412\") #412", "marker ]"])
        #expect(spans("Read [the guide][DOCS]") == ["marker [", "reference(destination: \"https://x.dev/docs\") the guide", "marker ][DOCS]"])
        #expect(spans("Not a link [sic] here").isEmpty)
        #expect(Self.spans("Support [ in names [docs](https://x.dev)") == ["marker [", "link→https://x.dev docs", "marker ](", "url https://x.dev", "marker )"])
        #expect(spans("Support [ in names [#412]") == ["marker [", "reference(destination: \"https://x.dev/412\") #412", "marker ]"])
        #expect(Line("[#412]: https://x.dev/412").block == .definition)
        #expect(spans("[#412]: https://x.dev/412") == ["marker [#412]:", "url https://x.dev/412"])
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

    @Test func indentNestsAndUnnestsTheLine() {
        let text = "- a\n\t- b\n  - c\n- d"
        func indent(_ location: Int, length: Int, outward: Bool) -> Markdown.Edit? {
            Markdown.indent(NSRange(location: location, length: length), in: text, selection: NSRange(location: location + length, length: 0), outward: outward)
        }
        #expect(indent(14, length: 3, outward: false) == Markdown.Edit(range: NSRange(location: 14, length: 0), replacement: "\t", selection: NSRange(location: 18, length: 0)))
        #expect(indent(4, length: 4, outward: true) == Markdown.Edit(range: NSRange(location: 4, length: 1), replacement: "", selection: NSRange(location: 7, length: 0)))
        #expect(indent(9, length: 5, outward: true) == Markdown.Edit(range: NSRange(location: 9, length: 2), replacement: "", selection: NSRange(location: 12, length: 0)))
        #expect(indent(14, length: 3, outward: true) == nil)
    }

    @Test func toggleWrapsAndUnwraps() {
        let wrapped = Markdown.toggle("**", in: "say word now", selection: NSRange(location: 4, length: 4))
        #expect(wrapped == Markdown.Edit(range: NSRange(location: 4, length: 4), replacement: "**word**", selection: NSRange(location: 6, length: 4)))
        let unwrapped = Markdown.toggle("**", in: "say **word** now", selection: NSRange(location: 6, length: 4))
        #expect(unwrapped == Markdown.Edit(range: NSRange(location: 4, length: 8), replacement: "word", selection: NSRange(location: 4, length: 4)))
        let inner = Markdown.toggle("`", in: "`x`", selection: NSRange(location: 0, length: 3))
        #expect(inner == Markdown.Edit(range: NSRange(location: 0, length: 3), replacement: "x", selection: NSRange(location: 0, length: 1)))
        #expect(Markdown.toggle("*", in: "**foo**", selection: NSRange(location: 2, length: 3)) == Markdown.Edit(range: NSRange(location: 2, length: 3), replacement: "*foo*", selection: NSRange(location: 3, length: 3)))
        #expect(Markdown.toggle("*", in: "**foo**", selection: NSRange(location: 0, length: 7)) == Markdown.Edit(range: NSRange(location: 0, length: 7), replacement: "***foo***", selection: NSRange(location: 1, length: 7)))
        #expect(Markdown.toggle("*", in: "***foo***", selection: NSRange(location: 3, length: 3)) == Markdown.Edit(range: NSRange(location: 2, length: 5), replacement: "foo", selection: NSRange(location: 2, length: 3)))
        #expect(Markdown.toggle("**", in: "***foo***", selection: NSRange(location: 3, length: 3)) == Markdown.Edit(range: NSRange(location: 1, length: 7), replacement: "foo", selection: NSRange(location: 1, length: 3)))
        #expect(Markdown.toggle("~~", in: "~~~foo~~~", selection: NSRange(location: 3, length: 3)) == Markdown.Edit(range: NSRange(location: 1, length: 7), replacement: "foo", selection: NSRange(location: 1, length: 3)))
        #expect(Markdown.toggle("`", in: "``x``", selection: NSRange(location: 0, length: 5)) == Markdown.Edit(range: NSRange(location: 0, length: 5), replacement: "`x`", selection: NSRange(location: 0, length: 3)))
        let empty = Markdown.toggle("~~", in: "", selection: NSRange(location: 0, length: 0))
        #expect(empty == Markdown.Edit(range: NSRange(location: 0, length: 0), replacement: "~~~~", selection: NSRange(location: 2, length: 0)))
    }

    @Test func linkWrapsTheSelection() {
        #expect(Markdown.link(in: "ask Martin", selection: NSRange(location: 4, length: 6)) == Markdown.Edit(range: NSRange(location: 4, length: 6), replacement: "[Martin]()", selection: NSRange(location: 13, length: 0)))
        #expect(Markdown.link(in: "", selection: NSRange(location: 0, length: 0)).selection == NSRange(location: 1, length: 0))
    }

    @Test func rangesMoveAcrossEdits() {
        let insertAtFive = (edit: NSRange(location: 5, length: 3), delta: 3)
        #expect(NSRange(location: 0, length: 2).moved(across: insertAtFive.edit, by: insertAtFive.delta) == NSRange(location: 0, length: 2))
        #expect(NSRange(location: 0, length: 5).moved(across: insertAtFive.edit, by: insertAtFive.delta) == NSRange(location: 0, length: 5))
        #expect(NSRange(location: 5, length: 0).moved(across: insertAtFive.edit, by: insertAtFive.delta) == NSRange(location: 8, length: 0))
        #expect(NSRange(location: 6, length: 4).moved(across: insertAtFive.edit, by: insertAtFive.delta) == NSRange(location: 9, length: 4))
        #expect(NSRange(location: 5, length: 2).moved(across: insertAtFive.edit, by: insertAtFive.delta) == NSRange(location: 8, length: 2))
        #expect(NSRange(location: 0, length: 5).moved(across: insertAtFive.edit, by: insertAtFive.delta, growing: true) == NSRange(location: 0, length: 8))
        let deleteTwoToFive = (edit: NSRange(location: 2, length: 0), delta: -3)
        #expect(NSRange(location: 3, length: 5).moved(across: deleteTwoToFive.edit, by: deleteTwoToFive.delta) == NSRange(location: 2, length: 3))
        #expect(NSRange(location: 8, length: 0).moved(across: deleteTwoToFive.edit, by: deleteTwoToFive.delta) == NSRange(location: 5, length: 0))
        let replaceTwoToFive = (edit: NSRange(location: 2, length: 6), delta: 3)
        #expect(NSRange(location: 3, length: 0).moved(across: replaceTwoToFive.edit, by: replaceTwoToFive.delta) == NSRange(location: 8, length: 0))
        #expect(NSRange(location: 2, length: 0).moved(across: replaceTwoToFive.edit, by: replaceTwoToFive.delta) == NSRange(location: 8, length: 0))
        #expect(NSRange(location: 0, length: 4).moved(across: replaceTwoToFive.edit, by: replaceTwoToFive.delta) == NSRange(location: 0, length: 8))
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
