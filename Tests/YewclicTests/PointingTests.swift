import CoreGraphics
import Foundation
import Testing
@testable import Yewclic

struct PointTagTests {
    @Test func parsesLabelsScreensAndNone() {
        let reply = "see the terminal? [POINT:400,300:terminal:screen2] then save [POINT:10,20:save button] [POINT:none]"
        #expect(PointTags.extractTargets(from: reply) == [
            PointTarget(imagePoint: CGPoint(x: 400, y: 300), label: "terminal", screenNumber: 2),
            PointTarget(imagePoint: CGPoint(x: 10, y: 20), label: "save button", screenNumber: nil),
        ])
    }

    @Test func removesTagsForSpeaking() {
        #expect(PointTags.removeTags(from: "click save [POINT:1,2:save].") == "click save.")
        #expect(PointTags.removeTags(from: "html is a language. [POINT:none]") == "html is a language.")
    }

    @Test func hidesAHalfStreamedTag() {
        #expect(PointTags.removeTags(from: "it's up top [POI") == "it's up top")
    }

    @Test func leavesOrdinaryBracketsAlone() {
        #expect(PointTags.removeTags(from: "an array [1, 2] stays") == "an array [1, 2] stays")
    }
}

struct ScreenMappingTests {
    @Test func mapsImagePixelsOntoTheRightPartOfTheDisplay() throws {
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        // A 1000x500-pixel screenshot of a 2000x1000-point display that sits
        // to the right of the main one (AppKit coordinates, bottom-left origin).
        let screenshot = CapturedScreen(jpegData: Data(), cgImage: image, pixelWidth: 1000, pixelHeight: 500,
                                        screenFrame: CGRect(x: 1440, y: 0, width: 2000, height: 1000),
                                        screenNumber: 2, isCursorScreen: false, label: "test")

        #expect(screenshot.screenPoint(forImagePoint: CGPoint(x: 0, y: 0)) == CGPoint(x: 1440, y: 1000))
        #expect(screenshot.screenPoint(forImagePoint: CGPoint(x: 500, y: 250)) == CGPoint(x: 2440, y: 500))
        #expect(screenshot.screenPoint(forImagePoint: CGPoint(x: 5000, y: -10)) == CGPoint(x: 3440, y: 1000), "clamped")
    }
}
