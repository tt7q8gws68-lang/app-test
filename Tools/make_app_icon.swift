// Renders the app icon (the "assignments" glyph: a rounded square with a check) into the asset
// catalog, light and dark. Run from the repository root:  swift Tools/make_app_icon.swift
//
// Light: white glyph on #5B4BEA. Dark: #8C7DFF glyph on #12101F. The glyph spans about 57% of
// the icon width, centered, drawn from the same 24pt-grid geometry as AppIcon.assignments.

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let folder = "AssignmentTracker/AssignmentTracker/Resources/Assets.xcassets/AppIcon.appiconset"

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(background: UInt32, glyph: UInt32, to name: String) {
    let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(color(background))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // The glyph's rounded square is 16 of 24 grid units; make it ~57% of the icon.
    let scale = size * 0.57 / 16
    context.translateBy(x: size / 2, y: size / 2)
    context.scaleBy(x: scale, y: -scale) // flip to SVG's y-down grid
    context.translateBy(x: -12, y: -12)

    let path = CGMutablePath()
    path.addRoundedRect(in: CGRect(x: 4, y: 4, width: 16, height: 16), cornerWidth: 4.5, cornerHeight: 4.5)
    path.move(to: CGPoint(x: 8.5, y: 12.2))
    path.addLine(to: CGPoint(x: 10.9, y: 14.6))
    path.addLine(to: CGPoint(x: 15.5, y: 9.8))
    context.addPath(path)
    context.setStrokeColor(color(glyph))
    context.setLineWidth(1.75)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(folder)/\(name)"))
}

render(background: 0x5B4BEA, glyph: 0xFFFFFF, to: "AppIcon-Light.png")
render(background: 0x12101F, glyph: 0x8C7DFF, to: "AppIcon-Dark.png")

let contents = """
{
  "images" : [
    {
      "filename" : "AppIcon-Light.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "AppIcon-Dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try! contents.write(toFile: "\(folder)/Contents.json", atomically: true, encoding: .utf8)
print("Wrote app icons to \(folder)")
