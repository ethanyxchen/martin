import AppKit
import MartinKit

@MainActor
final class MarkdownStyle: NSObject {
    nonisolated static let hang: CGFloat = 40
    nonisolated static let tail = Theme.column - hang - Theme.margin

    static let typing: [NSAttributedString.Key: Any] = {
        let look = Look(.text)
        return [.font: look.font, .foregroundColor: look.color, .paragraphStyle: paragraph(look, indent: 0, marker: 0), .baselineOffset: look.baselineOffset]
    }()

    private static let body = NSFont.systemFont(ofSize: 15)
    private static let ink = Theme.ink.ns
    private static let secondary = Theme.secondary.ns
    private static let tertiary = Theme.tertiary.ns
    private static let ember = Theme.ember.ns
    private static let moss = Theme.moss.ns

    private var codeBlocks: [NSRange] = []

    func line(at location: Int, in text: NSString) -> (range: NSRange, line: Markdown.Line) {
        var start = 0, contentsEnd = 0
        text.getParagraphStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        let range = NSRange(location: start, length: contentsEnd - start)
        let contents = text.substring(with: range)
        let line = Markdown.Line(contents)
        guard let block = codeBlocks.first(where: { NSLocationInRange(start, $0) }), start != block.location else { return (range, line) }
        let closing = line.block == .fence && NSMaxRange(text.paragraphRange(for: range)) == NSMaxRange(block)
        return (range, closing ? line : Markdown.Line(contents, code: true))
    }

    private func edge(of line: Markdown.Line, at location: Int) -> CodeEdge? {
        switch line.block {
        case .code: .middle
        case .fence: codeBlocks.contains { $0.location == location } ? .top : .bottom
        default: nil
        }
    }

    private func style(_ text: NSMutableAttributedString, as line: Markdown.Line, length: Int, edge: CodeEdge?) {
        let look = Look(line.block)
        let all = NSRange(location: 0, length: text.length)
        text.addAttributes([.font: look.font, .foregroundColor: look.color, .baselineOffset: look.baselineOffset], range: all)
        if case .task(done: true) = line.block {
            text.addAttributes([.foregroundColor: Self.tertiary, .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: Self.tertiary], range: NSRange(location: line.prefix, length: length - line.prefix))
        }
        if let edge { text.addAttribute(.codeBlock, value: edge, range: all) }
        for span in line.spans {
            switch span.role {
            case .marker:
                text.addAttribute(.foregroundColor, value: Self.tertiary, range: span.range)
                text.removeAttribute(.strikethroughStyle, range: span.range)
            case .checkbox:
                text.addAttribute(.foregroundColor, value: line.block == .task(done: true) ? Self.ember : Self.secondary, range: span.range)
                text.removeAttribute(.strikethroughStyle, range: span.range)
            case .strong:
                Self.add(.bold, to: text, in: span.range)
            case .emphasis:
                Self.add(.italic, to: text, in: span.range)
            case .strikethrough:
                text.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: Self.secondary], range: span.range)
            case .code:
                text.addAttributes([.font: Self.mono(look.font.pointSize * 0.9), .foregroundColor: Self.moss], range: span.range)
            case .link:
                text.addAttribute(.foregroundColor, value: Self.ember, range: span.range)
            case .url:
                text.addAttribute(.foregroundColor, value: Self.tertiary, range: span.range)
            }
        }
        let indent = text.attributedSubstring(from: NSRange(location: 0, length: line.indent)).size().width
        let marker = text.attributedSubstring(from: NSRange(location: line.indent, length: line.prefix - line.indent)).size().width
        text.addAttribute(.paragraphStyle, value: Self.paragraph(look, indent: indent, marker: marker), range: all)
    }

    private static func paragraph(_ look: Look, indent: CGFloat, marker: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = max(0, hang - marker)
        style.headIndent = hang + indent
        style.tailIndent = tail
        style.minimumLineHeight = look.lineHeight
        style.maximumLineHeight = look.lineHeight
        style.paragraphSpacingBefore = look.spacing
        return style
    }

    private static func add(_ trait: NSFontDescriptor.SymbolicTraits, to text: NSMutableAttributedString, in range: NSRange) {
        text.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
            text.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: run)
        }
    }

    private static func mono(_ size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func heading(_ size: CGFloat) -> NSFont {
        NSFont(descriptor: NSFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor.withDesign(.serif)!, size: size)!
    }

    @MainActor
    private struct Look {
        let font: NSFont
        let color: NSColor
        let lineHeight: CGFloat
        let spacing: CGFloat

        var baselineOffset: CGFloat {
            (lineHeight - font.ascender + font.descender) / 2
        }

        init(_ block: Markdown.Line.Block) {
            switch block {
            case .heading(1): self.init(font: heading(23), lineHeight: 32, spacing: 10)
            case .heading(2): self.init(font: heading(19), lineHeight: 28, spacing: 8)
            case .heading(3): self.init(font: heading(16.5), lineHeight: 25, spacing: 6)
            case .heading(let level): self.init(font: heading(15), color: level > 4 ? secondary : ink, lineHeight: 24, spacing: 4)
            case .quote: self.init(font: NSFont(descriptor: body.fontDescriptor.withDesign(.serif)!.withSymbolicTraits(.italic), size: 15)!, color: secondary)
            case .fence: self.init(font: mono(13), color: tertiary, lineHeight: 22)
            case .code: self.init(font: mono(13), lineHeight: 21)
            case .blank: self.init(font: body, lineHeight: 12)
            case .rule: self.init(font: body, color: tertiary)
            case .text, .list, .task: self.init(font: body)
            }
        }

        private init(font: NSFont, color: NSColor = MarkdownStyle.ink, lineHeight: CGFloat = 24, spacing: CGFloat = 0) {
            self.font = font
            self.color = color
            self.lineHeight = lineHeight
            self.spacing = spacing
        }
    }
}

