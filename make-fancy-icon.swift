#!/usr/bin/env swift
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let outputPath = args.count > 2 ? args[2] : "icon-styled.png"

let size: CGFloat = 1024
let cornerRadius: CGFloat = size * 0.2237

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("Cannot create context"); exit(1)
}

let fullRect = CGRect(x: 0, y: 0, width: size, height: size)
let bgPath = CGPath(roundedRect: fullRect, cornerWidth: cornerRadius,
                    cornerHeight: cornerRadius, transform: nil)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

let topColor = CGColor(red: 0.31, green: 0.92, blue: 0.55, alpha: 1.0)
let botColor = CGColor(red: 0.07, green: 0.55, blue: 0.30, alpha: 1.0)
if let grad = CGGradient(colorsSpace: colorSpace,
                         colors: [topColor, botColor] as CFArray, locations: [0, 1]) {
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])
}

ctx.setFillColor(CGColor(gray: 1, alpha: 0.10))
ctx.addRect(CGRect(x: 0, y: size * 0.5, width: size, height: size * 0.5))
ctx.fillPath()

ctx.restoreGState()

let bodyW = size * 0.62
let bodyH = size * 0.38
let bodyX = (size - bodyW) / 2
let bodyY = (size - bodyH) / 2 - size * 0.02
let bodyR: CGFloat = bodyH * 0.18
let body = CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH)
let bodyPath = CGPath(roundedRect: body, cornerWidth: bodyR, cornerHeight: bodyR, transform: nil)

ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
              blur: size * 0.03,
              color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

let tipW = size * 0.045
let tipH = bodyH * 0.45
let tipX = bodyX + bodyW
let tipY = bodyY + (bodyH - tipH) / 2
let tipR: CGFloat = tipW * 0.4
let tip = CGRect(x: tipX, y: tipY, width: tipW, height: tipH)
ctx.addPath(CGPath(roundedRect: tip, cornerWidth: tipR, cornerHeight: tipR, transform: nil))
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillPath()

let inset = bodyH * 0.14
let inner = body.insetBy(dx: inset, dy: inset)
let innerPath = CGPath(roundedRect: inner, cornerWidth: bodyR * 0.6, cornerHeight: bodyR * 0.6, transform: nil)
ctx.addPath(innerPath)
ctx.setFillColor(topColor)
ctx.fillPath()

let crossArm = inner.height * 0.55
let crossThick = inner.height * 0.16
let cx = inner.midX
let cy = inner.midY
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fill(CGRect(x: cx - crossArm / 2, y: cy - crossThick / 2,
                width: crossArm, height: crossThick))
ctx.fill(CGRect(x: cx - crossThick / 2, y: cy - crossArm / 2,
                width: crossThick, height: crossArm))

ctx.saveGState()
ctx.addPath(bgPath)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.15))
ctx.setLineWidth(size * 0.005)
ctx.strokePath()
ctx.restoreGState()

guard let cg = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: cg)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath) (\(data.count) bytes)")
