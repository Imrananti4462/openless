#!/usr/bin/env swift
import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

let sourceURL: URL
if CommandLine.arguments.count > 1 {
    sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    sourceURL = root.appendingPathComponent("Resources/Brand/openless-app-icon-source.jpg")
}

let outputDir = root.appendingPathComponent("Resources", isDirectory: true)
let previewURL = outputDir.appendingPathComponent("AppIcon.png")
let standardImageURL = outputDir.appendingPathComponent("Brand/openless-standard-image.png")
let iconsetURL = root.appendingPathComponent(".build/AppIcon.iconset", isDirectory: true)
let icnsURL = outputDir.appendingPathComponent("AppIcon.icns")

guard let source = NSImage(contentsOf: sourceURL),
      let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("[icon] failed to load \(sourceURL.path)\n", stderr)
    exit(1)
}

try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: standardImageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// Normalize any square-ish brand source into a centered symbol icon. The current
// source is already a cropped symbol, but the center crop keeps future exports safe.
let sourceWidth = CGFloat(cgImage.width)
let sourceHeight = CGFloat(cgImage.height)
let cropSide = min(sourceWidth, sourceHeight)
let cropRect = CGRect(
    x: (sourceWidth - cropSide) / 2,
    y: (sourceHeight - cropSide) / 2,
    width: cropSide,
    height: cropSide
)
guard let cropped = cgImage.cropping(to: cropRect) else {
    fputs("[icon] failed to crop source image\n", stderr)
    exit(1)
}

func renderedPNG(size: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "OpenLessIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "bitmap allocation failed"])
    }

    rep.size = NSSize(width: size, height: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "OpenLessIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "graphics context allocation failed"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let radius = CGFloat(size) * 0.22
    let mask = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    mask.addClip()

    NSColor(calibratedRed: 0.985, green: 0.985, blue: 0.98, alpha: 1).setFill()
    rect.fill()

    let image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    let inset = CGFloat(size) * 0.045
    let imageRect = rect.insetBy(dx: inset, dy: inset)
    image.draw(in: imageRect, from: NSRect(x: 0, y: 0, width: cropped.width, height: cropped.height), operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "OpenLessIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "png encoding failed"])
    }
    return data
}

let iconFiles: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let standardImage = try renderedPNG(size: 1024)
try standardImage.write(to: previewURL, options: .atomic)
try standardImage.write(to: standardImageURL, options: .atomic)
for file in iconFiles {
    let url = iconsetURL.appendingPathComponent(file.name)
    try renderedPNG(size: file.size).write(to: url, options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fputs("[icon] iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(process.terminationStatus)
}

print("[icon] wrote \(previewURL.path)")
print("[icon] wrote \(standardImageURL.path)")
print("[icon] wrote \(icnsURL.path)")
