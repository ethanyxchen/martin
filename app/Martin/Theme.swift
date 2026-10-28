import AppKit
import SwiftUI

struct Tone: ShapeStyle {
    let light: UInt32
    let dark: UInt32

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let hex = environment.colorScheme == .dark ? dark : light
        return Color.Resolved(red: Self.channel(hex, 16), green: Self.channel(hex, 8), blue: Self.channel(hex, 0))
    }

    var ns: NSColor {
        NSColor(name: nil) { [light, dark] appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(Self.channel(hex, 16)), green: CGFloat(Self.channel(hex, 8)), blue: CGFloat(Self.channel(hex, 0)), alpha: 1)
        }
    }

    private static func channel(_ hex: UInt32, _ shift: UInt32) -> Float {
        Float((hex >> shift) & 0xFF) / 255
    }
}

enum Theme {
    static let paper = Tone(light: 0xF7F8FA, dark: 0x1C1B19)
    static let well = Tone(light: 0xEBEDF1, dark: 0x242320)
    static let ink = Tone(light: 0x1C1E22, dark: 0xECEAE3)
    static let secondary = Tone(light: 0x6A6E76, dark: 0xA19C91)
    static let tertiary = Tone(light: 0xA3A7AF, dark: 0x6C685F)
    static let cobalt = Tone(light: 0x0055E0, dark: 0x5B8CFF)

    static let controls: CGFloat = 78
    static let gutter: CGFloat = 26
    static let margin: CGFloat = 28
    static let column = margin + gutter
    static let measure: CGFloat = 560
    static let page = column + measure + margin

    static let title = Font.system(size: 22, weight: .semibold, design: .serif)
    static let heading = Font.system(size: 15, weight: .semibold, design: .serif)
    static let meta = Font.system(size: 12)
}

extension View {
    func movesWindow() -> some View {
        contentShape(.rect).gesture(WindowDragGesture())
    }

    func flush() -> some View {
        padding(.leading, Theme.column)
            .padding(.trailing, Theme.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func column() -> some View {
        padding(.leading, Theme.column)
            .padding(.trailing, Theme.margin)
            .frame(maxWidth: Theme.page, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}
