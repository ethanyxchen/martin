import Foundation

public enum Markdown {
    public struct Line: Equatable, Sendable {
        public enum Block: Equatable, Sendable {
            case text, blank, heading, list, task(done: Bool), quote, fence, code, rule, definition
        }

        public enum Role: Equatable, Sendable {
            case marker, bullet, checkbox, strong, emphasis, strikethrough, code, link(destination: NSRange), reference(destination: String), url
        }

        public struct Span: Equatable, Sendable {
            public let role: Role
            public let range: NSRange

            init(_ role: Role, _ range: NSRange) {
                self.role = role
                self.range = range
            }
        }

        public let block: Block
        public let depth: Int
        public let prefix: Int
        public let spans: [Span]

        public init(_ text: String, code: Bool = false, references: [String: String] = [:]) {
            let line = text as NSString
            let whole = NSRange(location: 0, length: line.length)
            let start = line.rangeOfCharacter(from: CharacterSet(charactersIn: " \t").inverted).location
            let indent = start == NSNotFound ? line.length : start
            depth = line.substring(to: indent).reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
            if code {
                (block, prefix, spans) = (.code, indent, [])
            } else if indent == line.length {
                (block, prefix, spans) = (.blank, indent, [])
            } else if Fence(line, whole) != nil {
                (block, prefix, spans) = (.fence, indent, [Span(.marker, whole)])
            } else if Pattern.rule.firstMatch(in: text, options: .anchored, range: whole) != nil {
                (block, prefix, spans) = (.rule, indent, [Span(.marker, whole)])
            } else if let definition = Pattern.definition.firstMatch(in: text, options: .anchored, range: whole) {
                (block, prefix, spans) = (.definition, indent, [Span(.marker, definition.range(at: 1)), Span(.url, definition.range(at: 3))])
            } else {
                let (block, prefix, markers) = Self.block(of: text, in: whole, indent: indent)
                let content = NSRange(location: prefix, length: line.length - prefix)
                (self.block, self.prefix, spans) = (block, prefix, markers + Self.inline(text, in: content, references: references))
            }
        }

        public func continuation(in text: String) -> String? {
            switch block {
            case .list, .task, .quote: break
            default: return nil
            }
            let prefix = NSMutableString(string: (text as NSString).substring(to: self.prefix))
            if let checkbox = spans.first(where: { $0.role == .checkbox }) {
                prefix.replaceCharacters(in: checkbox.range, with: "[ ]")
            }
            if let marker = spans.first(where: { $0.role == .marker }), let number = Int(prefix.substring(with: marker.range).dropLast()) {
                prefix.replaceCharacters(in: NSRange(location: marker.range.location, length: marker.range.length - 1), with: String(number + 1))
            }
            return prefix as String
        }

        private static func block(of text: String, in whole: NSRange, indent: Int) -> (Block, Int, [Span]) {
            func match(_ pattern: NSRegularExpression) -> NSTextCheckingResult? {
                pattern.firstMatch(in: text, options: .anchored, range: whole)
            }
            if let heading = match(Pattern.heading) {
                return (.heading, heading.range.length, [Span(.marker, heading.range(at: 1))])
            }
            if let quote = match(Pattern.quote) {
                return (.quote, quote.range.length, [Span(.marker, quote.range(at: 1))])
            }
            func marker(_ range: NSRange) -> Span {
                Span(range.length == 1 ? .bullet : .marker, range)
            }
            if let task = match(Pattern.task) {
                let done = (text as NSString).substring(with: task.range(at: 3)) != "[ ]"
                return (.task(done: done), task.range.length, [marker(task.range(at: 2)), Span(.checkbox, task.range(at: 3))])
            }
            if let list = match(Pattern.list) {
                return (.list, list.range.length, [marker(list.range(at: 2))])
            }
            return (.text, indent, [])
        }

