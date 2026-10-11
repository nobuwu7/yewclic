import AppKit
import ScreenCaptureKit

/// A screenshot of one display, plus what we need to map pixel coordinates
/// in the image back onto the real screen.
struct CapturedScreen {
    var jpegData: Data
    var cgImage: CGImage
    var pixelWidth: Int
    var pixelHeight: Int
    /// The display's frame in AppKit global coordinates (bottom-left origin).
    var screenFrame: CGRect
    /// 1-based, cursor screen is always screen 1.
    var screenNumber: Int
    var isCursorScreen: Bool
    /// How the model is told about this image, e.g. "screen 2 of 2, secondary".
    var label: String

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

    /// The line that goes next to the image in the request.
    var promptCaption: String {
        "[Image: \(label), \(pixelWidth)x\(pixelHeight) pixels]"
    }
}

enum ScreenCapture {
    /// Long edge of each image. One screen gets more detail; with several
    /// screens each is smaller to keep requests fast (Clicky uses 1280).
    static let singleScreenLongEdgeInPixels: CGFloat = 1568
    static let multiScreenLongEdgeInPixels: CGFloat = 1280

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    static func screenUnderMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame == frame }
    }

    /// Captures every connected display, cursor screen first. The model gets
    /// context from all monitors and can point at things on any of them.
    static func captureAllScreens() async throws -> [CapturedScreen] {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Keep our own overlay (the buddy and its speech bubble) out of the shot.
        let ownWindows = shareableContent.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        let mouseLocation = NSEvent.mouseLocation
        // Use NSScreen frames (AppKit coordinates) rather than SCDisplay frames
        // (top-left origin) so everything shares one coordinate system.
        let screensWithDisplays: [(screen: NSScreen, display: SCDisplay)] = NSScreen.screens.compactMap { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else { return nil }
            return (screen, display)
        }
        .sorted { first, _ in NSMouseInRect(mouseLocation, first.screen.frame, false) }

        guard !screensWithDisplays.isEmpty else {
            throw ProviderError(message: "No display available for capture")
        }

        let longEdge = screensWithDisplays.count == 1 ? singleScreenLongEdgeInPixels : multiScreenLongEdgeInPixels
        var capturedScreens: [CapturedScreen] = []

        for (index, pair) in screensWithDisplays.enumerated() {
            let screen = pair.screen
            let isCursorScreen = NSMouseInRect(mouseLocation, screen.frame, false)
            let nativeWidth = screen.frame.width * screen.backingScaleFactor
            let nativeHeight = screen.frame.height * screen.backingScaleFactor
            let scale = min(1, longEdge / max(nativeWidth, nativeHeight))

            let configuration = SCStreamConfiguration()
            configuration.width = Int(nativeWidth * scale)
            configuration.height = Int(nativeHeight * scale)
            configuration.showsCursor = true

            let filter = SCContentFilter(display: pair.display, excludingWindows: ownWindows)
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard let jpegData = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                continue
            }

            let label: String
            if screensWithDisplays.count == 1 {
                label = "the user's screen (cursor is here)"
            } else if isCursorScreen {
                label = "screen \(index + 1) of \(screensWithDisplays.count), cursor is here (primary focus)"
            } else {
                label = "screen \(index + 1) of \(screensWithDisplays.count), secondary screen"
            }

            capturedScreens.append(CapturedScreen(
                jpegData: jpegData,
                cgImage: cgImage,
                pixelWidth: cgImage.width,
                pixelHeight: cgImage.height,
                screenFrame: screen.frame,
                screenNumber: index + 1,
                isCursorScreen: isCursorScreen,
                label: label
            ))
        }

        guard !capturedScreens.isEmpty else {
            throw ProviderError(message: "Couldn't capture any screen")
        }
        return capturedScreens
    }
}
