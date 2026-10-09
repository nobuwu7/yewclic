import Foundation

/// The model points at things by embedding tags in its reply:
///   [POINT:412,230:save button]          on the cursor's screen
///   [POINT:400,300:terminal:screen2]     on another monitor
///   [POINT:none]                         nothing worth pointing at
/// Coordinates are screenshot pixels with a top-left origin.
struct PointTarget: Equatable {
    var imagePoint: CGPoint
    var label: String
    /// nil means the cursor's screen (screen 1).
    var screenNumber: Int?
}

enum PointTags {
    private static let pattern = try! NSRegularExpression(
        pattern: #"\[POINT:\s*(?:none|(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*(?::\s*([^\]]*?))?(?::\s*screen\s*(\d+))?)\s*\]"#,
        options: [.caseInsensitive]
    )

    static func extractTargets(from text: String) -> [PointTarget] {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            // [POINT:none] has no coordinate groups.
            guard let xRange = Range(match.range(at: 1), in: text),
                  let yRange = Range(match.range(at: 2), in: text),
                  let x = Double(text[xRange]), let y = Double(text[yRange]) else { return nil }
            var label = ""
            if let labelRange = Range(match.range(at: 3), in: text) {
                label = String(text[labelRange]).trimmingCharacters(in: .whitespaces)
            }
            var screenNumber: Int?
            if let screenRange = Range(match.range(at: 4), in: text) {
                screenNumber = Int(text[screenRange])
            }
            return PointTarget(imagePoint: CGPoint(x: x, y: y), label: label, screenNumber: screenNumber)
        }
    }

    /// Text that is safe to show and speak: tags removed, including a
    /// half-streamed tag at the very end.
    static func removeTags(from text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var cleaned = pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        if let partialTagStart = cleaned.range(of: "[", options: .backwards),
           !cleaned[partialTagStart.lowerBound...].contains("]"),
           "[POINT".lowercased().hasPrefix(cleaned[partialTagStart.lowerBound...].prefix(6).lowercased()) {
            cleaned = String(cleaned[..<partialTagStart.lowerBound])
        }
        return cleaned
            .replacingOccurrences(of: #"\s+([.,!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
