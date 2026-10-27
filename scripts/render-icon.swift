import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3, let hex = UInt32(arguments[1], radix: 16) else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <tile hex> <iconset directory>\n".utf8))
    exit(1)
}
let iconset = URL(fileURLWithPath: arguments[2])

func color(_ hex: UInt32, lightened amount: CGFloat = 0) -> CGColor {
    let channels = [hex >> 16, hex >> 8, hex].map { CGFloat($0 & 0xFF) / 255 }
    let mixed = channels.map { $0 + (1 - $0) * amount }
    return CGColor(srgbRed: mixed[0], green: mixed[1], blue: mixed[2], alpha: 1)
}

func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / 1024
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(tile, radius: 185.4)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(color(hex))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [color(hex, lightened: 0.16), color(hex)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: tile.minY), end: CGPoint(x: 512, y: tile.maxY), options: [])
    context.restoreGState()

    let windows: [(lightened: CGFloat, degrees: CGFloat)] = [(0.3, -12), (0.58, -5), (1, 3)]
    for (index, window) in windows.enumerated() {
        let frame = CGRect(x: 176 + 96 * CGFloat(index), y: 221 + 96 * CGFloat(index), width: 480, height: 390)
        let focused = index == windows.count - 1
        context.saveGState()
        context.translateBy(x: frame.midX, y: frame.midY)
        context.rotate(by: window.degrees * .pi / 180)
        context.translateBy(x: -frame.midX, y: -frame.midY)
        if focused {
            context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 32 * scale, color: CGColor(srgbRed: 0, green: 0.1, blue: 0.33, alpha: 0.28))
        }
        context.addPath(squircle(frame, radius: 60))
        context.setFillColor(color(hex, lightened: window.lightened))
        context.fillPath()
        if focused {
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.setFillColor(color(hex, lightened: 0.7))
            for dot in 0..<3 {
                context.fillEllipse(in: CGRect(x: frame.minX + 41 + 44 * CGFloat(dot), y: frame.minY + 37, width: 30, height: 30))
            }
        }
        context.restoreGState()
    }
    return context.makeImage()!
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
var rendered: [Int: CGImage] = [:]
for points in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let pixels = points * density
        let image = rendered[pixels] ?? render(pixels: pixels)
        rendered[pixels] = image
        let file = iconset.appendingPathComponent("icon_\(points)x\(points)\(density == 1 ? "" : "@2x").png")
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Cannot create \(file.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(file.path)") }
    }
}
