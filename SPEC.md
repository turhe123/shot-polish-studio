# ShotPolishStudio — specification

**Tagline:** Turn a raw screenshot into a share-ready image with a gradient backdrop, padding, shadow and rounded corners.

**Category:** Menu Bar Utility

**Inspired by (paid):** Xnapper ($24.99 one-time)

**Frameworks:** SwiftUI, AppKit, CoreGraphics, CoreImage, UniformTypeIdentifiers, ScreenCaptureKit, Vision

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and evidence of demand. Xnapper is a Mac screenshot beautifier priced around fifteen to twenty-five dollars one time depending on seat count and promotions. It captures a region, automatically adds a pleasing background, padding and shadow, can balance the composition, redact emails and sensitive text, and exports with social media presets. It appears in every best screenshot apps for Mac roundup and has been sold in deal bundles, which signals steady demand from people who post product screenshots. Our clean-room version focuses on the beautifying step only.

Feature set for our version. The user captures a region with a hotkey, or drops or pastes an image onto the window. The app composes the image over a chosen background: a set of built-in two-color gradients, a solid color, or a custom color pair, with sliders for padding, corner radius, shadow strength and an optional thin window-style border. An auto-redact toggle uses on-device text recognition to find strings that look like email addresses, phone numbers or long digit sequences and draws blur or solid boxes over them, with a preview where each box can be clicked to remove it. Output aspect ratio presets include free, square, sixteen by nine and four by three, with the screenshot centered and scaled. Export actions are Copy to Clipboard, Save As PNG or JPEG, and Save to a default folder.

UI spec. This is a regular window app with a small menu bar item for capturing. The window has a large live preview in the center, and a sidebar with sections Background, Layout, Redaction and Export. The menu bar menu has Capture Region, Open Image, and Quit. Keyboard shortcuts: a global hotkey for capture, Command-C to copy the result, Command-S to save, Command-Z to undo a redaction change. Empty state shows a dashed drop zone with the text Drop, paste or capture an image. Settings are inside the sidebar and remembered between launches, including last background, padding values, and default save folder.

Technical approach. Capture uses ScreenCaptureKit single-frame capture with a region overlay window. Composition uses a SwiftUI view rendered by ImageRenderer at export scale, which keeps the preview and the exported image identical, with a rounded rectangle clip and a shadow modifier. Redaction detection uses a Vision text recognition request and regular expressions over each recognized line, mapping matched bounding boxes back to image coordinates, then applying a CoreImage pixelate or Gaussian blur through a mask. Saving uses an image destination with UniformTypeIdentifiers for PNG and JPEG. Persistence is AppStorage for numeric and color values, with colors encoded as hex strings. Screen Recording permission is required only for the capture feature and is requested lazily with a plain explanation, while dropping files needs no permission. Sandbox file access for the save folder uses a user chosen folder stored through a security scoped bookmark if sandboxed.

Edge cases and error handling. Very large images are downscaled for the live preview but exported at full resolution. Transparent screenshots keep alpha when saved as PNG and use a white fill for JPEG. Clipboard images from other apps may arrive as TIFF and must be converted. If recognition finds no sensitive text, show a quiet note saying nothing detected, and remind users that auto-redaction is a helper and not a guarantee, so they should review the preview before sharing.
