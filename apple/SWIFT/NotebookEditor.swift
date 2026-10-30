import SwiftUI
import Combine

@MainActor final class NotebookSession: ObservableObject {
    @Published var focusedPage = 0
    @Published var zoom = 1.0
    private final class WeakPage { weak var value: NotebookPageModel?; init(_ value: NotebookPageModel) { self.value = value } }
    private var visible: [String: WeakPage] = [:]
    func register(_ value: NotebookPageModel) { visible[value.document.id] = WeakPage(value) }
    func flush() { for entry in visible.values { entry.value?.flush() }; visible = visible.filter { $0.value.value != nil } }
}
private struct NotebookPageOffsets: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, next in next }) }
}

struct NotebookEditorView: View {
    @ObservedObject var store: NotebookStore
    let bookID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var session = NotebookSession()
    @State private var draftID = UUID().uuidString
    @State private var active: NotebookPageModel?
    @State private var tool: NotebookTool = {
        #if os(macOS)
        .text
        #else
        .pen
        #endif
    }()
    @State private var fingerDrawing = {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }()
    @State private var expanded = true
    @State private var proMode = false
    @State private var showBookSettings = false
    @State private var showPaper = false
    @State private var showPages = false
    @State private var showExport = false
    @State private var exporting = false
    @State private var exportURL: URL?
    @State private var exportChoice = "Current page"
    @State private var exportRange = "1"
    @State private var error = ""
    @State private var toolbarOffset = CGSize.zero
    @State private var dragOrigin = CGSize.zero
    @State private var pinchOrigin: Double?
    private var book: NotebookManifest? { store.book(bookID) }