        private static func inline(_ text: String, in content: NSRange, references: [String: String]) -> [Span] {
            var spans: [Span] = []
            var claimed: [NSRange] = []
            func free(_ ranges: NSRange...) -> Bool {
                ranges.allSatisfy { range in claimed.allSatisfy { NSIntersectionRange($0, range).length == 0 } }
            }

            for match in Pattern.code.matches(in: text, range: content) {
                let ticks = match.range(at: 1)
                spans += [Span(.code, match.range), Span(.marker, ticks), Span(.marker, NSRange(location: NSMaxRange(match.range) - ticks.length, length: ticks.length))]
                claimed.append(match.range)
            }
            for match in Pattern.link.matches(in: text, range: content) {
                let target = NSUnionRange(match.range(at: 3), match.range(at: 5))
                guard free(match.range(at: 1), target) else { continue }
                let destination = match.range(at: 4)
                spans += [
                    Span(.marker, match.range(at: 1)),
                    Span(.link(destination: destination), match.range(at: 2)),
                    Span(.marker, match.range(at: 3)),
                    Span(.url, destination),
                    Span(.marker, match.range(at: 5)),
                ]
                claimed += [match.range(at: 1), target]
            }
            for match in Pattern.reference.matches(in: text, range: content) {
                let label = match.range(at: 2), target = NSUnionRange(match.range(at: 3), match.range(at: 5))
                let name = (text as NSString).substring(with: match.range(at: 4).length > 0 ? match.range(at: 4) : label)
                guard free(match.range), let destination = references[Markdown.label(name)] else { continue }
                spans += [Span(.marker, match.range(at: 1)), Span(.reference(destination: destination), label), Span(.marker, target)]
                claimed.append(match.range)
            }
            for match in Pattern.shortcut.matches(in: text, range: content) {
                let label = match.range(at: 2)
                guard free(match.range), let destination = references[Markdown.label((text as NSString).substring(with: label))] else { continue }
                spans += [Span(.marker, match.range(at: 1)), Span(.reference(destination: destination), label), Span(.marker, match.range(at: 3))]
                claimed.append(match.range)
            }
            for match in Pattern.address.matches(in: text, range: content) where free(match.range) {
                spans.append(Span(.link(destination: match.range), match.range))
                claimed.append(match.range)
            }
            for (pattern, roles, width) in Pattern.delimited {
                for match in pattern.matches(in: text, range: content) {
                    let open = NSRange(location: match.range.location, length: width)
                    let close = NSRange(location: NSMaxRange(match.range) - width, length: width)
                    guard free(open, close) else { continue }
                    spans += roles.map { Span($0, match.range) } + [Span(.marker, open), Span(.marker, close)]
                    claimed += [open, close]
                }
            }
            return spans
        }
    }

    public struct Edit: Equatable, Sendable {
        public let range: NSRange
        public let replacement: String
        public let selection: NSRange

        public init(range: NSRange, replacement: String, selection: NSRange) {
            self.range = range
            self.replacement = replacement
            self.selection = selection
        }
    }

    public static func codeBlocks(in text: String) -> [NSRange] {
        let text = text as NSString
        var blocks: [NSRange] = []
        var open: (fence: Fence, start: Int)?
        var location = 0
        while location < text.length {
            var end = 0, contentsEnd = 0
            text.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let fence = Fence(text, NSRange(location: location, length: contentsEnd - location))
            if let current = open {
                if let fence, fence.closes(current.fence) {
                    blocks.append(NSRange(location: current.start, length: end - current.start))
                    open = nil
                }
            } else if let fence {
                open = (fence, location)
            }
            location = end
        }
        if let open { blocks.append(NSRange(location: open.start, length: text.length - open.start)) }
        return blocks
    }

    public static func references(in text: String) -> [String: String] {
        let source = text as NSString
        var references: [String: String] = [:]
        var location = 0
        while location < source.length {
            var end = 0, contentsEnd = 0
            source.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = NSRange(location: location, length: contentsEnd - location)
            if let start = source.blockStart(in: line), source.character(at: start) == 0x5B,
               let match = Pattern.definition.firstMatch(in: text, options: .anchored, range: line) {
                let name = label(source.substring(with: match.range(at: 2)))
                if references[name] == nil { references[name] = source.substring(with: match.range(at: 3)) }
            }
            location = end
        }
        return references
    }

    public static func mayBeHeading(_ line: NSRange, in text: NSString) -> Bool {
        text.blockStart(in: line).map { text.character(at: $0) == 0x23 } ?? false
    }

