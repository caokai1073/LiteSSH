#!/usr/bin/env swift
/// LiteSSH icon generator.
/// Usage: swift generate_icon.swift <output_path.png>
/// Draws a 1024×1024 PNG: two server boxes + bidirectional arrow on dark navy.
/// The build_dmg.sh script scales this down to all required iconset sizes.

import AppKit
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./icon_1024.png"

let size = 1024
guard let ctx = CGContext(
    data: nil,
    width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Failed to create CGContext") }

let s = CGFloat(size)

// ── Background: dark navy, rounded corners ────────────────────────────────────
ctx.setFillColor(CGColor(red: 0.105, green: 0.114, blue: 0.208, alpha: 1))
let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
ctx.addPath(bgPath); ctx.fillPath()

// ── Helper: draw one server rack ─────────────────────────────────────────────
func drawServer(rect: CGRect) {
    // Body (slate blue)
    ctx.setFillColor(CGColor(red: 0.28, green: 0.33, blue: 0.50, alpha: 1))
    ctx.addPath(CGPath(roundedRect: rect,
                       cornerWidth: rect.width * 0.14, cornerHeight: rect.width * 0.14,
                       transform: nil))
    ctx.fillPath()

    // 3 LED lines (teal, semi-transparent)
    ctx.setFillColor(CGColor(red: 0.36, green: 0.88, blue: 0.90, alpha: 0.90))
    let ledH: CGFloat = max(3, rect.height * 0.078)
    let ledW: CGFloat = rect.width * 0.60
    let ledX: CGFloat = rect.minX + (rect.width - ledW) / 2
    let innerH: CGFloat = rect.height * 0.64
    let innerY: CGFloat = rect.minY + (rect.height - innerH) / 2
    let step: CGFloat  = innerH / 3
    for i in 0..<3 {
        let ledY = innerY + CGFloat(i) * step + (step - ledH) / 2
        ctx.addPath(CGPath(roundedRect: CGRect(x: ledX, y: ledY, width: ledW, height: ledH),
                           cornerWidth: ledH / 2, cornerHeight: ledH / 2, transform: nil))
        ctx.fillPath()
    }
}

let srvW: CGFloat = s * 0.20
let srvH: CGFloat = s * 0.38
let srvY: CGFloat = (s - srvH) / 2
drawServer(rect: CGRect(x: s * 0.09,              y: srvY, width: srvW, height: srvH)) // left
drawServer(rect: CGRect(x: s - s * 0.09 - srvW,  y: srvY, width: srvW, height: srvH)) // right

// ── Bidirectional arrow (teal) ────────────────────────────────────────────────
let teal = CGColor(red: 0.36, green: 0.88, blue: 0.90, alpha: 1.0)
ctx.setStrokeColor(teal)
ctx.setFillColor(teal)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let cx = s / 2, cy = s / 2
let hw: CGFloat = s * 0.115   // half-length of shaft
let ah: CGFloat = s * 0.062   // arrowhead arm length

// Shaft
ctx.setLineWidth(s * 0.038)
ctx.move(to: CGPoint(x: cx - hw, y: cy))
ctx.addLine(to: CGPoint(x: cx + hw, y: cy))
ctx.strokePath()

// Arrowheads
ctx.setLineWidth(s * 0.034)
// Left
ctx.move(to: CGPoint(x: cx - hw + ah * 0.80, y: cy + ah * 0.65))
ctx.addLine(to: CGPoint(x: cx - hw, y: cy))
ctx.addLine(to: CGPoint(x: cx - hw + ah * 0.80, y: cy - ah * 0.65))
ctx.strokePath()
// Right
ctx.move(to: CGPoint(x: cx + hw - ah * 0.80, y: cy + ah * 0.65))
ctx.addLine(to: CGPoint(x: cx + hw, y: cy))
ctx.addLine(to: CGPoint(x: cx + hw - ah * 0.80, y: cy - ah * 0.65))
ctx.strokePath()

// ── Save PNG ──────────────────────────────────────────────────────────────────
guard let cgImage = ctx.makeImage() else { fatalError("makeImage failed") }
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("✓ Icon saved to \(outPath)")