    var body: some View {
        GeometryReader { geometry in
            if let book {
                let ids = book.pageIDs + [draftID]
                let baseWidth = min(900.0, max(280.0, geometry.size.width - 24))
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(spacing: 24) {
                            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                                let size = book.pageSizes[id] ?? NotebookPageSize(width: book.paper.width, height: book.paper.height)
                                let scale = baseWidth / size.width * session.zoom
                                Group {
                                    if abs(index - session.focusedPage) <= 1 {
                                        NotebookLivePage(store: store, session: session, book: book, pageID: id, tool: tool, fingerDrawing: fingerDrawing, focused: index == session.focusedPage, proMode: proMode,
                                            onFocus: { active = $0; session.focusedPage = index },
                                            onSave: { old, _ in if old == draftID && store.revision(old) != nil { draftID = UUID().uuidString } },
                                            onOverflow: { item, after in continueText(item, after: after, proxy: proxy) },
                                            onContinue: {
                                                active?.flush()
                                                let nextIDs = (store.book(bookID)?.pageIDs ?? []) + [draftID]
                                                let next = min(index + 1, nextIDs.count - 1)
                                                session.focusedPage = next
                                                Task { await Task.yield(); proxy.scrollTo(nextIDs[next], anchor: .top) }
                                            })
                                    } else {
                                        PaperBackgroundView(paper: book.paper).frame(width: size.width, height: size.height)
                                    }
                                }
                                .frame(width: size.width, height: size.height)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                                .background(GeometryReader { pageGeometry in
                                    Color.clear.preference(key: NotebookPageOffsets.self, value: [index: pageGeometry.frame(in: .named("notebookViewport")).minY])
                                })
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(alignment: .bottomTrailing) { Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary).padding(6).background(.regularMaterial, in: Capsule()).padding(8).allowsHitTesting(false) }
                                .id(id)
                            }
                        }
                        .padding(12)
                        .frame(minWidth: geometry.size.width, alignment: .center)
                        #if os(iOS)
                        .background(NotebookPanPolicy(twoFingers: (fingerDrawing || tool == .eraser || proMode) && tool != .text))
                        #endif
                    }
                    .coordinateSpace(name: "notebookViewport")
                    .background(Color.primary.opacity(0.06))
                    .onPreferenceChange(NotebookPageOffsets.self) { positions in
                        if let nearest = positions.min(by: { abs($0.value) < abs($1.value) }), nearest.key != session.focusedPage {
                            session.focusedPage = nearest.key
                            store.remember(bookID: bookID, page: nearest.key, zoom: session.zoom)
                        }
                    }
                    .simultaneousGesture(MagnifyGesture().onChanged { value in
                        if pinchOrigin == nil { pinchOrigin = session.zoom }
                        session.zoom = min(3, max(0.5, (pinchOrigin ?? 1) * value.magnification))
                    }.onEnded { _ in pinchOrigin = nil; store.remember(bookID: bookID, page: session.focusedPage, zoom: session.zoom) })
                    .safeAreaInset(edge: .top) { toolbar(book: book, ids: ids, proxy: proxy).offset(toolbarOffset) }
                    .sheet(isPresented: $showPages) { pagesSheet(book, proxy: proxy) }
                    .task {
                        let saved = store.position(bookID: bookID)
                        session.zoom = saved.1; session.focusedPage = min(saved.0, ids.count - 1)
                        await Task.yield(); proxy.scrollTo(ids[session.focusedPage], anchor: .top)
                    }
                }
            } else { ContentUnavailableView("Notebook unavailable", systemImage: "book.closed") }
        }
        .sheet(isPresented: $showBookSettings) { if let book { NotebookBookSettings(store: store, book: book) } }
        .sheet(isPresented: $showPaper) {
            NavigationStack {
                if let active {
                    NotebookPaperSettings(paper: Binding(get: { active.document.paper }, set: { value in
                        active.document.paper = value; active.edited()
                    }))
                    .navigationTitle("Paper")
                    .toolbar { Button("Done") { active.flush(); showPaper = false } }
                    .onDisappear { if var value = store.book(bookID) { value.paper = active.document.paper; try? store.saveBook(value) } }
                } else { ProgressView("Opening page…") }
            }.frame(minWidth: 300, minHeight: 450)
        }
        .sheet(isPresented: $showExport) { exportSheet }
        .onChange(of: phase) { _, value in if value != .active { session.flush() } }
        .onDisappear { session.flush(); store.remember(bookID: bookID, page: session.focusedPage, zoom: session.zoom) }
    }

    private func toolbar(book: NotebookManifest, ids: [String], proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { session.flush(); dismiss() } label: { Image(systemName: "books.vertical") }.accessibilityLabel("Notebook library")
                Button { showBookSettings = true } label: { Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1) }
                Spacer(minLength: 2)
                Button("\(session.focusedPage + 1) / \(max(book.pageIDs.count, session.focusedPage + 1))") { session.flush(); showPages = true }.font(.caption.monospacedDigit()).accessibilityLabel("Page navigator")
                Button(proMode ? "Done · normal mode" : "Pro canvas", systemImage: proMode ? "checkmark" : "square.stack.3d.up") { session.flush(); proMode.toggle(); if proMode { tool = .selection } }.font(.caption)
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }.accessibilityLabel("Collapse writing tools")
                Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(.secondary)
                    .gesture(DragGesture().onChanged { value in toolbarOffset = CGSize(width: min(40, max(-40, dragOrigin.width + value.translation.width)), height: min(160, max(0, dragOrigin.height + value.translation.height))) }.onEnded { _ in dragOrigin = toolbarOffset })
            }
            if expanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        #if os(iOS)
                        toolButton(.pen, "pencil.tip", "Pen")
                        toolButton(.marker, "highlighter", "Highlighter")
                        toolButton(.eraser, "eraser", "Eraser")
                        toolButton(.selection, "lasso", "Selection")
                        #endif
                        toolButton(.text, "textformat", "Text box")
                        Button { active?.flush(); showPaper = true } label: { Image(systemName: "square.grid.3x3") }.accessibilityLabel("Paper template")
                        Button { active?.undo(tool: tool) } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel("Undo")
                        Button { active?.redo(tool: tool) } label: { Image(systemName: "arrow.uturn.forward") }.accessibilityLabel("Redo")
                        Button { session.flush(); exportURL = nil; showExport = true } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Export PDF")
                        Menu {
                            Button("Zoom out") { session.zoom = max(0.5, session.zoom - 0.25) }
                            Button("Fit width") { session.zoom = 1 }
                            Button("Zoom in") { session.zoom = min(3, session.zoom + 0.25) }
                            #if os(iOS)
                            Toggle("Draw with finger", isOn: $fingerDrawing)
                            #endif
                        } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Zoom and input settings")
                    }.font(.system(size: 18)).padding(.vertical, 5)
                }
                if tool == .text, let active { NotebookTextFormatting(model: active) }
                if proMode, let active { NotebookProTools(model: active) }
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            if let active, !active.error.isEmpty { Text(active.error).font(.caption).foregroundStyle(.red) }
        }
        .buttonStyle(.plain).tint(.accentColor).padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20)).padding(.horizontal, 10).padding(.top, 4)
    }
    private func toolButton(_ value: NotebookTool, _ symbol: String, _ title: String) -> some View {
        Button { tool = value; active?.selectedCanvasID = nil } label: { Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 28, height: 28).background(tool == value ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7)) }.accessibilityLabel(title)
    }
    private func pagesSheet(_ book: NotebookManifest, proxy: ScrollViewProxy) -> some View {
        NavigationStack {
            List {
                ForEach(Array(book.pageIDs.enumerated()), id: \.element) { index, id in
                    Button { showPages = false; session.focusedPage = index; proxy.scrollTo(id, anchor: .top) } label: {
                        HStack { NotebookThumbnail(store: store, id: id).frame(width: 48, height: 68); Text("Page \(index + 1)"); Spacer() }
                    }
                    .overlay(alignment: .trailing) {
                        Menu {
                            Button("Insert page after") { session.flush(); try? store.insertBlankPage(bookID: bookID, after: index) }
                            Button("Duplicate") { session.flush(); try? store.duplicatePage(id, bookID: bookID) }
                            Button("Delete page", role: .destructive) { session.flush(); active = nil; try? store.removePage(id, bookID: bookID) }
                        } label: { Label("Edit", systemImage: "ellipsis.circle") }.padding(.trailing, 8)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { session.flush(); active = nil; try? store.removePage(id, bookID: bookID) } }
                    .contextMenu {
                        Button("Insert page after") { session.flush(); try? store.insertBlankPage(bookID: bookID, after: index) }
                        Button("Duplicate page") { do { try store.duplicatePage(id, bookID: bookID) } catch { self.error = error.localizedDescription } }
                        Button("Move up") { movePage(index, to: index - 1) }.disabled(index == 0)
                        Button("Move down") { movePage(index, to: index + 1) }.disabled(index == book.pageIDs.count - 1)
                        Button("Delete page", role: .destructive) { do { try store.removePage(id, bookID: bookID) } catch { self.error = error.localizedDescription } }
                    }
                }.onDelete { offsets in
                    session.flush(); active = nil
                    for index in offsets { do { try store.removePage(book.pageIDs[index], bookID: bookID) } catch { self.error = error.localizedDescription } }
                }.onMove { offsets, destination in
                    var next = book; next.pageIDs.move(fromOffsets: offsets, toOffset: destination); try? store.saveBook(next)
                }
                Button("Insert blank page after current", systemImage: "plus.rectangle.on.rectangle") { session.flush(); try? store.insertBlankPage(bookID: bookID, after: session.focusedPage) }
                Button("New page", systemImage: "plus") { showPages = false; session.focusedPage = book.pageIDs.count; proxy.scrollTo(draftID, anchor: .top) }
            }.navigationTitle("Pages")
                .toolbar {
                    #if os(iOS)
                    EditButton()
                    #endif
                    Button("Done") { showPages = false }
                }
        }.frame(minWidth: 300, minHeight: 400)
    }
    private func movePage(_ source: Int, to target: Int) {
        guard var book = book else { return }; book.pageIDs = NotebookPageOrder.moving(book.pageIDs, from: source, to: target); try? store.saveBook(book)
    }
    private var exportSheet: some View {
        NavigationStack {
            Form {
                Picker("Pages", selection: $exportChoice) { ForEach(["Current page", "Selected pages", "Entire notebook"], id: \.self) { Text($0) } }
                if exportChoice == "Selected pages" { TextField("For example 1-3, 5", text: $exportRange) }
                if exporting { ProgressView("Creating PDF locally…") }
                else { Button("Generate PDF") { export() } }
                if let exportURL { ShareLink(item: exportURL) { Label("Share PDF", systemImage: "square.and.arrow.up") } }
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            }.navigationTitle("Export notebook").toolbar { Button("Done") { showExport = false } }
        }.frame(minWidth: 300, minHeight: 320)
    }
    private func continueText(_ value: NotebookTextObject, after pageID: String, proxy: ScrollViewProxy) {
        guard let original = book else { return }
        var remaining = value.text
        var added: [String] = []
        do {
            while !remaining.isEmpty {
                var doc = NotebookPageDocument(id: UUID().uuidString, notebookID: bookID, paper: original.paper)
                var item = value; item.id = UUID().uuidString; item.x = doc.paper.safeMargin; item.y = doc.paper.safeMargin
                item.width = doc.paper.width - 2 * doc.paper.safeMargin; item.text = remaining
                let fit = NotebookPDFExport.fitText(item, height: doc.paper.height - 2 * doc.paper.safeMargin)
                item.text = fit.0; item.height = fit.2; doc.textObjects = [item]
                try store.savePage(doc, bookID: bookID, expectedRevision: nil)
                added.append(doc.id); remaining = fit.1
            }
            if var current = store.book(bookID), let position = current.pageIDs.firstIndex(of: pageID) {
                current.pageIDs.removeAll { added.contains($0) }; current.pageIDs.insert(contentsOf: added, at: position + 1)
                try store.saveBook(current)
                session.focusedPage = position + added.count
                if let last = added.last { Task { await Task.yield(); proxy.scrollTo(last, anchor: .top) } }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func export() {
        guard let book, let study = store.study else { return }
        session.flush(); exporting = true; error = ""
        do {
            let sources: [NotebookPDFSource]
            if exportChoice == "Current page", let active { sources = [.draft(active.document)] }
            else {
                let indices = exportChoice == "Entire notebook" ? Array(book.pageIDs.indices) : try NotebookPageOrder.selection(exportRange, count: book.pageIDs.count)
                sources = try indices.map { .file(try study.assetURL(book.pageIDs[$0])) }
            }
            let title = book.title
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("SATHI-Notebook-" + UUID().uuidString + ".pdf")
            Task {
                do { exportURL = try await Task.detached(priority: .userInitiated) { try NotebookPDFExport.export(title: title, sources: sources, destination: destination) }.value }
                catch { self.error = error.localizedDescription }
                exporting = false
            }
        } catch { self.error = error.localizedDescription; exporting = false }
    }
}

private struct NotebookLivePage: View {
    @ObservedObject var store: NotebookStore
    @ObservedObject var session: NotebookSession
    @StateObject private var model: NotebookPageModel
    let pageID: String
    let tool: NotebookTool
    let fingerDrawing: Bool
    let focused: Bool
    let proMode: Bool
    let onFocus: (NotebookPageModel) -> Void
    let onSave: (String, String) -> Void
    let onContinue: () -> Void
    let onOverflow: (NotebookTextObject, String) -> Void
    init(store: NotebookStore, session: NotebookSession, book: NotebookManifest, pageID: String, tool: NotebookTool, fingerDrawing: Bool, focused: Bool, proMode: Bool, onFocus: @escaping (NotebookPageModel) -> Void, onSave: @escaping (String, String) -> Void, onOverflow: @escaping (NotebookTextObject, String) -> Void, onContinue: @escaping () -> Void) {
        self.store = store; self.session = session; self.pageID = pageID; self.tool = tool; self.fingerDrawing = fingerDrawing; self.focused = focused; self.proMode = proMode; self.onFocus = onFocus; self.onSave = onSave; self.onOverflow = onOverflow; self.onContinue = onContinue
        _model = StateObject(wrappedValue: NotebookPageModel(store: store, book: book, pageID: pageID))
    }
    var body: some View {
        let paper = model.document.paper
        ZStack(alignment: .topLeading) {
            PaperBackgroundView(paper: paper)
            #if os(iOS)
            NotebookPencilCanvas(model: model, tool: tool, fingerDrawing: fingerDrawing, focused: focused, onEndOfPage: { model.flush(); onContinue() }, onActivate: { onFocus(model) })
            #else
            NotebookInkView(data: model.document.drawing, paper: paper)
            #endif
            if tool == .text {
                Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { onFocus(model); model.addText(at: $0.location) })
            }
            NotebookProLayer(model: model, editing: proMode, onActivate: { onFocus(model) })
            ForEach(model.document.textObjects) { item in NotebookTextBox(model: model, id: item.id, editing: tool == .text, onActivate: { onFocus(model) }) }
        }
        .frame(width: paper.width, height: paper.height).clipped()
        .onAppear {
            session.register(model); model.onPersist = onSave; model.onTextOverflow = onOverflow
            if focused { activate() }
        }
        .onChange(of: focused) { _, value in if value { activate() } }
        .onChange(of: store.revision(pageID)) { _, _ in model.refreshIfUnmodified() }
        .onChange(of: tool) { _, value in if focused && value == .text { activate() } }
        .onDisappear { model.flush(); model.onPersist = nil; model.onTextOverflow = nil }
    }
    private func activate() {
        onFocus(model)
        if tool == .text {
            if model.document.textObjects.isEmpty { model.addText(at: CGPoint(x: model.document.paper.safeMargin, y: model.document.paper.safeMargin)) }
            model.selectedTextID = model.document.textObjects.last?.id
        }
    }
}

struct NotebookTextFormatting: View {
    @ObservedObject var model: NotebookPageModel
    var body: some View {
        if let id = model.selectedTextID, let index = model.document.textObjects.firstIndex(where: { $0.id == id }) {
            HStack(spacing: 16) {
                Button { model.checkpoint(); model.document.textObjects[index].bold.toggle(); model.edited() } label: { Image(systemName: "bold") }
                Button { model.checkpoint(); model.document.textObjects[index].italic.toggle(); model.edited() } label: { Image(systemName: "italic") }
                Button { model.checkpoint(); model.document.textObjects[index].underline.toggle(); model.edited() } label: { Image(systemName: "underline") }
                Menu {
                    ForEach([14.0, 18, 22, 28, 36], id: \.self) { size in Button("\(Int(size)) pt") { model.checkpoint(); model.document.textObjects[index].fontSize = size; model.edited() } }
                } label: { Image(systemName: "textformat.size") }
                Menu {
                    ForEach(["left", "center", "right"], id: \.self) { alignment in Button(alignment.capitalized) { model.checkpoint(); model.document.textObjects[index].alignment = alignment; model.edited() } }
                } label: { Image(systemName: "text.alignleft") }
                ColorPicker("Text colour", selection: Binding(get: { model.document.textObjects[index].color.color }, set: { model.document.textObjects[index].color = .from($0); model.edited() }), supportsOpacity: false).labelsHidden().frame(width: 28)
                Button(role: .destructive) { model.checkpoint(); model.document.textObjects.remove(at: index); model.selectedTextID = nil; model.edited() } label: { Image(systemName: "trash") }
            }.font(.system(size: 16)).padding(.top, 4)
        } else { Text("Tap anywhere on the paper to add editable text.").font(.caption).foregroundStyle(.secondary) }
    }
}

struct NotebookThumbnail: View {
    @ObservedObject var store: NotebookStore
    let id: String
    @State private var image: CGImage?
    var body: some View {
        Group { if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() } else { Rectangle().fill(.white).overlay(Image(systemName: "doc").foregroundStyle(.secondary)) } }
            .task(id: store.revision(id)) {
                guard let page = try? store.page(id) else { return }
                let result = await Task.detached(priority: .utility) { NotebookPDFExport.thumbnail(page) }.value
                if !Task.isCancelled { image = result }
            }
    }
}