    static func label(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func toggle(_ delimiter: String, in text: String, selection: NSRange) -> Edit {
        let text = text as NSString
        let width = (delimiter as NSString).length
        let mark = (delimiter as NSString).character(at: 0)
        func run(from location: Int, by step: Int, within bounds: NSRange) -> Int {
            var count = 0
            while NSLocationInRange(location + count * step, bounds), text.character(at: location + count * step) == mark { count += 1 }
            return count
        }
        func wraps(_ run: Int) -> Bool {
            mark == 0x2A ? run == width || run >= 3 : run >= width
        }
        let document = NSRange(location: 0, length: text.length)
        if wraps(min(run(from: selection.location - 1, by: -1, within: document), run(from: NSMaxRange(selection), by: 1, within: document))) {
            let range = NSRange(location: selection.location - width, length: selection.length + 2 * width)
            return Edit(range: range, replacement: text.substring(with: selection), selection: NSRange(location: range.location, length: selection.length))
        }
        if selection.length >= 2 * width, wraps(min(run(from: selection.location, by: 1, within: selection), run(from: NSMaxRange(selection) - 1, by: -1, within: selection))) {
            let inner = NSRange(location: selection.location + width, length: selection.length - 2 * width)
            return Edit(range: selection, replacement: text.substring(with: inner), selection: NSRange(location: selection.location, length: inner.length))
        }
        return Edit(range: selection, replacement: delimiter + text.substring(with: selection) + delimiter, selection: NSRange(location: selection.location + width, length: selection.length))
    }

    public static func link(in text: String, selection: NSRange) -> Edit {
        let label = (text as NSString).substring(with: selection)
        let caret = selection.length == 0 ? selection.location + 1 : NSMaxRange(selection) + 3
        return Edit(range: selection, replacement: "[\(label)]()", selection: NSRange(location: caret, length: 0))
    }
}

public extension NSRange {
    func moved(across edit: NSRange, by delta: Int, growing: Bool = false) -> NSRange {
        let replacedEnd = NSMaxRange(edit) - delta
        func shift(_ position: Int, pastInsertion: Bool) -> Int {
            if position < edit.location || (position == edit.location && !pastInsertion) { return position }
            return position >= replacedEnd ? position + delta : NSMaxRange(edit)
        }
        let start = shift(location, pastInsertion: true)
        return NSRange(location: start, length: max(start, shift(NSMaxRange(self), pastInsertion: growing)) - start)
    }
}

private struct Fence {
    let mark: unichar
    let count: Int
    let bare: Bool

    init?(_ text: NSString, _ line: NSRange) {
        guard let start = text.blockStart(in: line), [0x60, 0x7E].contains(text.character(at: start)) else { return nil }
        mark = text.character(at: start)
        var end = start
        while end < NSMaxRange(line), text.character(at: end) == mark { end += 1 }
        count = end - start
        let info = text.substring(with: NSRange(location: end, length: NSMaxRange(line) - end))
        guard count >= 3, mark != 0x60 || !info.contains("`") else { return nil }
        bare = info.allSatisfy(\.isWhitespace)
    }

    func closes(_ open: Fence) -> Bool {
        mark == open.mark && count >= open.count && bare
    }
}

private extension NSString {
    func blockStart(in line: NSRange) -> Int? {
        var start = line.location
        while start < NSMaxRange(line), start - line.location < 3, character(at: start) == 0x20 { start += 1 }
        return start < NSMaxRange(line) ? start : nil
    }
}

private enum Pattern {
    static let heading = regex(#" {0,3}(#{1,6})(?:[ \t]+|$)"#)
    static let rule = regex(#" {0,3}([-*_])[ \t]*(?:\1[ \t]*){2,}$"#)
    static let quote = regex(#" {0,3}((?:>[ \t]?)+)"#)
    static let task = regex(#"([ \t]*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\])(?:[ \t]+|$)"#)
    static let list = regex(#"([ \t]*)([-*+]|\d{1,9}[.)])(?:[ \t]+|$)"#)
    static let code = regex(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    static let link = regex(#"(!?\[)([^\[\]\n]*)(\]\()([^)\s]*)((?:[ \t]+"[^"\n]*")?\))"#)
    static let definition = regex(#" {0,3}(\[([^\]\n]+)\]:)[ \t]*(\S+)(?:[ \t]+"[^"\n]*")?[ \t]*$"#)
    static let reference = regex(#"(\[)([^\[\]\n]+)(\]\[)([^\[\]\n]*)(\])"#)
    static let shortcut = regex(#"(?<![\]\\!])(\[)([^\[\]\n]+)(\])(?![(\[:])"#)
    static let address = regex(#"(?<![\w/])https?://[^\s<>()\[\]]*[^\s<>()\[\].,:;!?'"*_~]"#)
    static let delimited: [(NSRegularExpression, [Markdown.Line.Role], Int)] = [
        (regex(#"(?<![\\*])\*\*\*(?![\s*])(.+?)(?<![\s\\*])\*\*\*(?!\*)"#), [.strong, .emphasis], 3),
        (regex(#"(?<![\\*])\*\*(?![\s*])(.+?)(?<![\s\\])\*\*(?!\*)"#), [.strong], 2),
        (regex(#"(?<![\\\w])__(?![\s_])(.+?)(?<![\s\\])__(?!\w)"#), [.strong], 2),
        (regex(#"(?<![\\~])~~(?![\s~])(.+?)(?<![\s\\])~~(?!~)"#), [.strikethrough], 2),
        (regex(#"(?<![\\*])\*(?![\s*])(.+?)(?<![\s\\*])\*(?!\*)"#), [.emphasis], 1),
        (regex(#"(?<![\\\w])_(?![\s_])(.+?)(?<![\s\\_])_(?!\w)"#), [.emphasis], 1),
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }
}
