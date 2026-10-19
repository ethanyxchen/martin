import AppKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView.make()
        textView.delegate = context.coordinator
        textView.string = text
        textView.restyle()
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scroll.documentView as? NoteTextView, textView.string != text else { return }
        textView.string = text
        textView.restyle()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NoteTextView else { return }
            textView.restyle()
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? NoteTextView)?.revealCaretLine()
        }

        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
            (textView as? NoteTextView)?.snapped(from: old, to: new) ?? new
        }

        func textView(_ textView: NSTextView, shouldChangeTypingAttributes old: [String: Any], toAttributes new: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            new.filter { $0.key != .hiddenMarkup && $0.key != .link }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            (textView as? NoteTextView)?.handle(selector) ?? false
        }
    }
}

final class NoteTextView: NSTextView {
    private var revealed = NSRange(location: NSNotFound, length: 0)

    static func make() -> NoteTextView {
        let storage = NSTextStorage()
        let layout = NoteLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = NoteTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = .width
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: Theme.margin, height: 2)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.insertionPointColor = Theme.ink.ns
        view.linkTextAttributes = [
            .foregroundColor: Theme.ink.ns,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: Theme.tertiary.ns,
            .cursor: NSCursor.pointingHand,
        ]
        view.typingAttributes = Markdown.body
        return view
    }

    func restyle() {
        guard let textStorage, !hasMarkedText() else { return }
        revealed = (string as NSString).paragraphRange(for: selectedRange())
        Markdown.style(textStorage, revealing: revealed)
    }

    func revealCaretLine() {
        guard (string as NSString).paragraphRange(for: selectedRange()) != revealed else { return }
        restyle()
    }

    func snapped(from old: NSRange, to new: NSRange) -> NSRange {
        guard new.length == 0, let marker = lineMarker(at: new.location) else { return new }
        if old == NSRange(location: NSMaxRange(marker), length: 0), new.location < old.location, marker.location > 0 {
            return NSRange(location: marker.location - 1, length: 0)
        }
        return NSRange(location: NSMaxRange(marker), length: 0)
    }

    func handle(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(insertNewline(_:)): continueList()
        case #selector(deleteBackward(_:)): removeMarker()
        default: false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let box = checkbox(at: convert(event.locationInWindow, from: nil)) else { return super.mouseDown(with: event) }
        let mark = (string as NSString).substring(with: box)
        replace(box, with: mark == " " ? "x" : " ")
    }

    private func lineMarker(at location: Int) -> NSRange? {
        guard let textStorage, location < textStorage.length else { return nil }
        var marker = NSRange()
        let start = (string as NSString).paragraphRange(for: NSRange(location: location, length: 0)).location
        guard textStorage.attribute(.hiddenMarkup, at: location, longestEffectiveRange: &marker, in: NSRange(location: start, length: textStorage.length - start)) != nil,
              marker.location == start else { return nil }
        return marker
    }

    private func caretLine() -> (line: NSRange, block: Block, prefix: Int)? {
        let caret = selectedRange()
        guard caret.length == 0 else { return nil }
        let text = string as NSString
        var start = 0, end = 0, contentsEnd = 0
        text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: caret)
        let line = NSRange(location: start, length: contentsEnd - start)
        let (block, prefix) = Markdown.parse(text.substring(with: line))
        return (line, block, prefix)
    }

    private func continueList() -> Bool {
        guard let (line, block, prefix) = caretLine() else { return false }
        switch block {
        case .task, .bullet:
            let marker = NSRange(location: line.location, length: prefix)
            guard line.length > prefix else { return replace(marker, with: "") }
            let next = (string as NSString).substring(with: marker).replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
            return replace(selectedRange(), with: "\n" + next)
        default:
            return false
        }
    }

    private func removeMarker() -> Bool {
        guard let (line, block, prefix) = caretLine(), block != .text, prefix > 0, selectedRange().location == line.location + prefix else { return false }
        return replace(NSRange(location: line.location, length: prefix), with: "")
    }

    private func checkbox(at point: NSPoint) -> NSRange? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard (0..<Theme.gutter).contains(local.x) else { return nil }
        let character = layoutManager.characterIndexForGlyph(at: layoutManager.glyphIndex(for: local, in: textContainer))
        let line = (string as NSString).paragraphRange(for: NSRange(location: min(character, textStorage.length - 1), length: 0))
        guard case .task = textStorage.attribute(.block, at: line.location, effectiveRange: nil) as? Block else { return nil }
        let bracket = (string as NSString).range(of: "[", range: line)
        return NSRange(location: bracket.location + 1, length: 1)
    }

    @discardableResult
    private func replace(_ range: NSRange, with replacement: String) -> Bool {
        guard shouldChangeText(in: range, replacementString: replacement) else { return true }
        textStorage?.replaceCharacters(in: range, with: replacement)
        setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
        didChangeText()
        return true
    }
}

