import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Central model: the loaded screenshot, redaction boxes with undo history, persisted style,
/// and all user actions (capture, open, paste, copy, save).
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var style = PolishStyle.load() {
        didSet {
            style.save()
            if style.autoRedact != oldValue.autoRedact { style.autoRedact ? runDetection() : clearRedactions() }
            if style.redactStyle != oldValue.redactStyle { refreshPreview() }
        }
    }
    @Published private(set) var source: CGImage?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var boxes: [CGRect] = []
    @Published private(set) var isDetecting = false
    @Published private(set) var nothingDetected = false
    @Published var status: String?
    @Published private(set) var saveFolder: URL

    var openMainWindow: (() -> Void)?
    private var previewSource: CGImage?
    private var history: [[CGRect]] = []
    private let capture = RegionCapture()
    private var hotKey: GlobalHotKey?
    private static let folderKey = "saveFolderBookmark"

    var canUndo: Bool { !history.isEmpty }
    var pixelSize: CGSize { CGSize(width: source?.width ?? 0, height: source?.height ?? 0) }

    private init() {
        saveFolder = Self.resolveSaveFolder()
        hotKey = GlobalHotKey { AppState.shared.startCapture() }
    }

    // MARK: Input

    func setImage(_ image: CGImage) {
        source = image
        previewSource = ImageTools.downscaled(image, maxDimension: 1800)
        history.removeAll()
        boxes = []
        nothingDetected = false
        isDetecting = false
        refreshPreview()
        if style.autoRedact { runDetection() }
        bringToFront()
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        bringToFront()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    func load(url: URL) {
        guard let image = ImageTools.load(url: url) else { return flash("Couldn’t read that image.") }
        setImage(image)
    }

    func paste() {
        let pb = NSPasteboard.general
        if let url = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL])?.first {
            return load(url: url)
        }
        guard let image = NSImage(pasteboard: pb), let cg = ImageTools.cgImage(from: image) else {
            return flash("The clipboard doesn’t contain an image.")
        }
        setImage(cg)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in AppState.shared.load(url: url) }
            }
            return true
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data, let image = NSImage(data: data), let cg = ImageTools.cgImage(from: image) else { return }
            Task { @MainActor in AppState.shared.setImage(cg) }
        }
        return true
    }

    // MARK: Capture

    func startCapture() {
        guard CGPreflightScreenCaptureAccess() else { return requestScreenRecording() }
        capture.begin { rect, screen in
            Task { @MainActor in
                do {
                    let image = try await RegionCapture.capture(rect: rect, on: screen)
                    AppState.shared.setImage(image)
                } catch {
                    AppState.shared.bringToFront()
                    AppState.shared.flash("Capture failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func requestScreenRecording() {
        bringToFront()
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "ShotPolishStudio only needs this to capture a region of your screen. Images never leave your Mac. Dropping or pasting images works without it.\n\nAfter granting access in System Settings, you may need to relaunch the app."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if !CGRequestScreenCaptureAccess() { flash("Screen Recording not granted yet — enable it in System Settings › Privacy & Security.") }
        case .alertSecondButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        default: break
        }
    }

    // MARK: Redaction

    func runDetection() {
        guard let source else { return }
        isDetecting = true
        nothingDetected = false
        Task {
            let found = await Redactor.detect(in: source)
            guard source === self.source, style.autoRedact else { return }
            isDetecting = false
            nothingDetected = found.isEmpty
            setBoxes(found)
        }
    }

    private func clearRedactions() {
        isDetecting = false
        nothingDetected = false
        setBoxes([])
    }

    func removeBox(at index: Int) {
        guard boxes.indices.contains(index) else { return }
        var next = boxes
        next.remove(at: index)
        setBoxes(next)
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        boxes = previous
        refreshPreview()
    }

    private func setBoxes(_ newBoxes: [CGRect]) {
        guard newBoxes != boxes else { return }
        history.append(boxes)
        boxes = newBoxes
        refreshPreview()
    }

    private func refreshPreview() {
        guard let previewSource else { previewImage = nil; return }
        let redacted = Redactor.apply(boxes, style: style.redactStyle, to: previewSource)
        previewImage = NSImage(cgImage: redacted, size: CGSize(width: redacted.width, height: redacted.height))
    }

    // MARK: Export

    private func renderedData() -> Data? {
        guard let source else { flash("Nothing to export yet."); return nil }
        guard let image = ImageTools.render(source: source, boxes: boxes, style: style),
              let data = ImageTools.encode(image, as: style.format) else { flash("Rendering failed."); return nil }
        return data
    }

    func copyToClipboard() {
        guard let source, let image = ImageTools.render(source: source, boxes: boxes, style: style),
              let png = ImageTools.encode(image, as: .png) else { return flash("Nothing to copy yet.") }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        flash("Copied to clipboard.")
    }

    func saveAs() {
        guard let data = renderedData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [style.format == .png ? .png : .jpeg]
        panel.nameFieldStringValue = defaultFileName()
        panel.directoryURL = saveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(data, to: url)
    }

    func saveToDefaultFolder() {
        guard let data = renderedData() else { return }
        let scoped = saveFolder.startAccessingSecurityScopedResource()
        defer { if scoped { saveFolder.stopAccessingSecurityScopedResource() } }
        write(data, to: saveFolder.appendingPathComponent(defaultFileName()))
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = saveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveFolder = url
        if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: Self.folderKey)
        }
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
            flash("Saved \(url.lastPathComponent)")
        } catch {
            flash("Save failed: \(error.localizedDescription)")
        }
    }

    private func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Polished \(formatter.string(from: Date())).\(style.format.fileExtension)"
    }

    private static func resolveSaveFolder() -> URL {
        var stale = false
        if let data = UserDefaults.standard.data(forKey: folderKey),
           let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
            return url
        }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: Helpers

    func bringToFront() {
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func flash(_ message: String) {
        status = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if status == message { status = nil }
        }
    }

    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
