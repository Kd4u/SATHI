import Foundation
import Combine
import SwiftData
import CryptoKit
import PencilKit

@Model final class NotebookIndex {
    @Attribute(.unique) var id: String
    var title: String
    var subject: String
    var folder: String
    var modifiedAt: Date
    var deletedAt: Date?
    var manifest: Data
    var lastOpenedAt: Date?
    var lastPage: Int
    var zoom: Double
    init(book: NotebookManifest, data: Data) {
        id = book.id; title = book.title; subject = book.subject; folder = book.folder
        modifiedAt = book.modifiedAt; deletedAt = book.deletedAt; manifest = data; lastPage = 0; zoom = 1; lastOpenedAt = nil
    }
}

@MainActor final class NotebookStore: ObservableObject {
    @Published private(set) var books: [NotebookManifest] = []
    @Published var message = ""
    private(set) var study: StudyStore?
    private var container: ModelContainer?
    private var context: ModelContext?
    private var subscription: AnyCancellable?
    private var reconciling = false
    private let pages = NSCache<NSString, PageBox>()
    private final class PageBox { let page: NotebookPageDocument; init(_ page: NotebookPageDocument) { self.page = page } }

    func configure(study: StudyStore) throws {
        guard self.study !== study || context == nil else { return }
        self.study = study
        let directory = try study.notebookDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration("NotebookIndex", url: directory.appendingPathComponent("index.store"), cloudKitDatabase: .none)
        container = try ModelContainer(for: NotebookIndex.self, configurations: config)
        context = ModelContext(container!)
        pages.countLimit = 7; pages.totalCostLimit = 24 * 1024 * 1024
        try reload()
        try migrateLegacyNotes()
        subscription = study.$assets.map { values in values.map { $0.id + $0.revision }.joined() }
            .removeDuplicates().debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in try? self?.reload() }
    }
    private func indexes() throws -> [NotebookIndex] { try context?.fetch(FetchDescriptor<NotebookIndex>()) ?? [] }
    func reload() throws {
        guard !reconciling, let study, let context else { return }
        reconciling = true; defer { reconciling = false }
        var result: [NotebookManifest] = []
        let existing = try indexes()
        for asset in study.assets where asset.kind == "notebook" {
            guard var book = try? JSONDecoder().decode(NotebookManifest.self, from: study.assetData(asset.id)) else { continue }
            book.id = asset.id
            if asset.title.contains("local conflict copy") { book.title = asset.title }
            result.append(book)
            let data = try JSONEncoder().encode(book)
            if let row = existing.first(where: { $0.id == book.id }) {
                row.title = book.title; row.subject = book.subject; row.folder = book.folder
                row.modifiedAt = book.modifiedAt; row.deletedAt = book.deletedAt; row.manifest = data
            } else { context.insert(NotebookIndex(book: book, data: data)) }
        }
        try context.save()
        books = result.sorted { $0.modifiedAt > $1.modifiedAt }
        // Conflicting page versions created by the shared sync layer remain discoverable.
        let linked = Set(result.flatMap { $0.pageIDs + $0.removedPageIDs })
        for asset in study.assets where asset.kind == "notebookPage" && !linked.contains(asset.id) {
            guard let page = try? JSONDecoder().decode(NotebookPageDocument.self, from: study.assetData(asset.id)),
                  let book = books.first(where: { $0.id == page.notebookID && $0.deletedAt == nil }) else { continue }
            var next = book; next.pageIDs.append(asset.id); try saveBook(next)
        }
    }
    func book(_ id: String) -> NotebookManifest? { books.first { $0.id == id } }
    func create(title: String, subject: String = "", semesterID: String = "") throws -> NotebookManifest {
        var book = NotebookManifest(); book.title = title; book.subject = subject; book.semesterID = semesterID
        try saveBook(book); return book
    }
    func saveBook(_ value: NotebookManifest) throws {
        guard let study, let context else { throw NotebookFailure.missingPage }
        var book = value; book.modifiedAt = Date()
        try study.saveAsset(id: book.id, kind: "notebook", title: book.title, subject: book.subject, semesterID: book.semesterID, data: JSONEncoder().encode(book))
        books.removeAll { $0.id == book.id }; books.append(book); books.sort { $0.modifiedAt > $1.modifiedAt }
        let data = try JSONEncoder().encode(book)
        if let row = try indexes().first(where: { $0.id == book.id }) {
            row.title = book.title; row.subject = book.subject; row.folder = book.folder; row.manifest = data; row.modifiedAt = book.modifiedAt; row.deletedAt = book.deletedAt
        } else { context.insert(NotebookIndex(book: book, data: data)) }
        try context.save()
    }
    func page(_ id: String) throws -> NotebookPageDocument {
        guard let study else { throw NotebookFailure.missingPage }
        let revision = study.assets.first(where: { $0.id == id })?.revision ?? ""
        let key = (id + revision) as NSString
        if let cached = pages.object(forKey: key) { return cached.page }
        var page = try JSONDecoder().decode(NotebookPageDocument.self, from: study.assetData(id)); page.id = id
        pages.setObject(PageBox(page), forKey: key, cost: page.drawing.count + page.textObjects.reduce(0) { $0 + $1.text.utf8.count })
        return page
    }
    func revision(_ id: String) -> String? { study?.assets.first(where: { $0.id == id })?.revision }
    @discardableResult func savePage(_ value: NotebookPageDocument, bookID: String, expectedRevision: String?) throws -> NotebookPageDocument {
        guard let study, var book = book(bookID) else { throw NotebookFailure.missingPage }
        var page = value
        let current = revision(page.id)
        let fork = (current != nil && current != expectedRevision) || page.notebookID != bookID
        if fork { page.id = UUID().uuidString; message = "Concurrent changes kept as a separate page." }
        page.notebookID = bookID; page.modifiedAt = Date()
        if !page.hasContent && current == nil { return page }
        try study.saveAsset(id: page.id, kind: "notebookPage", title: book.title + " · page", subject: book.subject, semesterID: book.semesterID, data: JSONEncoder().encode(page))
        let size = NotebookPageSize(width: page.paper.width, height: page.paper.height)
        let geometryChanged = book.pageSizes[page.id] != size
        book.pageSizes[page.id] = size
        if !book.pageIDs.contains(page.id) {
            if value.notebookID != bookID, let index = book.pageIDs.firstIndex(of: value.id) { book.pageIDs[index] = page.id }
            else { book.pageIDs.append(page.id) }
            try saveBook(book)
        } else if geometryChanged { try saveBook(book) }
        if let revision = revision(page.id) { pages.setObject(PageBox(page), forKey: (page.id + revision) as NSString, cost: page.drawing.count) }
        return page
    }
    func remember(bookID: String, page: Int, zoom: Double) {
        guard let row = try? indexes().first(where: { $0.id == bookID }) else { return }
        row.lastOpenedAt = Date(); row.lastPage = max(0, page); row.zoom = min(3, max(0.5, zoom)); try? context?.save()
    }
    func position(bookID: String) -> (Int, Double) {
        guard let row = try? indexes().first(where: { $0.id == bookID }) else { return (0, 1) }
        return (row.lastPage, row.zoom)
    }
    func lastOpened() -> String? { (try? indexes().sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }.first(where: { $0.deletedAt == nil })?.id) ?? nil }
    func removePage(_ id: String, bookID: String) throws {
        guard var book = book(bookID) else { return }; book.pageIDs.removeAll { $0 == id }; book.removedPageIDs.append(id); try saveBook(book)
    }
    func duplicatePage(_ id: String, bookID: String) throws {
        var copy = try page(id); copy.id = UUID().uuidString; copy.notebookID = bookID
        try savePage(copy, bookID: bookID, expectedRevision: nil)
    }
    func duplicateBook(_ id: String) async throws {
        guard let original = book(id) else { return }
        var copy = original; copy.id = UUID().uuidString; copy.title += " · copy"; copy.pageIDs = []; copy.pageSizes = [:]; copy.deletedAt = nil; copy.importedLegacyIDs = []
        try saveBook(copy)
        for pageID in original.pageIDs {
            var page = try self.page(pageID); page.id = UUID().uuidString; page.notebookID = copy.id
            try savePage(page, bookID: copy.id, expectedRevision: nil); await Task.yield()
        }
    }
    func trash(_ id: String, restore: Bool = false) throws {
        guard var book = book(id) else { return }; book.deletedAt = restore ? nil : Date(); try saveBook(book)
    }
    private func migrateLegacyNotes() throws {
        guard let study else { return }
        let adopted = Set(books.flatMap(\.importedLegacyIDs))
        for asset in study.assets where asset.kind == "note" && !adopted.contains(asset.id) {
            let legacy = try study.note(asset.id)
            let seed = asset.semesterID + "|" + asset.subject
            let digest = SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
            let bookID = "book-" + digest
            var book = self.book(bookID) ?? NotebookManifest(id: bookID, title: asset.subject.isEmpty ? "Quick book" : asset.subject, subject: asset.subject, semesterID: asset.semesterID)
            var page = NotebookPageDocument(id: "page-import-" + asset.id, notebookID: bookID)
            page.drawing = legacy.drawing
            if let drawing = try? PKDrawing(data: legacy.drawing), drawing.strokes.isEmpty { page.drawing = Data() }
            if !legacy.text.isEmpty { page.textObjects = [NotebookTextObject(text: legacy.text, width: page.paper.width - 96, height: 400)] }
            try saveBook(book)
            if page.hasContent { try savePage(page, bookID: bookID, expectedRevision: revision(page.id)) }
            book = self.book(bookID) ?? book; book.importedLegacyIDs.append(asset.id); try saveBook(book)
        }
    }
}