private final class NoteLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange range: NSRange
    ) -> Int {
        guard let textStorage else { return 0 }
        let hidden = (0..<range.length).map { textStorage.attribute(.hiddenMarkup, at: characterIndexes[$0], effectiveRange: nil) != nil }
        guard hidden.contains(true) else { return 0 }
        let adjusted = (0..<range.length).map { hidden[$0] ? .null : properties[$0] }
        adjusted.withUnsafeBufferPointer { setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: range) }
        return range.length
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(.block, in: characters) { value, range, _ in
            guard let block = value as? Block else { return }
            let first = glyphIndexForCharacter(at: range.location)
            let fragment = lineFragmentRect(forGlyphAt: first, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
            let baseline = fragment.minY + location(forGlyphAt: first).y
            let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 14)
            switch block {
            case .task(let checked):
                Self.drawCheckbox(checked: checked, centeredAt: NSPoint(x: fragment.minX + 9, y: baseline - font.capHeight / 2))
            case .bullet:
                Theme.tertiary.ns.setFill()
                NSBezierPath(ovalIn: NSRect(x: fragment.minX + 7, y: baseline - font.xHeight / 2 - 2, width: 4, height: 4)).fill()
            case .quote:
                let bounds = boundingRect(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
                Theme.hairline.ns.setFill()
                NSBezierPath(roundedRect: NSRect(x: origin.x + Theme.gutter, y: origin.y + bounds.minY + 4, width: 2, height: bounds.height - 6), xRadius: 1, yRadius: 1).fill()
            default:
                return
            }
        }
    }

    private static func drawCheckbox(checked: Bool, centeredAt center: NSPoint) {
        let box = NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
        guard checked else {
            Theme.tertiary.ns.setStroke()
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.6, dy: 0.6), xRadius: 4, yRadius: 4)
            outline.lineWidth = 1.2
            outline.stroke()
            return
        }
        Theme.ember.ns.setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: box.minX + 3.6, y: box.midY + 0.2))
        tick.line(to: NSPoint(x: box.minX + 6, y: box.midY + 2.6))
        tick.line(to: NSPoint(x: box.maxX - 3.4, y: box.midY - 2.4))
        tick.lineWidth = 1.7
        tick.lineCapStyle = .round
        tick.lineJoinStyle = .round
        NSColor.white.setStroke()
        tick.stroke()
    }
}

enum Block: Hashable {
    case blank, heading, task(checked: Bool), bullet, detail, quote, text
}

extension NSAttributedString.Key {
    static let hiddenMarkup = NSAttributedString.Key("martin.hiddenMarkup")
    static let block = NSAttributedString.Key("martin.block")
}

@MainActor
enum Markdown {
    static let body: [NSAttributedString.Key: Any] = [
        .font: Theme.body,
        .foregroundColor: Theme.ink.ns,
        .paragraphStyle: paragraph(.text, after: nil),
    ]

