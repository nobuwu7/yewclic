import AppKit
import ScreenCaptureKit

/// A screenshot of the display under the mouse, plus what we need to map
/// pixel coordinates in the image back onto the real screen.
struct CapturedScreen {
    var jpegData: Data
    var cgImage: CGImage
    var pixelWidth: Int
    var pixelHeight: Int
    /// The display's frame in AppKit global coordinates (bottom-left origin).
    var screenFrame: CGRect

    /// Converts a point in screenshot pixels (top-left origin, as the model
    /// sees it) into AppKit global screen coordinates.
    func screenPoint(forImagePoint imagePoint: CGPoint) -> CGPoint {
        let clampedX = min(max(imagePoint.x, 0), CGFloat(pixelWidth))
        let clampedY = min(max(imagePoint.y, 0), CGFloat(pixelHeight))
        return CGPoint(
            x: screenFrame.minX + clampedX / CGFloat(pixelWidth) * screenFrame.width,
            y: screenFrame.maxY - clampedY / CGFloat(pixelHeight) * screenFrame.height
        )
    }
}

enum ScreenCapture {
    /// Long edge of the image we send. Large enough to read UI text, small
    /// enough to keep requests fast and cheap.
    static let maximumLongEdgeInPixels: CGFloat = 1568

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    static func screenUnderMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func captureScreenUnderMouse() async throws -> CapturedScreen {
        let screen = screenUnderMouse()
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            throw ProviderError(message: "Couldn't identify the current display")
        }

        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
            throw ProviderError(message: "Display not available for capture")
        }
        // Keep our own overlay (the buddy and its speech bubble) out of the shot.
        let ownWindows = shareableContent.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

        let scale = min(1, maximumLongEdgeInPixels / max(screen.frame.width * screen.backingScaleFactor, screen.frame.height * screen.backingScaleFactor))
        let configuration = SCStreamConfiguration()
        configuration.width = Int(screen.frame.width * screen.backingScaleFactor * scale)
        configuration.height = Int(screen.frame.height * screen.backingScaleFactor * scale)
        configuration.showsCursor = true

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw ProviderError(message: "Couldn't encode screenshot")
        }

        return CapturedScreen(
            jpegData: jpegData,
            cgImage: cgImage,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            screenFrame: screen.frame
        )
    }
}
