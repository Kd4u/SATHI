import SwiftUI
import Combine
import PencilKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

nonisolated enum NotebookTool: String, CaseIterable { case pen, marker, eraser, selection, text }

@MainActor final class NotebookPageModel: ObservableObject {
    @Published var document: NotebookPageDocument
    @Published var error = ""
    @Published var selectedTextID: String?
    @Published var selectedCanvasID: String?
    @Published var inkColor = NotebookColor.ink
    @Published var inkWidth = 2.0
    @Published var inkOpacity = 1.0
    @Published var saveState = "Saved locally"
    var undoInk: (() -> Void)?
    var redoInk: (() -> Void)?
    var flushInk: (() -> Void)?
    private let store: NotebookStore
    private let bookID: String
    private var revision: String?
    private var persisted: NotebookPageDocument
    private var pendingSave: Task<Void, Never>?
    private var undoText: [NotebookPageDocument] = []
    private var redoText: [NotebookPageDocument] = []
    var onPersist: ((String, String) -> Void)?
    var onTextOverflow: ((NotebookTextObject, String) -> Void)?
    var undoTyped: (() -> Bool)?
    var redoTyped: (() -> Bool)?
    init(store: NotebookStore, book: NotebookManifest, pageID: String) {
        self.store = store; bookID = book.id
        let fallback = NotebookPageDocument(id: pageID, notebookID: book.id, paper: book.paper)
        let loaded = try? store.page(pageID)
        document = loaded ?? fallback; persisted = loaded ?? fallback
        revision = store.revision(pageID)
        if revision != nil && loaded == nil { error = "This page has not downloaded yet. Use Sync before editing." }
    }
    func drawingChanged(_ drawing: PKDrawing) {
        guard error.isEmpty else { return }
        document.drawing = drawing.strokes.isEmpty ? Data() : drawing.dataRepresentation()
        scheduleSave()
    }
    func replaceText(_ value: NotebookTextObject) {
        guard error.isEmpty, let index = document.textObjects.firstIndex(where: { $0.id == value.id }) else { return }
        var item = value
        let fit = NotebookPDFExport.fitText(item, height: max(48, document.paper.height - item.y - document.paper.safeMargin))
        item.text = fit.0; item.height = fit.2
        document.textObjects[index] = item
        if !fit.1.isEmpty {
            flush()
            var continuation = value; continuation.text = fit.1
            onTextOverflow?(continuation, document.id)
        } else { scheduleSave() }
    }
    func edited() {
        guard error.isEmpty else { return }
        scheduleSave()
    }
    func checkpoint() { undoText.append(document); if undoText.count > 30 { undoText.removeFirst() }; redoText.removeAll() }
    func undo(tool: NotebookTool) {
        if selectedCanvasID == nil && tool != .text, let undoInk { undoInk(); return }
        if selectedCanvasID == nil && tool == .text, undoTyped?() == true { return }
        guard let old = undoText.popLast() else { return }; redoText.append(document); document = old; scheduleSave()
    }
    func redo(tool: NotebookTool) {
        if selectedCanvasID == nil && tool != .text, let redoInk { redoInk(); return }
        if selectedCanvasID == nil && tool == .text, redoTyped?() == true { return }
        guard let next = redoText.popLast() else { return }; undoText.append(document); document = next; scheduleSave()
    }
    func addText(at point: CGPoint) {
        checkpoint()
        let paper = document.paper
        var text = NotebookTextObject(x: min(max(paper.safeMargin, point.x), paper.width - 150), y: min(max(paper.safeMargin, point.y), paper.height - 80), width: paper.width - 2 * paper.safeMargin, height: 160)
        text.color = paper.background.isDark ? .white : .ink
        document.textObjects.append(text); selectedTextID = text.id
    }
    func refreshIfUnmodified() {
        flushInk?()
        guard document == persisted, store.revision(document.id) != revision,
              let next = try? store.page(document.id) else { return }
        document = next; persisted = next; revision = store.revision(next.id); error = ""
    }
    func flush() {
        flushInk?(); pendingSave?.cancel(); pendingSave = nil
        guard error.isEmpty, document != persisted else { return }
        save()
    }
    private func scheduleSave() {
        pendingSave?.cancel(); saveState = "Saving on this device…"
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            self?.save()
        }
    }
    private func save() {
        guard error.isEmpty, document != persisted else { return }
        do {
            let oldID = document.id
            let saved = try store.savePage(document, bookID: bookID, expectedRevision: revision)
            document = saved; persisted = saved; revision = store.revision(saved.id)
            saveState = "Saved locally"
            if revision != nil { onPersist?(oldID, saved.id) }
        } catch { self.error = error.localizedDescription; saveState = "Save needs attention" }
    }
}

