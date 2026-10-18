import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Only a randomly named test board is ever used. Refuse the general board explicitly.
let args = CommandLine.arguments
if args[1] == "make" {
    let ctx = CGContext(data: nil, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 640,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.4, alpha: 0.6))
    ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    exit(CGImageDestinationFinalize(dest) ? 0 : 1)
}
precondition(args[2].hasPrefix("me.saffer.sill.test.images."))
let board = NSPasteboard(name: NSPasteboard.Name(args[2]))
switch args[1] {
case "get":
    if let data = board.data(forType: .png) { print(data.base64EncodedString()) }
case "image":
    board.clearContents()
    let item = NSPasteboardItem()
    item.setData(try Data(contentsOf: URL(fileURLWithPath: args[3])), forType: .png)
    if args.count > 4 { item.setString("private", forType: NSPasteboard.PasteboardType(args[4])) }
    board.writeObjects([item])
case "text":
    board.clearContents(); board.setString(args[3], forType: .string)
case "release": board.releaseGlobally()
default: fatalError("unknown action")
}
