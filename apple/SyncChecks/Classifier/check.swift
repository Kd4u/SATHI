import Foundation
@main struct ClassifierChecks {
    static func main() throws {
        let model = TimetableCellClassifier(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        assert(model.available)
        func score(_ text: String, _ faculty: String = "", _ repetitions: Int = 1, _ known: Bool = false) -> Double {
            model.classProbability(text: text, faculty: faculty, repetitions: repetitions, knownCourse: known)!
        }
        assert(score("Business Research Methodology", "", 10) > 0.5)
        assert(score("Dynamics of Health Insurance & Pharmaceutical Business", "TBD8") > 0.5)
        assert(score("Workshop on Interviews and Presentations", "(Guest Session)", 7, true) > 0.5)
        assert(score("Spanish", "Prof. Faculty", 20, true) > 0.5)
        assert(score("END TERM EXAMINATIONS", "", 40) < 0.5)
        assert(score("TEDX", "", 20) < 0.5)
        assert(score(".", ".", 19) == 0)
        assert(score("21:15-22:45") == 0)
        let unavailable = TimetableCellClassifier(url: URL(fileURLWithPath: "/missing-model.json"))
        assert(!unavailable.available && unavailable.classProbability(text: "Course", faculty: "", repetitions: 2, knownCourse: false) == nil)
        print("Trained cell-role model passed: blank/TBD/guest faculty, classes, events, placeholders, time-only lines and unavailable-model fallback.")
    }
}
