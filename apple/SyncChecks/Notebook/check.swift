import Foundation
@main struct NotebookChecks {
    static func main() throws {
        let paper = PaperConfiguration()
        assert(paper.width == 595 && paper.height == 842 && paper.template == .ruled)
        var landscape = paper; landscape.landscape = true
        assert(landscape.width == 842 && landscape.height == 595)
        assert(NotebookPageOrder.moving(["a", "b", "c"], from: 2, to: 0) == ["c", "a", "b"])
        let selected = try NotebookPageOrder.selection("1-3, 5", count: 5); assert(selected == [0, 1, 2, 4])
        for invalid in ["0", "6", "3-1", "1-2-3", ""] {
            do { _ = try NotebookPageOrder.selection(invalid, count: 5); fatalError("Invalid selection accepted") } catch NotebookFailure.invalidRange { }
        }
        var doc = NotebookPageDocument(id: "page", notebookID: "book")
        assert(!doc.hasContent)
        doc.textObjects = [NotebookTextObject(text: "   ")]; assert(!doc.hasContent)
        doc.textObjects[0].text = "Editable text"; assert(doc.hasContent)
        doc.drawing = Data([1, 2, 3])
        let decoded = try JSONDecoder().decode(NotebookPageDocument.self, from: JSONEncoder().encode(doc)); assert(decoded == doc)
        var manifest = NotebookManifest(); manifest.pageIDs = (0..<500).map { "page-\($0)" }
        let restored = try JSONDecoder().decode(NotebookManifest.self, from: JSONEncoder().encode(manifest))
        assert(restored.pageIDs == manifest.pageIDs)
        let events = (0..<8).map { SATHICommandEvent(id: "excel-\($0)", date: "2026-10-27", title: "END TERM EXAMINATIONS", time: "08:15 – 09:45") }
        let consolidated = EventPresentation.consolidate(events)
        assert(consolidated.count == 1 && consolidated[0].time == "All day")
        assert(consolidated[0].title == "End-term examinations")
        assert(EventPresentation.widgetRows(events).first?.eventKind == "day")
        assert(EventPresentation.consolidate([.init(id: "custom-a", date: "2026-10-27", title: "Workshop", time: "09:00 – 10:00"), .init(id: "custom-b", date: "2026-10-27", title: "Workshop", time: "11:00 – 12:00")]).count == 2)
        print("Notebook foundation passed: empty drafts, 500-page metadata, editable text/ink round trip, paper geometry, ordering/export ranges and exam-day widget grouping.")
    }
}
