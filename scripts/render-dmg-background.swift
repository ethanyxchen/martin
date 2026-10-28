import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-dmg-background.swift <background.tiff>\n".utf8))
    exit(1)
}

let arrow = Color(red: 0.77, green: 0.75, blue: 0.71)

struct Background: View {
    var body: some View {
        ZStack {
            Color.white
            Path { path in
                path.move(to: CGPoint(x: 261, y: 166))
                path.addCurve(to: CGPoint(x: 393, y: 162), control1: CGPoint(x: 300, y: 146), control2: CGPoint(x: 355, y: 146))
            }
            .stroke(arrow, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [1, 7]))
            Path { path in
                path.move(to: CGPoint(x: 383, y: 153))
                path.addLine(to: CGPoint(x: 394, y: 162))
                path.addLine(to: CGPoint(x: 381, y: 166))
            }
            .stroke(arrow, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            Text("Drag Martin into Applications")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.55))
                .position(x: 330, y: 350)
        }
        .frame(width: 660, height: 400)
    }
}

let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: arguments[1]) as CFURL, UTType.tiff.identifier as CFString, 2, nil
)!
MainActor.assumeIsolated {
    for scale in [1, 2] {
        let renderer = ImageRenderer(content: Background())
        renderer.scale = CGFloat(scale)
        let dpi = 72 * scale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, renderer.cgImage!, properties)
    }
}
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(arguments[1])") }
