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
    static let paper = Tone(light: 0xFBFBF4, dark: 0x1C1B19)
    static let well = Tone(light: 0xF3F2EA, dark: 0x242320)
    static let ink = Tone(light: 0x1F1E1B, dark: 0xECEAE3)
    static let secondary = Tone(light: 0x6E6A61, dark: 0xA19C91)
    static let tertiary = Tone(light: 0xA8A49A, dark: 0x6C685F)
    static let hairline = Tone(light: 0xE5E2D7, dark: 0x33312D)
    static let ember = Tone(light: 0xEE5F22, dark: 0xFF7A3D)
    static let moss = Tone(light: 0x4F7D4A, dark: 0x7DB576)

    static let gutter: CGFloat = 26
    static let margin: CGFloat = 28
    static let column = margin + gutter

    static let title = Font.system(size: 22, weight: .semibold, design: .serif)
    static let meta = Font.system(size: 12)
    static let label = Font.system(size: 13, weight: .semibold).lowercaseSmallCaps().uppercaseSmallCaps()

    @MainActor static let body = NSFont.systemFont(ofSize: 14)
    @MainActor static let heading = NSFont(descriptor: NSFont.systemFont(ofSize: 13, weight: .semibold).fontDescriptor.addingAttributes([
        .featureSettings: [
            [NSFontDescriptor.FeatureKey.typeIdentifier: kUpperCaseType, .selectorIdentifier: kUpperCaseSmallCapsSelector],
            [NSFontDescriptor.FeatureKey.typeIdentifier: kLowerCaseType, .selectorIdentifier: kLowerCaseSmallCapsSelector],
        ],
    ]), size: 13)!
    @MainActor static let quote = NSFont(descriptor: NSFont.systemFont(ofSize: 13.5).fontDescriptor.withDesign(.serif)!.withSymbolicTraits(.italic), size: 13.5)!
    @MainActor static let timestamp = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.label)
            .kerning(0.8)
            .foregroundStyle(Theme.secondary)
    }
}
