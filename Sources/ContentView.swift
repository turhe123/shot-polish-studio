import SwiftUI
import UniformTypeIdentifiers

/// Main window: live preview in the center, settings sidebar with Background, Layout, Redaction and Export.
struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 360)
        } detail: {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
                .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { state.handleDrop($0) }
                .toolbar {
                    ToolbarItemGroup {
                        Button { state.startCapture() } label: { Label("Capture Region", systemImage: "camera.viewfinder") }
                            .help("Capture a screen region (\(GlobalHotKey.displayString))")
                        Button { state.openImage() } label: { Label("Open Image", systemImage: "photo.badge.plus") }
                        Button { state.copyToClipboard() } label: { Label("Copy", systemImage: "doc.on.doc") }
                            .disabled(state.source == nil)
                        Button { state.saveAs() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                            .disabled(state.source == nil)
                    }
                }
        }
        .frame(minWidth: 860, minHeight: 540)
        .onAppear { state.openMainWindow = { openWindow(id: "main") } }
    }

    @ViewBuilder private var preview: some View {
        if let image = state.previewImage, state.source != nil {
            GeometryReader { geo in
                let canvas = PolishCanvas.canvasSize(for: state.pixelSize, style: state.style)
                let factor = max(0.01, min((geo.size.width - 48) / canvas.width, (geo.size.height - 48) / canvas.height))
                PolishCanvas(image: image, pixelSize: state.pixelSize, style: state.style, factor: factor,
                             boxes: state.boxes, onTapBox: { state.removeBox(at: $0) })
                    .background(checkerboard.opacity(state.style.background == .transparent ? 1 : 0))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .overlay(alignment: .bottom) { statusBanner }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 44, weight: .light))
                Text("Drop, paste or capture an image").font(.title3.weight(.medium))
                Text("Capture with \(GlobalHotKey.displayString) · Paste with ⌘V").font(.callout).foregroundStyle(.secondary)
            }
            .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isTargeted ? Color.accentColor : .secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .padding(32)
            .overlay(alignment: .bottom) { statusBanner }
        }
    }

    private var checkerboard: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 10
            for row in 0..<Int(size.height / tile) + 1 {
                for col in 0..<Int(size.width / tile) + 1 where (row + col).isMultiple(of: 2) {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)), with: .color(.gray.opacity(0.25)))
                }
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if let status = state.status {
            Text(status)
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 14)
                .transition(.opacity)
        }
    }
}

/// Sidebar controls bound to the persisted `PolishStyle`.
struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Background") {
                Picker("Type", selection: $state.style.background) {
                    ForEach(PolishStyle.Background.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch state.style.background {
                case .preset:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(GradientPreset.all) { preset in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(preset.gradient)
                                .frame(height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.primary, lineWidth: state.style.presetIndex == preset.id ? 2 : 0))
                                .onTapGesture { state.style.presetIndex = preset.id }
                                .help(preset.name)
                        }
                    }
                case .solid:
                    ColorPicker("Color", selection: hexBinding(\.colorA), supportsOpacity: false)
                case .custom:
                    ColorPicker("Top color", selection: hexBinding(\.colorA), supportsOpacity: false)
                    ColorPicker("Bottom color", selection: hexBinding(\.colorB), supportsOpacity: false)
                case .transparent:
                    Text("PNG keeps transparency; JPEG uses white.").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Layout") {
                LabeledSlider(title: "Padding", value: $state.style.padding, range: 0...0.3)
                LabeledSlider(title: "Corner radius", value: $state.style.cornerRadius, range: 0...0.06)
                LabeledSlider(title: "Shadow", value: $state.style.shadow, range: 0...1)
                Toggle("Window border", isOn: $state.style.border)
                Picker("Aspect ratio", selection: $state.style.aspect) {
                    ForEach(PolishStyle.Aspect.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("Redaction") {
                Toggle("Auto-redact emails & numbers", isOn: $state.style.autoRedact)
                Picker("Style", selection: $state.style.redactStyle) {
                    ForEach(PolishStyle.RedactStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                if state.style.autoRedact {
                    if state.isDetecting {
                        HStack { ProgressView().controlSize(.small); Text("Scanning text…").foregroundStyle(.secondary) }
                    } else if state.nothingDetected && state.boxes.isEmpty {
                        Text("Nothing sensitive detected.").foregroundStyle(.secondary)
                    } else if !state.boxes.isEmpty {
                        Text("\(state.boxes.count) area(s) redacted — click a box in the preview to remove it.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Scan Again") { state.runDetection() }.disabled(state.source == nil || state.isDetecting)
                        Button("Undo") { state.undo() }.disabled(!state.canUndo)
                    }
                }
                Text("Auto-redaction is a helper, not a guarantee. Review the preview before sharing.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Export") {
                Picker("Format", selection: $state.style.format) {
                    ForEach(PolishStyle.Format.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Copy to Clipboard  ⌘C") { state.copyToClipboard() }.disabled(state.source == nil)
                Button("Save As…  ⌘S") { state.saveAs() }.disabled(state.source == nil)
                Button("Save to Default Folder  ⌥⌘S") { state.saveToDefaultFolder() }.disabled(state.source == nil)
                LabeledContent("Folder") {
                    Button(state.saveFolder.lastPathComponent) { state.chooseSaveFolder() }
                        .help(state.saveFolder.path)
                }
            }

            Section {
                Button("Support / Donate ❤️") { AppState.openDonation() }
            }
        }
        .formStyle(.grouped)
    }

    private func hexBinding(_ keyPath: WritableKeyPath<PolishStyle, String>) -> Binding<Color> {
        Binding(get: { Color(hex: state.style[keyPath: keyPath]) },
                set: { state.style[keyPath: keyPath] = $0.hexString })
    }
}

/// Slider with a title and percentage readout.
private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range).labelsHidden()
        }
    }
}
