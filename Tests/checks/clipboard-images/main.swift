import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

typealias P = ClipboardPolicy
var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() { failures += 1; print("FAIL (line \(line)): \(message)") }
}
func fixture(_ width: Int, _ height: Int, alpha: Bool = false, type: UTType = .png,
             properties: [CFString: Any] = [:], noise: Bool = false) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if noise {
        var random: UInt64 = 42
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for p in 0..<(width * height) {
            for c in 0..<3 { random = random &* 6364136223846793005 &+ 1; bytes[p * 4 + c] = UInt8(truncatingIfNeeded: random >> 32) }
            bytes[p * 4 + 3] = 255
        }
    } else {
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}
func properties(_ data: Data) -> [CFString: Any] {
    CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil) as! [CFString: Any]
}
let original = fixture(120, 80, alpha: true, properties: [
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 42.0, kCGImagePropertyGPSLatitudeRef: "N"],
    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "private test name"]])
let image = ClipboardImage.prepare(original)!
let payload = P.payload(image: image, accepts: 2)!
check(ClipboardImage.type(of: image) == UTType.png.identifier, "transparency uses PNG")
let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(image as CFData, nil)!, 0, nil)!
check(decoded.alphaInfo == .last || decoded.alphaInfo == .premultipliedLast, "alpha survives normalization")
check(properties(image)[kCGImagePropertyGPSDictionary] == nil, "GPS stripped")
check((properties(image)[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFArtist] == nil, "author stripped")
check(payload.count <= StreamMessage.maxClientPayload, "base64 JSON fits the existing wire cap")
check(Wire.decode(Clipboard.self, from: payload)?.image == image, "binary image round trips through JSON")
let photo = fixture(3000, 1800, type: .jpeg, properties: [kCGImagePropertyOrientation: 6])
let preparedPhoto = ClipboardImage.prepare(photo)!
check(ClipboardImage.type(of: preparedPhoto) == UTType.jpeg.identifier, "opaque photo uses JPEG")
let photoProperties = properties(preparedPhoto)
check(abs((photoProperties[kCGImagePropertyPixelWidth] as? Int ?? 0) - 1229) <= 1 && photoProperties[kCGImagePropertyPixelHeight] as? Int == 2048,
      "large photo is downsampled with EXIF orientation applied")
check((photoProperties[kCGImagePropertyOrientation] as? Int ?? 1) == 1, "orientation no longer needs EXIF")
let tiff = ClipboardImage.prepare(fixture(100, 60, type: .tiff))!
check(ClipboardImage.type(of: tiff) != nil, "Mac TIFF pasteboard representation normalizes")
let noisy = ClipboardImage.prepare(fixture(1200, 1000, noise: true))!
check(noisy.count <= ClipboardImage.maxBytes && ClipboardImage.type(of: noisy) != nil, "incompressible screenshot shrinks to wire budget")
check(ClipboardImage.prepare(Data()) == nil && ClipboardImage.type(of: Data()) == nil, "empty rejected")
check(ClipboardImage.prepare(Data("not an image".utf8)) == nil, "arbitrary bytes rejected")
check(ClipboardImage.prepare(Data(repeating: 0, count: ClipboardImage.maxSourceBytes + 1)) == nil, "source byte cap")
check(ClipboardImage.type(of: Data(repeating: 0, count: ClipboardImage.maxBytes + 1)) == nil, "received byte cap")
check(ClipboardImage.type(of: fixture(2049, 2)) == nil, "received dimensions bounded even when highly compressed")
check(ClipboardImage.type(of: fixture(20, 20, type: .tiff)) == nil, "wire accepts only normalized PNG/JPEG")
check(ClipboardImage.type(of: Data(image.prefix(30))) == nil, "truncated image rejected")
check(P.subscription == Data("{}".utf8), "legacy subscription bytes unchanged")
check(P.subscription(hostClipboard: 1) == P.subscription, "new device with old host stays text only")
check(!P.acceptsImages(P.subscription), "legacy device cannot receive images")
check(P.acceptsImages(P.subscription(hostClipboard: 2)), "new device explicitly opts in")
check(!P.acceptsImages(Wire.encode(Clipboard(accepts: 1))), "generation 1 is text only")
check(P.fromDevice(payload) == .setImage(image), "host takes valid image")
check(P.fromDevice(Wire.encode(Clipboard(text: "caption", image: image))) == .setImage(image), "image wins over caption")
check(P.fromDevice(Wire.encode(Clipboard(image: image, stop: true))) == .stop, "stop wins over image")
check(P.fromDevice(Wire.encode(Clipboard(text: "caption", image: Data([1])))) == .refuse(.undecodable), "invalid image cannot become caption")
check(P.fromDevice(Data(repeating: 32, count: P.maxPayload + 1)) == .refuse(.tooLong), "whole JSON cap before decoding")
check(P.hostReceives(payload, arrivals: [0.2, 0.3, 0.4, 0.5], now: 0.6).ask == .refuse(.rate), "images count against the clipboard rate")
check(P.hostReceives(Wire.encode(Clipboard(image: image, stop: true)), arrivals: [0.2,0.3,0.4,0.5], now: 0.6).ask == .stop, "rate never blocks stopping")
var reads = 0
func host(_ types: [String], own: Int? = nil, data: Data? = image) -> P.HostDecision {
    P.hostDecides(types: types, changeCount: 7, ownChangeCount: own, launchID: "test",
                  ownMarker: { "test" }, text: { reads += 1; return "caption" }, image: { reads += 1; return data })
}
for marker in P.markerTypes + [P.remoteClipboardType, P.ownType] {
    reads = 0
    if case .skip = host(["public.png", marker]) {} else { check(false, "private marker skipped") }
    check(reads == 0, "\(marker): neither image nor text is read")
}
reads = 0
check(host(["public.png"], own: 7) == .skip(.own) && reads == 0, "own change never reads image")
check(host(["public.png"]) == .sendImage(P.payload(image: image)!), "Mac image decision is distinct from text broadcasting")
reads = 0
check(host(["public.png"], data: nil) == .skip(.noText) && reads == 1, "failed conversion never reads a caption/file name")
check(P.deviceImage(payload, switchOn: true, hostClipboard: 2, lastSent: nil, changeCount: 1) == image, "iOS accepts image")
check(P.deviceImage(payload, switchOn: false, hostClipboard: 2, lastSent: nil, changeCount: 1) == nil, "switch off blocks images")
check(P.deviceImage(payload, switchOn: true, hostClipboard: 1, lastSent: nil, changeCount: 1) == nil, "old host cannot send images")
let sent = P.Sent(image: image, changeCount: 4)
check(P.deviceImage(payload, switchOn: true, hostClipboard: 2, lastSent: sent, changeCount: 4) == nil, "image echo suppressed")
check(P.deviceImage(payload, switchOn: true, hostClipboard: 2, lastSent: sent, changeCount: 5) == image, "later clipboard change permits same image")
check(P.offersChip(connected: true, hostClipboard: 2, switchOn: true, hasStrings: false, hasImages: true, changeCount: 2, handled: 1), "image copy offers Paste without reading it")
check(!P.offersChip(connected: true, hostClipboard: 1, switchOn: true, hasStrings: false, hasImages: true, changeCount: 2, handled: 1), "old host gets no image Paste offer")
check(P.deviceSends(["hello"], connected: true, hostClipboard: 1, switchOn: true) == .send(P.payload(text: "hello")!), "legacy text payload unchanged")
check(P.deviceSends(["hello"], connected: true, hostClipboard: 2, switchOn: true) == .send(P.payload(text: "hello", accepts: 2)!), "new text messages retain image opt-in")
print("\(checks) image clipboard checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
