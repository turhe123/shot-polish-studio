import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox

/// Shows a full-screen selection overlay on every display, then grabs the chosen region
/// as a single frame with ScreenCaptureKit.
@MainActor
final class RegionCapture {
    private var windows: [NSWindow] = []
    private var completion: ((CGRect, NSScreen) -> Void)?

    enum CaptureError: LocalizedError {
        case noDisplay
        var errorDescription: String? { "The selected display could not be found." }
    }

    /// Presents the overlay. `completion` receives the selected rect (top-left origin, in points) and its screen.
    func begin(completion: @escaping (CGRect, NSScreen) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in self?.finish(rect: rect, screen: screen) }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(rect: CGRect?, screen: NSScreen) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let handler = completion
        completion = nil
        guard let rect, rect.width >= 4, rect.height >= 4 else { return }
        // Convert from view coordinates (bottom-left) to display coordinates (top-left).
        let flipped = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
        handler?(flipped, screen)
    }

    /// Captures `rect` (display points, top-left origin) on `screen` at native resolution.
    static func capture(rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CaptureError.noDisplay }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.sourceRect = rect
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

/// Borderless window that can take key focus so Escape cancels the selection.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Dims the screen and draws the rubber-band selection rectangle.
private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(point.x - start.x), height: abs(point.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) { onFinish?(selection) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        guard let selection else { return }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
        let label = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        label.draw(at: CGPoint(x: selection.minX + 4, y: selection.maxY + 4),
                   withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    }
}

/// Registers a system-wide hotkey through Carbon (works without Accessibility permission).
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var action: (() -> Void)?

    /// Option-Shift-Command-2.
    static let displayString = "⌥⇧⌘2"

    init(action: @escaping () -> Void) {
        GlobalHotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x5350_5354), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
