import Foundation

/// The model points at things by embedding tags like `[POINT:412,230:Save button]`
/// in its reply. Coordinates are screenshot pixels with a top-left origin.
struct PointTarget: Equatable {
    var imagePoint: CGPoint
    var label: String
}

enum PointTags {
    private static let pattern = try! NSRegularExpression(
        pattern: #"\[POINT:\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*(?::\s*([^\]]*))?\]"#,
        options: [.caseInsensitive]
    )

    static func extractTargets(from text: String) -> [PointTarget] {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            guard let xRange = Range(match.range(at: 1), in: text),
                  let yRange = Range(match.range(at: 2), in: text),
                  let x = Double(text[xRange]), let y = Double(text[yRange]) else { return nil }
            var label = ""
            if let labelRange = Range(match.range(at: 3), in: text) {
                label = String(text[labelRange]).trimmingCharacters(in: .whitespaces)
            }
            return PointTarget(imagePoint: CGPoint(x: x, y: y), label: label)
        }
    }

    /// Text that is safe to show and speak: tags removed, including a
    /// half-streamed tag at the very end.
    static func removeTags(from text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var cleaned = pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        if let partialTagStart = cleaned.range(of: "[POINT", options: [.backwards, .caseInsensitive]),
           !cleaned[partialTagStart.lowerBound...].contains("]") {
            cleaned = String(cleaned[..<partialTagStart.lowerBound])
        }
        return cleaned
            .replacingOccurrences(of: #"\s+([.,!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
