import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Bounded, metadata-free clipboard images shared by the Mac and iOS clients.
public enum ClipboardImage {
    /// Base64 plus JSON must fit the existing 1 MiB client-message limit.
    public static let maxBytes = 700 * 1024
    public static let maxDimension = 2048
    public static let maxSourceBytes = 32 * 1024 * 1024
    public static let maxSourcePixels = 100_000_000
    public static let sourceTypes = ["public.png", "public.jpeg", "public.tiff", "public.heic", "public.heif"]

    /// Downsample before decoding the full image; preserve transparency, apply orientation and
    /// omit EXIF/GPS metadata. PNG/JPEG/HEIC/TIFF pasteboard representations are accepted here.
    public static func prepare(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maxSourceBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              dimensions(source, maximum: maxSourcePixels) != nil else { return nil }
        for side in [2048, 1536, 1024, 768, 512, 384, 256] {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: side,
                kCGImageSourceShouldCacheImmediately: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let alpha = [.first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly].contains(image.alphaInfo)
            let type = alpha ? UTType.png : UTType.jpeg
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, type.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            let encoded = result as Data
            if encoded.count <= maxBytes { return encoded }
        }
        return nil
    }

    /// Validate received bytes before handing them to either system pasteboard. A compressed size
    /// cap alone is insufficient: a small PNG can declare an enormous decoded image.
    public static func type(of data: Data) -> String? {
        guard !data.isEmpty, data.count <= maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              type == UTType.png.identifier || type == UTType.jpeg.identifier,
              let size = dimensions(source, maximum: maxDimension * maxDimension),
              size.0 <= maxDimension, size.1 <= maxDimension,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary) != nil else { return nil }
        return type
    }

    private static func dimensions(_ source: CGImageSource, maximum: Int) -> (Int, Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int,
              let h = properties[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= maximum, h <= maximum, w <= maximum / h else { return nil }
        return (w, h)
    }
}
