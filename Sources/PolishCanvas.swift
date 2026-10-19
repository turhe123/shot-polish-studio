import SwiftUI

/// The composed result: backdrop, padding, rounded/shadowed screenshot. Used both for the live preview
/// and (via ImageRenderer at factor 1) for export, so both are pixel-for-pixel consistent.
struct PolishCanvas: View {
    let image: NSImage
    /// Full-resolution pixel size of the screenshot; layout is computed from this.
    let pixelSize: CGSize
    let style: PolishStyle
    /// Points per source pixel. 1 for export, smaller for the preview.
    var factor: CGFloat = 1
    /// Redaction boxes in Vision-normalized coordinates (origin bottom-left). Shown only when `onTapBox` is set.
    var boxes: [CGRect] = []
    var onTapBox: ((Int) -> Void)?

    /// Canvas size (in source pixels) that holds the padded screenshot, expanded to the requested aspect ratio.
    static func canvasSize(for pixelSize: CGSize, style: PolishStyle) -> CGSize {
        let pad = max(pixelSize.width, pixelSize.height) * style.padding
        var size = CGSize(width: pixelSize.width + pad * 2, height: pixelSize.height + pad * 2)
        if let ratio = style.aspect.ratio {
            if size.width / size.height < ratio { size.width = size.height * ratio } else { size.height = size.width / ratio }
        }
        return CGSize(width: size.width.rounded(), height: size.height.rounded())
    }

    var body: some View {
        let canvas = Self.canvasSize(for: pixelSize, style: style)
        let base = max(pixelSize.width, pixelSize.height) * factor
        let shape = RoundedRectangle(cornerRadius: base * style.cornerRadius, style: .continuous)
        let imageSize = CGSize(width: pixelSize.width * factor, height: pixelSize.height * factor)

        ZStack {
            backdrop
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: imageSize.width, height: imageSize.height)
                .clipShape(shape)
                .overlay {
                    if style.border {
                        shape.strokeBorder(Color.white.opacity(0.45), lineWidth: max(1, base * 0.0015))
                        shape.inset(by: max(1, base * 0.0015)).strokeBorder(Color.black.opacity(0.18), lineWidth: max(0.5, base * 0.0008))
                    }
                }
                .shadow(color: .black.opacity(0.55 * style.shadow), radius: base * 0.035 * style.shadow, y: base * 0.015 * style.shadow)
                .overlay { if onTapBox != nil { boxOverlay(in: imageSize) } }
        }
        .frame(width: canvas.width * factor, height: canvas.height * factor)
    }

    @ViewBuilder private var backdrop: some View {
        switch style.background {
        case .preset: GradientPreset.at(style.presetIndex).gradient
        case .solid: Color(hex: style.colorA)
        case .custom:
            LinearGradient(colors: [Color(hex: style.colorA), Color(hex: style.colorB)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .transparent: Color.clear
        }
    }

    private func boxOverlay(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(boxes.enumerated()), id: \.offset) { index, box in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(Rectangle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .frame(width: box.width * size.width, height: box.height * size.height)
                    .offset(x: box.minX * size.width, y: (1 - box.maxY) * size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapBox?(index) }
                    .help("Click to remove this redaction")
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
