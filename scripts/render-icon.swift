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

func render(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / 1024
    context.saveGState()
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: tile).cgPath
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(color(hex))
    context.fillPath()
    context.restoreGState()

    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [color(hex, lightened: 0.16), color(hex)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
    context.restoreGState()

    let lengths: [CGFloat] = [400, 300, 360]
    let thickness = max(1, (64 * scale).rounded())
    let pitch = max(thickness + 1, (150 * scale).rounded())
    let gap = max(1, (56 * scale).rounded())
    let radius = thickness > 1 ? thickness / 2 : 0
    let centre = CGFloat(pixels) / 2
    let left = (centre - (thickness + gap + (lengths.max()! * scale).rounded()) / 2).rounded()
    let top = (centre + (pitch * CGFloat(lengths.count - 1) + thickness) / 2).rounded()
    context.setFillColor(.white)
    for (index, length) in lengths.enumerated() {
        let y = top - thickness - CGFloat(index) * pitch
        let bullet = CGRect(x: left, y: y, width: thickness, height: thickness)
        let line = CGRect(x: left + thickness + gap, y: y, width: max(1, (length * scale).rounded()), height: thickness)
        for rect in [bullet, line] {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        }
    }
    context.fillPath()
    return context.makeImage()!
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let name = "icon_\(points)x\(points)\(density == 1 ? "" : "@2x").png"
        let destination = CGImageDestinationCreateWithURL(iconset.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, render(pixels: points * density), nil)
        guard CGImageDestinationFinalize(destination) else { exit(1) }
    }
}
