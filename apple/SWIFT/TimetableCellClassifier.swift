import Foundation

/// Trained binary cell-role model. Extraction, identity and source-cell accounting
/// remain explicit so a prediction can never fabricate a missing lecture.
struct TimetableCellClassifier {
    private struct Parameters: Decodable {
        let version: Int
        let features: [String]
        let intercept: Double
        let weights: [Double]
        let threshold: Double
        let eventTokens: [String]
    }
    private let parameters: Parameters?
    var available: Bool { parameters != nil }
    init(url: URL? = nil) {
        let location = url ?? Bundle.main.url(forResource: "TimetableCellRole", withExtension: "json")
        let expected = ["faculty", "knownCourse", "repeated", "tbd", "guest", "event", "time", "placeholder", "words", "numbered", "section"]
        if let location, let data = try? Data(contentsOf: location),
           let model = try? JSONDecoder().decode(Parameters.self, from: data),
           model.version == 1, model.features == expected, model.weights.count == expected.count,
           model.weights.allSatisfy(\.isFinite), model.intercept.isFinite, (0...1).contains(model.threshold) {
            parameters = model
        } else { parameters = nil }
    }
    func classProbability(text: String, faculty: String, repetitions: Int, knownCourse: Bool) -> Double? {
        guard let p = parameters else { return nil }
        func matches(_ text: String, _ expression: String) -> Bool {
            text.range(of: expression, options: .regularExpression) != nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Placeholders and time-only lines are structural, even for unseen models.
        if ["", ".", "-", "TBD"].contains(trimmed) || matches(trimmed, #"^\d{1,2}[:.]\d{2}\s*[-–—]\s*\d{1,2}[:.]\d{2}$"#) { return 0 }
        let x: [Double] = [
            matches(faculty, #"(?i)^\s*(?:professor|prof\.?|dr\.?|mr\.?|mrs\.?|ms\.?)\s+"#) ? 1 : 0,
            knownCourse ? 1 : 0,
            repetitions > 1 ? 1 : 0,
            matches(faculty, #"(?i)^TBD\d*$"#) ? 1 : 0,
            faculty.uppercased().contains("GUEST") ? 1 : 0,
            p.eventTokens.contains(where: { text.uppercased().contains($0) }) ? 1 : 0,
            0, 0,
            Double(min(text.split(whereSeparator: \.isWhitespace).count, 12)) / 12,
            matches(text, #"\s[-–—]\s*\d+\s*$"#) ? 1 : 0,
            matches(text, #"(?i)\bsec(?:tion)?\.?\s*[A-Z]\b"#) ? 1 : 0
        ]
        let logit = zip(x, p.weights).reduce(p.intercept) { $0 + $1.0 * $1.1 }
        return 1 / (1 + exp(-max(-30, min(30, logit))))
    }
}
