import Foundation
import Vision

/// On-device OCR. Lets text-only models (e.g. DeepSeek, small local models)
/// "see" the screen as a list of text snippets with pixel positions, so they
/// can still answer questions and point at things.
enum ScreenTextReader {
    static func describeScreen(_ screenshot: CapturedScreen, maximumLines: Int = 250) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: screenshot.cgImage)
        do {
            try handler.perform([request])
        } catch {
            return "(Screen text could not be read.)"
        }

        let observations = (request.results ?? [])
            // Read top-to-bottom, then left-to-right, like a person would.
            .sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            .prefix(maximumLines)

        let lines = observations.compactMap { observation -> String? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision boxes are normalised with a bottom-left origin.
            let centerX = Int(observation.boundingBox.midX * CGFloat(screenshot.pixelWidth))
            let centerY = Int((1 - observation.boundingBox.midY) * CGFloat(screenshot.pixelHeight))
            return "(\(centerX),\(centerY)) \(text)"
        }
        return lines.isEmpty ? "(No readable text on screen.)" : lines.joined(separator: "\n")
    }
}