extension MarkdownStyle: @preconcurrency NSTextContentStorageDelegate {
    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let source = textContentStorage.textStorage else { return nil }
        let text = NSMutableAttributedString(attributedString: source.attributedSubstring(from: range))
        let (contents, line) = line(at: range.location, in: source.string as NSString)
        style(text, as: line, length: contents.length, edge: edge(of: line, at: range.location))
        return NSTextParagraph(attributedString: text)
    }
}

extension MarkdownStyle: @preconcurrency NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let end = NSMaxRange(range) - delta
        let before = codeBlocks.map { block in
            if NSMaxRange(block) < range.location { return block }
            if block.location >= end { return NSRange(location: block.location + delta, length: block.length) }
            return NSRange(location: block.location, length: block.length + delta)
        }
        codeBlocks = Markdown.codeBlocks(in: textStorage.string)
        let changed = Set(before).symmetricDifference(codeBlocks)
        guard let first = changed.first else { return }
        let stale = NSIntersectionRange(changed.reduce(first, NSUnionRange), NSRange(location: 0, length: textStorage.length))
        textStorage.edited(.editedAttributes, range: stale, changeInLength: 0)
    }
}

extension MarkdownStyle: @preconcurrency NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
              let edge = paragraph.attributedString.attribute(.codeBlock, at: 0, effectiveRange: nil) as? CodeEdge else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        return CodeFragment(textElement: textElement, range: textElement.elementRange, edge: edge)
    }
}

private enum CodeEdge {
    case top, middle, bottom
}

private extension NSAttributedString.Key {
    static let codeBlock = NSAttributedString.Key("martin.codeBlock")
}

private final class CodeFragment: NSTextLayoutFragment {
    private static let radius: CGFloat = 6
    private static let padding: CGFloat = 12
    private let edge: CodeEdge

    init(textElement: NSTextElement, range: NSTextRange?, edge: CodeEdge) {
        self.edge = edge
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(panel)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let panel = panel.offsetBy(dx: point.x, dy: point.y)
        let rounded = CGRect(
            x: panel.minX,
            y: edge == .top ? panel.minY : panel.minY - Self.radius,
            width: panel.width,
            height: panel.height + (edge == .middle ? 2 : 1) * Self.radius
        )
        context.saveGState()
        context.clip(to: panel)
        context.addPath(CGPath(roundedRect: rounded, cornerWidth: Self.radius, cornerHeight: Self.radius, transform: nil))
        context.setFillColor(Theme.ink.ns.cgColor.copy(alpha: 0.037)!)
        context.fillPath()
        context.restoreGState()
        super.draw(at: point, in: context)
    }

    private var panel: CGRect {
        let width = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let minX = MarkdownStyle.hang - Self.padding, maxX = width + MarkdownStyle.tail + Self.padding
        return CGRect(x: minX - layoutFragmentFrame.minX, y: 0, width: maxX - minX, height: layoutFragmentFrame.height)
    }
}
