import SwiftUI

extension Notification.Name {
    static let sathiOpenNotebook = Notification.Name("SATHIOpenNotebook")
    static let sathiNewNotebook = Notification.Name("SATHINewNotebook")
}
private struct NotebookRoute: Identifiable { let id: String }

struct NotebookLibraryView: View {
    @ObservedObject var study: StudyStore
    let subjects: [String]
    var semesterID: String?
    @StateObject private var store = NotebookStore()
    @State private var selected: NotebookRoute?
    @State private var editing: NotebookManifest?
    @State private var create = false
    @State private var search = ""
    @State private var folder = "All notebooks"
    @State private var trash = false
    @State private var opened = false
    @State private var error = ""
    @State private var duplicating = false
    private var term: String { semesterID ?? study.workspace.currentSemesterID }
    private var available: [NotebookManifest] {
        store.books.filter { book in
            (trash ? book.deletedAt != nil : book.deletedAt == nil) && (book.subject.isEmpty || book.semesterID == term)
                && (search.isEmpty || book.title.localizedCaseInsensitiveContains(search) || book.subject.localizedCaseInsensitiveContains(search))
                && (folder == "All notebooks" || book.folder == folder)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextField("Search notebooks", text: $search).textFieldStyle(.roundedBorder)
                Button { create = true } label: { Image(systemName: "plus") }.accessibilityLabel("New notebook")
                Menu {
                    Button("All notebooks") { folder = "All notebooks" }
                    ForEach(Array(Set(store.books.map(\.folder).filter { !$0.isEmpty })).sorted(), id: \.self) { name in Button(name) { folder = name } }
                    Divider(); Button(trash ? "Show notebooks" : "Recently deleted") { trash.toggle() }
                } label: { Image(systemName: "folder") }
            }
            if duplicating { ProgressView("Copying pages…") }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135, maximum: 210), spacing: 20)], spacing: 24) {
                ForEach(available) { book in
                    Button {
                        if trash { do { try store.trash(book.id, restore: true) } catch { self.error = error.localizedDescription } }
                        else { selected = NotebookRoute(id: book.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            NotebookCoverView(book: book)
                            Text(book.title).font(.subheadline.weight(.medium)).lineLimit(2).foregroundStyle(.primary)
                            Text(trash ? "Tap to restore" : "\(book.pageIDs.count) pages").font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                    .contextMenu {
                        if trash { Button("Restore") { try? store.trash(book.id, restore: true) } }
                        else {
                            Button("Cover, title & folder") { editing = book }
                            Button("Duplicate notebook") {
                                duplicating = true
                                Task { do { try await store.duplicateBook(book.id) } catch { self.error = error.localizedDescription }; duplicating = false }
                            }
                            Button("Move to Recently Deleted", role: .destructive) { try? store.trash(book.id) }
                        }
                    }
                }
            }
            if available.isEmpty {
                ContentUnavailableView(trash ? "No deleted notebooks" : "Your notebook shelf", systemImage: "books.vertical", description: Text(trash ? "Deleted notebooks can be restored here." : "Choose a subject or start a personal notebook."))
            }
            Text("Saved on this device. Cloud sync runs hourly or with Sync.").font(.caption).foregroundStyle(.secondary)
        }
        .task {
            do {
                try store.configure(study: study)
                opened = true
            } catch { self.error = error.localizedDescription }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sathiNewNotebook)) { _ in if semesterID == nil { create = true } }
        #if os(iOS)
        .fullScreenCover(item: $selected) { route in NotebookEditorView(store: store, bookID: route.id) }
        #else
        .sheet(item: $selected) { route in NotebookEditorView(store: store, bookID: route.id).frame(minWidth: 650, idealWidth: 1000, minHeight: 600, idealHeight: 800) }
        #endif
        .sheet(isPresented: $create) {
            NotebookCreateView(store: store, subjects: subjects, semesterID: term) { id in
                create = false
                Task { try? await Task.sleep(for: .milliseconds(180)); selected = NotebookRoute(id: id) }
            }
        }
        .sheet(item: $editing) { book in NotebookBookSettings(store: store, book: book) }
    }
    private func openLast() throws {
        if let id = store.lastOpened(), available.contains(where: { $0.id == id }) { selected = NotebookRoute(id: id) }
        else if let first = available.first { selected = NotebookRoute(id: first.id) }
        else { let book = try store.create(title: "Quick book"); selected = NotebookRoute(id: book.id) }
    }
}

struct NotebookCreateView: View {
    @ObservedObject var store: NotebookStore
    let subjects: [String]
    let semesterID: String
    let onCreated: (String) -> Void
    @State private var title = ""
    @State private var subject = ""
    @State private var style = "linen"
    @State private var color = NotebookColor.blue
    @State private var paper = PaperConfiguration()
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    private var sample: NotebookManifest { NotebookManifest(title: title.isEmpty ? (subject.isEmpty ? "My notebook" : subject) : title, subject: subject, coverStyle: style, coverColor: color, paper: paper) }
    var body: some View {
        NavigationStack {
            Form {
                Section { NotebookCoverView(book: sample).frame(height: 180).frame(maxWidth: .infinity) }
                TextField("Notebook title", text: $title)
                Picker("Subject", selection: $subject) {
                    Text("Personal / quick notes").tag("")
                    ForEach(Array(Set(subjects)).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Picker("Cover", selection: $style) { ForEach(["linen", "plain", "leather"], id: \.self) { Text($0.capitalized) } }
                ColorPicker("Cover colour", selection: Binding(get: { color.color }, set: { color = .from($0) }), supportsOpacity: false)
                NavigationLink("Paper style") { NotebookPaperSettings(paper: $paper) }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped).navigationTitle("New notebook")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            do {
                                var book = sample; book.semesterID = subject.isEmpty ? "" : semesterID
                                try store.saveBook(book); onCreated(book.id)
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
        }.frame(minWidth: 300, minHeight: 450)
    }
}

struct NotebookBookSettings: View {
    @ObservedObject var store: NotebookStore
    @State var book: NotebookManifest
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section { NotebookCoverView(book: book).frame(height: 190).frame(maxWidth: .infinity) }
                TextField("Title", text: $book.title)
                TextField("Folder", text: $book.folder)
                Picker("Cover style", selection: $book.coverStyle) { ForEach(["linen", "plain", "leather"], id: \.self) { Text($0.capitalized) } }
                ColorPicker("Cover colour", selection: Binding(get: { book.coverColor.color }, set: { book.coverColor = .from($0) }), supportsOpacity: false)
                NavigationLink("Default paper for new pages") { NotebookPaperSettings(paper: $book.paper) }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped).navigationTitle("Notebook")
                .toolbar { Button("Done") { do { try store.saveBook(book); dismiss() } catch { self.error = error.localizedDescription } } }
        }.frame(minWidth: 300, minHeight: 450)
        .onDisappear { if book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { book.title = "Untitled notebook" }; try? store.saveBook(book) }
    }
}
