// Lays out crops of window snapshots as one wide strip: tiles in a row with rounded corners, a hairline
// border and a soft shadow, on a transparent background. Used by make-teaser.sh.
//
//   swift collage.swift <out.png> <window width> <output width> <snapshot.png:x,y,w,h[,padY]> ...
//
// Crops are in points of the window, origin top left; <window width> in points gives the snapshots' scale.
// The first tile sets the height. A shorter tile is padded at the bottom with the strip of its snapshot
// that starts at padY, which should be empty space of the same pane.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count > 4, let windowWidth = Double(arguments[2]), let outputWidth = Double(arguments[3]) else {
    print("usage: collage.swift <out.png> <window width> <output width> <snapshot.png:x,y,w,h[,padY]> ...")
    exit(2)
}

struct Tile {
    var image: CGImage
    var snapshot: CGImage
    var crop: CGRect  // in pixels
    var padY: Double?  // in pixels
}

var tiles: [Tile] = []
var scale = 0.0
for spec in arguments.dropFirst(4) {
    guard let colon = spec.lastIndex(of: ":") else { fatalError("no crop in \(spec)") }
    let path = String(spec[..<colon])
    let numbers = spec[spec.index(after: colon)...].split(separator: ",").compactMap { Double($0) }
    guard numbers.count >= 4,
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let snapshot = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fatalError("cannot read \(spec)") }
    scale = Double(snapshot.width) / windowWidth
    let crop = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        .applying(CGAffineTransform(scaleX: scale, y: scale)).integral
    tiles.append(Tile(image: snapshot.cropping(to: crop)!, snapshot: snapshot, crop: crop,
                      padY: numbers.count > 4 ? (numbers[4] * scale).rounded() : nil))
}

// Spacing in points, like the crops.
let gap = 28 * scale, margin = 20 * scale, radius = 15 * scale
let height = Double(tiles[0].image.height)
let width = tiles.map { Double($0.image.width) }.reduce(0, +) + gap * Double(tiles.count - 1) + 2 * margin
let canvasHeight = height + 2 * margin

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
let context = CGContext(data: nil, width: Int(width), height: Int(canvasHeight), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: bitmapInfo)!
context.interpolationQuality = .high
var x = margin
for tile in tiles {
    let w = Double(tile.image.width), h = Double(tile.image.height)
    let rect = CGRect(x: x, y: margin, width: w, height: height)
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    // The shadow falls from an opaque shape that the tile then covers.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -3 * scale), blur: 14 * scale, color: CGColor(gray: 0, alpha: 0.45))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0.16, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    // Core Graphics counts y from the bottom: the crop goes to the top of the tile, the padding below it.
    if let padY = tile.padY, h < height,
       let pad = tile.snapshot.cropping(to: CGRect(x: tile.crop.minX, y: padY, width: w, height: height - h)) {
        let padHeight = Double(pad.height)
        context.draw(pad, in: CGRect(x: x, y: margin + height - h - padHeight, width: w, height: padHeight))
    }
    context.draw(tile.image, in: CGRect(x: x, y: margin + height - h, width: w, height: h))
    context.restoreGState()
    context.addPath(shape)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    context.setLineWidth(scale)
    context.strokePath()
    x += w + gap
}

let resized = Int(outputWidth), resizedHeight = Int((canvasHeight * outputWidth / width).rounded())
let output = CGContext(data: nil, width: resized, height: resizedHeight, bitsPerComponent: 8, bytesPerRow: 0,
                       space: space, bitmapInfo: bitmapInfo)!
output.interpolationQuality = .high
output.draw(context.makeImage()!, in: CGRect(x: 0, y: 0, width: resized, height: resizedHeight))
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL,
                                                  UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, output.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(arguments[1])") }
print("\(arguments[1]): \(resized) x \(resizedHeight)")
