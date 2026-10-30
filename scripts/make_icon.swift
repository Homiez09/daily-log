#!/usr/bin/env swift
// Regenerates Resources/AppIcon.icns from Resources/AppIcon.icon (the Icon Composer document).
//
//   swift scripts/make_icon.swift
//
// Why this exists: `actool` (the normal .icon compiler) needs Xcode's first-launch setup, so instead
// we render the Liquid Glass document with Icon Composer's own `ictool`, give it the standard macOS
// icon padding + shadow, and package it with `iconutil`. The .icns is committed, so building the app
// never needs this script or Xcode's icon tools.

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let document = root.appendingPathComponent("Resources/AppIcon.icon")
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

guard FileManager.default.isExecutableFile(atPath: ictool) else {
    FileHandle.standardError.write(Data("ictool not found at \(ictool). Install Xcode 26+ (it bundles Icon Composer).\n".utf8))
    exit(1)
}

let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("dailylog-icon-\(UUID().uuidString)")
let iconset = workDirectory.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: workDirectory) }

/// Apple's macOS icon grid: the squircle is 824 pt wide inside a 1024 pt canvas.
let contentRatio: CGFloat = 824.0 / 1024.0

func renderSquircle(pixels: Int) throws -> NSImage {
    let file = workDirectory.appendingPathComponent("render-\(pixels).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ictool)
    process.arguments = [document.path, "--export-image", "--output-file", file.path, "--platform", "macOS",
                         "--rendition", "Default", "--width", "\(pixels)", "--height", "\(pixels)", "--scale", "1"]
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0, let image = NSImage(contentsOf: file) else {
        throw NSError(domain: "make_icon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ictool failed for \(pixels)px"])
    }
    return image
}

func compose(canvas: Int) throws -> Data {
    let content = max(Int((CGFloat(canvas) * contentRatio).rounded()), 1)
    let squircle = try renderSquircle(pixels: content)

    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "make_icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "bitmap"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = CGFloat(canvas) * 0.014
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(canvas) * 0.010)
    shadow.set()

    let inset = CGFloat(canvas - content) / 2
    squircle.draw(in: NSRect(x: inset, y: inset, width: CGFloat(content), height: CGFloat(content)),
                  from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make_icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "png"])
    }
    return png
}

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for entry in entries {
    let data = try compose(canvas: entry.pixels)
    try data.write(to: iconset.appendingPathComponent("\(entry.name).png"))
    print("rendered \(entry.name).png (\(entry.pixels)px)")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
print("wrote \(output.path)")
