import AppKit

final class ImageBar: NSView {
    private weak var owner: NoteTextView?

    init(owner: NoteTextView) {
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        let stack = NSStackView(views: [
            button("Fit width", #selector(fit)),
            button("Original size", #selector(original)),
            divider,
            button("Remove", #selector(remove), color: .systemRed),
        ])
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        frame.size = stack.fittingSize
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    private var divider: NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([line.widthAnchor.constraint(equalToConstant: 1), line.heightAnchor.constraint(equalToConstant: 14)])
        return line
    }

    private func button(_ title: String, _ action: Selector, color: NSColor = .labelColor) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.refusesFirstResponder = true
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: color])
        return button
    }

    @objc private func fit() {
        owner?.fitSelectedImage()
    }

    @objc private func original() {
        owner?.resizeSelectedImage(to: nil)
    }

    @objc private func remove() {
        _ = owner?.removeSelectedImage()
    }
}

final class SizeBadge: NSView {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.17, alpha: 1).cgColor
        label.font = .systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = .white
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func show(width: CGFloat) {
        label.stringValue = "\(Int(width.rounded())) pt"
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 7, y: 2)
        frame.size = NSSize(width: label.frame.width + 14, height: label.frame.height + 4)
        layer?.cornerRadius = frame.height / 2
    }
}

final class DropGuide: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 8))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.sublayers = nil
        let cobalt = Theme.cobalt.ns.cgColor
        let line = CALayer()
        line.backgroundColor = cobalt
        line.frame = CGRect(x: 0, y: 3, width: bounds.width, height: 2)
        line.cornerRadius = 1
        let dot = CALayer()
        dot.backgroundColor = cobalt
        dot.frame = CGRect(x: 0, y: 0, width: 8, height: 8)
        dot.cornerRadius = 4
        layer?.addSublayer(line)
        layer?.addSublayer(dot)
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }
}
