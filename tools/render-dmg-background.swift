#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render-dmg-background.swift OUTPUT.png\n", stderr)
    exit(64)
}

let size = NSSize(width: 760, height: 500)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("unable to create background bitmap\n", stderr)
    exit(2)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.12, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

func draw(
    _ text: String,
    at point: NSPoint,
    width: CGFloat,
    font: NSFont,
    color: NSColor = .white,
    alignment: NSTextAlignment = .center
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    text.draw(
        in: NSRect(x: point.x, y: point.y, width: width, height: 80),
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    )
}

draw(
    "DisplayWeave",
    at: NSPoint(x: 80, y: 425),
    width: 600,
    font: .systemFont(ofSize: 30, weight: .semibold)
)
draw(
    "第 1 步 · 将 DisplayWeave 拖入“应用程序”",
    at: NSPoint(x: 80, y: 350),
    width: 600,
    font: .systemFont(ofSize: 21, weight: .medium)
)
draw(
    "Step 1 · Drag DisplayWeave to Applications",
    at: NSPoint(x: 80, y: 320),
    width: 600,
    font: .systemFont(ofSize: 15),
    color: NSColor(white: 0.78, alpha: 1)
)
draw(
    "➜",
    at: NSPoint(x: 300, y: 205),
    width: 160,
    font: .systemFont(ofSize: 64, weight: .light),
    color: NSColor(calibratedRed: 0.35, green: 0.78, blue: 1, alpha: 1)
)
draw(
    "第 2 步 · 首次运行若被拦截：隐私与安全性 → 仍要打开",
    at: NSPoint(x: 60, y: 55),
    width: 640,
    font: .systemFont(ofSize: 14, weight: .medium)
)
draw(
    "Step 2 · First run: Privacy & Security → Open Anyway",
    at: NSPoint(x: 60, y: 28),
    width: 640,
    font: .systemFont(ofSize: 12),
    color: NSColor(white: 0.72, alpha: 1)
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode background PNG\n", stderr)
    exit(2)
}

try png.write(
    to: URL(fileURLWithPath: CommandLine.arguments[1]),
    options: .atomic
)