#if os(iOS)
struct NotebookPencilCanvas: UIViewRepresentable {
    @ObservedObject var model: NotebookPageModel
    let tool: NotebookTool
    let fingerDrawing: Bool
    let focused: Bool
    let onEndOfPage: () -> Void
    let onActivate: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = NotebookCanvasView(frame: .zero); canvas.isOpaque = false; canvas.backgroundColor = .clear
        canvas.isScrollEnabled = false; canvas.bounces = false; canvas.delegate = context.coordinator
        if !model.document.drawing.isEmpty, let drawing = try? PKDrawing(data: model.document.drawing) { canvas.drawing = drawing }
        context.coordinator.canvas = canvas
        canvas.onWindow = { [weak coordinator = context.coordinator] in coordinator?.attach() }
        model.flushInk = { [weak coordinator = context.coordinator] in coordinator?.flush() }
        model.undoInk = { [weak canvas] in canvas?.undoManager?.undo() }
        model.redoInk = { [weak canvas] in canvas?.undoManager?.redo() }
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.drawingPolicy = (fingerDrawing || tool == .eraser) ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = tool != .text
        let signature = tool.rawValue + String(model.document.paper.background.isDark) + String(describing: model.inkColor) + String(model.inkWidth) + String(model.inkOpacity)
        if signature != context.coordinator.toolSignature || (tool == .eraser && !(canvas.tool is PKEraserTool)) {
            context.coordinator.toolSignature = signature
            let ink: UIColor = (model.document.paper.background.isDark && model.inkColor == .ink ? UIColor.white : UIColor(model.inkColor.color)).withAlphaComponent(model.inkOpacity)
            switch tool {
            case .pen: canvas.tool = PKInkingTool(.pen, color: ink, width: model.inkWidth)
            case .marker: canvas.tool = PKInkingTool(.marker, color: ink.withAlphaComponent(min(0.6, model.inkOpacity)), width: max(8, model.inkWidth * 5))
            case .eraser: canvas.tool = PKEraserTool(.vector)
            case .selection: canvas.tool = PKLassoTool()
            case .text: break
            }
        }
        if focused && (tool == .pen || tool == .marker) && canvas.window != nil {
            context.coordinator.picker.addObserver(canvas)
            context.coordinator.picker.setVisible(true, forFirstResponder: canvas)
            if !canvas.isFirstResponder { canvas.becomeFirstResponder() }
        } else { context.coordinator.picker.setVisible(false, forFirstResponder: canvas) }
        // Only a genuine external change replaces canvas ink; a text keystroke does not.
        if context.coordinator.lastData != model.document.drawing && !context.coordinator.isDrawing {
            if model.document.drawing.isEmpty { canvas.drawing = PKDrawing() }
            else if let drawing = try? PKDrawing(data: model.document.drawing) { canvas.drawing = drawing }
            context.coordinator.lastData = model.document.drawing
        }
    }
    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.flush(); coordinator.pending?.cancel(); coordinator.picker.removeObserver(canvas)
        coordinator.parent.model.flushInk = nil; coordinator.parent.model.undoInk = nil; coordinator.parent.model.redoInk = nil
    }
    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: NotebookPencilCanvas
        weak var canvas: PKCanvasView?
        let picker = PKToolPicker()
        var pending: Task<Void, Never>?
        var isDrawing = false
        var strokeCount = 0
        var needsContinuation = false
        var lastData: Data
        var toolSignature = ""
        init(_ parent: NotebookPencilCanvas) { self.parent = parent; lastData = parent.model.document.drawing }
        func attach() {
            guard let canvas, parent.focused, parent.tool == .pen || parent.tool == .marker else { return }
            picker.addObserver(canvas); picker.setVisible(true, forFirstResponder: canvas); canvas.becomeFirstResponder()
        }
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { isDrawing = true; strokeCount = canvasView.drawing.strokes.count; parent.onActivate() }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { isDrawing = false; needsContinuation = true }
        func continueIfNeeded() {
            guard needsContinuation, let canvas, canvas.tool is PKInkingTool, canvas.drawing.strokes.count > strokeCount,
                  let point = canvas.drawing.strokes.last?.path.last,
                  point.location.y > parent.model.document.paper.height - parent.model.document.paper.safeMargin else { return }
            needsContinuation = false; parent.onEndOfPage()
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            pending?.cancel()
            pending = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                self?.flush(); self?.continueIfNeeded()
            }
        }
        func flush() {
            guard let canvas else { return }
            let data = canvas.drawing.strokes.isEmpty ? Data() : canvas.drawing.dataRepresentation()
            guard data != lastData else { return }
            lastData = data; parent.model.drawingChanged(canvas.drawing)
        }
    }
}

