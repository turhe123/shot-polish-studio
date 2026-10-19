import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Loading, downscaling, rendering and encoding of images.
enum ImageTools {
    static func load(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 16_384] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options) ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Converts any NSImage (including TIFF from other apps' pasteboards) into a CGImage.
    static func cgImage(from image: NSImage) -> CGImage? {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first, let cg = rep.cgImage { return cg }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Returns a copy no larger than `maxDimension` on its longest side (for the live preview).
    static func downscaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let width = Int(CGFloat(image.width) * scale), height = Int(CGFloat(image.height) * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    /// Renders the final composition at full source resolution via ImageRenderer.
    @MainActor
    static func render(source: CGImage, boxes: [CGRect], style: PolishStyle) -> CGImage? {
        let redacted = Redactor.apply(boxes, style: style.redactStyle, to: source)
        let size = CGSize(width: source.width, height: source.height)
        let canvas = PolishCanvas(image: NSImage(cgImage: redacted, size: size), pixelSize: size, style: style)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        return renderer.cgImage
    }

    /// Encodes as PNG (alpha kept) or JPEG (flattened onto white).
    static func encode(_ image: CGImage, as format: PolishStyle.Format) -> Data? {
        var output = image
        if format == .jpeg, let flat = flattenedOnWhite(image) { output = flat }
        let data = NSMutableData()
        let type = (format == .png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        let props = [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        CGImageDestinationAddImage(destination, output, format == .jpeg ? props : nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
