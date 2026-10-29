import Foundation
import PDFKit
import PencilKit
@main struct NotebookPDFChecks {
    static func main() throws {
        var first = NotebookPageDocument(id: "one", notebookID: "book")
        first.textObjects = [NotebookTextObject(text: "Editable notebook PDF – page one", bold: true)]
        var second = NotebookPageDocument(id: "two", notebookID: "book")
        second.paper.size = "A5"; second.paper.template = .grid; second.paper.landscape = true
        second.textObjects = [NotebookTextObject(text: "Second page", underline: true)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SATHI-notebook-pdf-check.pdf")
        _ = try NotebookPDFExport.export(title: "Notebook check", sources: [.draft(first), .draft(second)], destination: url)
        guard let pdf = PDFDocument(url: url) else { fatalError("Unreadable PDF") }
        assert(pdf.pageCount == 2)
        assert(pdf.page(at: 0)!.bounds(for: .mediaBox).size == CGSize(width: 595, height: 842))
        assert(pdf.page(at: 1)!.bounds(for: .mediaBox).size == CGSize(width: 595, height: 420))
        assert(pdf.string?.contains("Second page") == true)
        assert(NotebookPDFExport.thumbnail(first) != nil)
        print("Native PDF checks passed: ordered pages, A4/A5 landscape dimensions, selectable text and thumbnail rendering.")
    }
}