/// Finger ink and one-finger scrolling must not compete on the same paper surface.
private final class NotebookCanvasView: PKCanvasView {
    var onWindow: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { onWindow?() } }
}

struct NotebookPanPolicy: UIViewRepresentable {
    let twoFingers: Bool
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            var parent = view?.superview
            while let value = parent {
                if let scroll = value as? UIScrollView, !(scroll is PKCanvasView) { scroll.panGestureRecognizer.minimumNumberOfTouches = twoFingers ? 2 : 1; break }
                parent = value.superview
            }
        }
    }
}
#endif

struct NotebookInkView: View {
    let data: Data
    let paper: PaperConfiguration
    @State private var image: Image?
    var body: some View {
        Group { if let image { image.resizable().frame(width: paper.width, height: paper.height) } }
            .task(id: data) {
                guard !data.isEmpty, let drawing = try? PKDrawing(data: data) else { image = nil; return }
                #if os(iOS)
                image = Image(uiImage: drawing.image(from: CGRect(x: 0, y: 0, width: paper.width, height: paper.height), scale: 1))
                #else
                image = Image(nsImage: drawing.image(from: CGRect(x: 0, y: 0, width: paper.width, height: paper.height), scale: 1))
                #endif
            }.allowsHitTesting(false)
    }
}

struct NotebookStaticPage: View {
    let document: NotebookPageDocument
    var body: some View {
        ZStack(alignment: .topLeading) {
            PaperBackgroundView(paper: document.paper)
            NotebookInkView(data: document.drawing, paper: document.paper)
            ForEach(document.textObjects) { item in
                Text(item.text).font(item.notebookFont).underline(item.underline)
                    .foregroundStyle(item.color.color).multilineTextAlignment(item.alignment == "center" ? .center : item.alignment == "right" ? .trailing : .leading)
                    .frame(width: item.width, height: item.height, alignment: .topLeading).offset(x: item.x, y: item.y)
            }
        }.frame(width: document.paper.width, height: document.paper.height).clipped()
    }
}

extension NotebookTextObject {
    var notebookFont: Font { let base = Font.system(size: fontSize, weight: bold ? .bold : .regular); return italic ? base.italic() : base }
}
