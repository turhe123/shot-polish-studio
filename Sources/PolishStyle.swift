import SwiftUI
import AppKit

/// All user-adjustable composition settings. Persisted as JSON in UserDefaults; colors are hex strings.
struct PolishStyle: Codable, Equatable {
    enum Background: String, Codable, CaseIterable, Identifiable {
        case preset = "Gradient", solid = "Solid", custom = "Custom", transparent = "None"
        var id: String { rawValue }
    }

    enum Aspect: String, Codable, CaseIterable, Identifiable {
        case free = "Free", square = "1:1", wide = "16:9", classic = "4:3"
        var id: String { rawValue }
        var ratio: CGFloat? {
            switch self {
            case .free: return nil
            case .square: return 1
            case .wide: return 16.0 / 9.0
            case .classic: return 4.0 / 3.0
            }
        }
    }

    enum RedactStyle: String, Codable, CaseIterable, Identifiable {
        case blur = "Blur", pixelate = "Pixelate", solid = "Solid Box"
        var id: String { rawValue }
    }

    enum Format: String, Codable, CaseIterable, Identifiable {
        case png = "PNG", jpeg = "JPEG"
        var id: String { rawValue }
        var fileExtension: String { self == .png ? "png" : "jpg" }
    }

    var background: Background = .preset
    var presetIndex = 0
    var colorA = "#6366F1"
    var colorB = "#EC4899"
    /// Padding as a fraction of the screenshot's longest side.
    var padding: Double = 0.08
    /// Corner radius as a fraction of the screenshot's longest side.
    var cornerRadius: Double = 0.012
    var shadow: Double = 0.6
    var border = false
    var aspect: Aspect = .free
    var autoRedact = false
    var redactStyle: RedactStyle = .blur
    var format: Format = .png

    private static let key = "polishStyle.v1"

    static func load() -> PolishStyle {
        guard let data = UserDefaults.standard.data(forKey: key),
              let style = try? JSONDecoder().decode(PolishStyle.self, from: data) else { return PolishStyle() }
        return style
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Built-in two-color gradient backdrops.
struct GradientPreset: Identifiable {
    let id: Int
    let name: String
    let top: String
    let bottom: String

    static let all: [GradientPreset] = [
        ("Dusk", "#6366F1", "#EC4899"), ("Ocean", "#0EA5E9", "#2563EB"), ("Mint", "#34D399", "#0D9488"),
        ("Sunset", "#F59E0B", "#EF4444"), ("Grape", "#A855F7", "#6D28D9"), ("Peach", "#FDBA74", "#FB7185"),
        ("Slate", "#64748B", "#1E293B"), ("Sky", "#BAE6FD", "#A5B4FC"),
    ].enumerated().map { GradientPreset(id: $0.offset, name: $0.element.0, top: $0.element.1, bottom: $0.element.2) }

    static func at(_ index: Int) -> GradientPreset { all.indices.contains(index) ? all[index] : all[0] }

    var gradient: LinearGradient {
        LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    /// Creates a color from `#RRGGBB`; falls back to gray for malformed input.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self = Color(.sRGB,
                     red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
