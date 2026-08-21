// Draws the application icon into an .iconset folder.
//
//     swift Scripts/make-icon.swift <output.iconset>
//
// Only CoreGraphics and ImageIO are used, so the script draws the same picture
// whether it runs on a developer's Mac or on a CI runner with no window server.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

let skyBlue = color(0.35, 0.78, 0.98)
let deepBlue = color(0.05, 0.35, 0.70)
let white = color(1, 1, 1, 0.97)

/// Draws the icon into a square bitmap and returns it.
func render(pixels: Int) -> CGImage {
    let scale = CGFloat(pixels) / canvas
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("cannot create a \(pixels)×\(pixels) bitmap")
    }
    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)

    // The rounded square every macOS icon sits in, filled with a gradient.
    let plate = CGPath(
        roundedRect: CGRect(x: 80, y: 80, width: canvas - 160, height: canvas - 160),
        cornerWidth: 200,
        cornerHeight: 200,
        transform: nil
    )
    context.saveGState()
    context.addPath(plate)
    context.clip()
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [skyBlue, deepBlue] as CFArray,
        locations: [0, 1]
    ) else {
        fail("cannot create the background gradient")
    }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: canvas),
        end: CGPoint(x: canvas, y: 0),
        options: []
    )
    context.restoreGState()

    // A remote control: a rounded body, a power button and two columns of keys.
    let body = CGRect(x: 392, y: 216, width: 240, height: 592)
    context.setFillColor(white)
    context.addPath(CGPath(roundedRect: body, cornerWidth: 84, cornerHeight: 84, transform: nil))
    context.fillPath()

    context.setStrokeColor(deepBlue)
    context.setLineWidth(26)
    let power = CGRect(x: 512 - 52, y: 648 - 52, width: 104, height: 104)
    context.strokeEllipse(in: power)

    context.setFillColor(deepBlue)
    for row in 0..<3 {
        for column in 0..<2 {
            let dot = CGRect(
                x: 512 - 74 + CGFloat(column) * 96 - 24,
                y: 470 - CGFloat(row) * 104 - 24,
                width: 48,
                height: 48
            )
            context.fillEllipse(in: dot)
        }
    }

    guard let image = context.makeImage() else {
        fail("cannot read back the \(pixels)×\(pixels) bitmap")
    }
    return image
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fail("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("cannot finish writing \(url.path)")
    }
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: make-icon.swift <output.iconset>")
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
} catch {
    fail("cannot create \(directory.path): \(error.localizedDescription)")
}

// The sizes `iconutil` expects in an iconset.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(points)x\(points)\(suffix).png"
        write(render(pixels: points * scale), to: directory.appendingPathComponent(name))
    }
}
