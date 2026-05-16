#!/usr/bin/env swift
// Generates AppIcon.iconset/* PNGs from pure CoreGraphics — no design assets,
// fully reproducible. Run via `tools/make_icons.sh`.

import Cocoa
import CoreGraphics
import UniformTypeIdentifiers

func render(size: CGFloat) -> CGImage? {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // ---- Squircle background with diagonal gradient -------------------------
    let cornerR = size * 0.2237 // standard macOS icon corner radius
    let bgPath = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: cornerR, cornerHeight: cornerR, transform: nil
    )

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let bgColors = [
        CGColor(srgbRed: 0.42, green: 0.36, blue: 1.00, alpha: 1.0), // #6B5BFF
        CGColor(srgbRed: 0.12, green: 0.66, blue: 1.00, alpha: 1.0)  // #1FA8FF
    ] as CFArray
    let bgGradient = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 1])!
    ctx.drawLinearGradient(bgGradient,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])

    // Subtle inner highlight along top-left
    let highlightColors = [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray
    let highlightGradient = CGGradient(colorsSpace: cs, colors: highlightColors, locations: [0, 1])!
    ctx.drawRadialGradient(highlightGradient,
                           startCenter: CGPoint(x: size * 0.25, y: size * 0.9),
                           startRadius: 0,
                           endCenter: CGPoint(x: size * 0.25, y: size * 0.9),
                           endRadius: size * 0.7,
                           options: [])
    ctx.restoreGState()

    // ---- Three layered "windows" -------------------------------------------
    let winW = size * 0.58
    let winH = size * 0.40
    let winR = size * 0.045
    let cx = size / 2
    let cy = size / 2

    func drawWindow(offset: CGPoint, alpha: CGFloat, withChrome: Bool, withShadow: Bool) {
        let rect = CGRect(
            x: cx - winW / 2 + offset.x,
            y: cy - winH / 2 + offset.y,
            width: winW, height: winH
        )
        let path = CGPath(roundedRect: rect, cornerWidth: winR, cornerHeight: winR, transform: nil)

        if withShadow {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -size * 0.012),
                blur: size * 0.04,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35)
            )
        }

        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
        ctx.addPath(path)
        ctx.fillPath()

        if withShadow {
            ctx.restoreGState()
        }

        if withChrome {
            let dotR = size * 0.014
            let dotSpacing = size * 0.042
            let firstX = rect.minX + size * 0.045
            let dotY = rect.maxY - size * 0.045
            let colors: [CGColor] = [
                CGColor(srgbRed: 1.00, green: 0.36, blue: 0.36, alpha: 1),
                CGColor(srgbRed: 1.00, green: 0.74, blue: 0.21, alpha: 1),
                CGColor(srgbRed: 0.18, green: 0.78, blue: 0.36, alpha: 1)
            ]
            for (i, color) in colors.enumerated() {
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(
                    x: firstX + CGFloat(i) * dotSpacing - dotR,
                    y: dotY - dotR,
                    width: dotR * 2, height: dotR * 2
                ))
            }

            // Content line — a small accent that hints at a selected row
            let bar = CGRect(
                x: rect.minX + size * 0.06,
                y: rect.minY + size * 0.08,
                width: rect.width - size * 0.12,
                height: size * 0.035
            )
            let barPath = CGPath(roundedRect: bar, cornerWidth: bar.height/2, cornerHeight: bar.height/2, transform: nil)
            ctx.setFillColor(CGColor(srgbRed: 0.42, green: 0.36, blue: 1.0, alpha: 0.9))
            ctx.addPath(barPath)
            ctx.fillPath()
        }
    }

    // Back-most → front-most, with diagonal stagger
    drawWindow(offset: CGPoint(x:  size * 0.10, y: -size * 0.10), alpha: 0.30, withChrome: false, withShadow: true)
    drawWindow(offset: CGPoint(x:  size * 0.00, y:  size * 0.00), alpha: 0.55, withChrome: false, withShadow: true)
    drawWindow(offset: CGPoint(x: -size * 0.10, y:  size * 0.10), alpha: 1.00, withChrome: true,  withShadow: true)

    return ctx.makeImage()
}

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (name, px) in sizes {
    guard let img = render(size: CGFloat(px)) else {
        FileHandle.standardError.write("failed: \(name)\n".data(using: .utf8)!)
        continue
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1, nil
    ) else { continue }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name) (\(px)x\(px))")
}

// Also emit a standalone 1024 png for READMEs etc.
if let img = render(size: 1024) {
    let url = URL(fileURLWithPath: outDir).deletingLastPathComponent().appendingPathComponent("mwitch-logo.png")
    if let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) {
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(url.lastPathComponent)")
    }
}