    private static let link = try! NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private static let timestamp = try! NSRegularExpression(pattern: #"\s·\s\d{1,2}(:\d{2}){1,2}\s*$"#)

    static func parse(_ line: String) -> (Block, Int) {
        if line.allSatisfy(\.isWhitespace) { return (.blank, 0) }
        if let match = line.prefixMatch(of: #/#{1,6} +/#) { return (.heading, match.0.utf16.count) }
        if let match = line.prefixMatch(of: #/\s*- \[([ xX])\] /#) { return (.task(checked: match.1 != " "), match.0.utf16.count) }
        if let match = line.prefixMatch(of: #/\s*[-*] /#) { return (.bullet, match.0.utf16.count) }
        if let match = line.prefixMatch(of: #/\s*> ?/#) { return (.quote, match.0.utf16.count) }
        if let match = line.prefixMatch(of: #/\s+/#) { return (.detail, match.0.utf16.count) }
        return (.text, 0)
    }

    static func style(_ storage: NSTextStorage, revealing reveal: NSRange) {
        let text = storage.string as NSString
        storage.beginEditing()
        storage.setAttributes(body, range: NSRange(location: 0, length: text.length))
        var previous: Block?
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { line, range, enclosing, _ in
            let (block, prefix) = parse(line ?? "")
            let content = NSRange(location: range.location + prefix, length: range.length - prefix)
            storage.addAttributes(attributes(block, after: previous), range: enclosing)
            storage.addAttribute(.block, value: block, range: enclosing)
            if prefix > 0 {
                storage.addAttribute(.hiddenMarkup, value: true, range: NSRange(location: range.location, length: prefix))
            }
            if block == .quote, let stamp = timestamp.firstMatch(in: storage.string, range: content) {
                storage.addAttributes([.font: Theme.timestamp, .foregroundColor: Theme.tertiary.ns], range: stamp.range)
            }
            styleLinks(in: content, of: storage, revealed: NSIntersectionRange(enclosing, reveal).length > 0 || NSLocationInRange(reveal.location, enclosing))
            previous = block
        }
        storage.endEditing()
    }

    private static func styleLinks(in range: NSRange, of storage: NSTextStorage, revealed: Bool) {
        for match in link.matches(in: storage.string, range: range) {
            let label = match.range(at: 1)
            let syntax = [
                NSRange(location: match.range.location, length: 1),
                NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)),
            ]
            if let url = URL(string: (storage.string as NSString).substring(with: match.range(at: 2))) {
                storage.addAttribute(.link, value: url, range: label)
            }
            for part in syntax {
                storage.addAttributes(revealed ? [.foregroundColor: Theme.tertiary.ns] : [.hiddenMarkup: true], range: part)
            }
        }
    }

    private static func attributes(_ block: Block, after previous: Block?) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraph(block, after: previous)]
        switch block {
        case .heading:
            attributes[.font] = Theme.heading
            attributes[.foregroundColor] = Theme.secondary.ns
            attributes[.kern] = 0.8
        case .task(checked: true):
            attributes[.foregroundColor] = Theme.tertiary.ns
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = Theme.tertiary.ns
        case .detail:
            attributes[.font] = NSFont.systemFont(ofSize: 13)
            attributes[.foregroundColor] = Theme.secondary.ns
        case .quote:
            attributes[.font] = Theme.quote
            attributes[.foregroundColor] = Theme.secondary.ns
        default:
            break
        }
        let font = attributes[.font] as? NSFont ?? Theme.body
        attributes[.baselineOffset] = (lineHeight(block) - (font.ascender - font.descender)) / 2
        return attributes
    }

    private static func paragraph(_ block: Block, after previous: Block?) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = block == .quote ? Theme.gutter + 12 : Theme.gutter
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.minimumLineHeight = lineHeight(block)
        style.maximumLineHeight = lineHeight(block)
        style.paragraphSpacingBefore = spacing(block, after: previous)
        return style
    }

    private static func lineHeight(_ block: Block) -> CGFloat {
        switch block {
        case .blank: 10
        case .heading: 18
        case .detail, .quote: 20
        default: 22
        }
    }

    private static func spacing(_ block: Block, after previous: Block?) -> CGFloat {
        switch (block, previous) {
        case (.heading, nil): 0
        case (.heading, _): 18
        case (.task, .heading), (.bullet, .heading), (.task, nil), (.bullet, nil): 6
        case (.task, _), (.bullet, _): 12
        case (.quote, _): 4
        case (.detail, _): 1
        default: 0
        }
    }
}
