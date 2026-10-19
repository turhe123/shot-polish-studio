import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Finds sensitive-looking text (emails, phone numbers, long digit runs) with on-device Vision OCR
/// and paints blur / pixelate / solid boxes over it with CoreImage.
enum Redactor {
    private static let email = try? NSRegularExpression(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: .caseInsensitive)
    private static let digits = try? NSRegularExpression(pattern: "\\+?\\(?\\d[\\d\\s().-]{5,}\\d")
    private static let context = CIContext()

    /// Returns boxes in Vision-normalized coordinates (0…1, origin bottom-left).
    static func detect(in image: CGImage) async -> [CGRect] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                return []
            }
            var boxes: [CGRect] = []
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                let range = NSRange(text.startIndex..., in: text)
                var matches = email?.matches(in: text, range: range) ?? []
                matches += (digits?.matches(in: text, range: range) ?? []).filter { match in
                    guard let r = Range(match.range, in: text) else { return false }
                    return text[r].filter(\.isNumber).count >= 7
                }
                for match in matches {
                    guard let r = Range(match.range, in: text),
                          let box = try? candidate.boundingBox(for: r)?.boundingBox else { continue }
                    boxes.append(box.insetBy(dx: -0.004, dy: -box.height * 0.15))
                }
            }
            return boxes
        }.value
    }

    /// Applies the redaction boxes to `image`, preserving alpha.
    static func apply(_ boxes: [CGRect], style: PolishStyle.RedactStyle, to image: CGImage) -> CGImage {
        guard !boxes.isEmpty else { return image }
        let source = CIImage(cgImage: image)
        let extent = source.extent
        var output = source
        for box in boxes {
            let rect = CGRect(x: box.minX * extent.width, y: box.minY * extent.height,
                              width: box.width * extent.width, height: box.height * extent.height)
                .intersection(extent).integral
            guard !rect.isEmpty else { continue }
            let patch: CIImage
            switch style {
            case .blur:
                patch = source.cropped(to: rect).clampedToExtent()
                    .applyingGaussianBlur(sigma: max(8, Double(rect.height) * 0.6))
            case .pixelate:
                let filter = CIFilter.pixellate()
                filter.inputImage = source.clampedToExtent()
                filter.scale = Float(max(6, rect.height / 3))
                filter.center = CGPoint(x: rect.minX, y: rect.minY)
                patch = filter.outputImage ?? source
            case .solid:
                patch = CIImage(color: CIColor(red: 0.12, green: 0.12, blue: 0.14))
            }
            output = patch.cropped(to: rect).composited(over: output)
        }
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: space) ?? image
    }
}
