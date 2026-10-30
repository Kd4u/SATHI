import SwiftUI
import UniformTypeIdentifiers
import ImageIO
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension NotebookPageModel {
    func addElement(_ element: NotebookCanvasElement) {
        checkpoint(); if document.elements == nil { document.elements = [] }
        var value = element
        value.width = min(document.paper.width, max(20, value.width)); value.height = min(document.paper.height, max(20, value.height))
        value.x = min(document.paper.width - value.width, max(0, value.x)); value.y = min(document.paper.height - value.height, max(0, value.y))
        document.elements?.append(value); selectedCanvasID = value.id; edited()
    }
    func editElement(_ id: String, _ update: (inout NotebookCanvasElement) -> Void) {
        guard var elements = document.elements, let index = elements.firstIndex(where: { $0.id == id }) else { return }
        update(&elements[index]); document.elements = elements; edited()
    }
}

struct NotebookProLayer: View {
    @ObservedObject var model: NotebookPageModel
    let editing: Bool
    let onActivate: () -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.document.elements ?? []) { element in
                NotebookCanvasElementView(model: model, element: element, editing: editing, onActivate: onActivate)
            }
        }.frame(width: model.document.paper.width, height: model.document.paper.height, alignment: .topLeading)
    }
}
private struct NotebookCanvasElementView: View {
    @ObservedObject var model: NotebookPageModel
    let element: NotebookCanvasElement
    let editing: Bool
    let onActivate: () -> Void
    @State private var origin: CGPoint?
    @State private var size: CGSize?
    private var selected: Bool { editing && model.selectedCanvasID == element.id }
    var body: some View {
        content.opacity(element.opacity)
            .frame(width: element.width, height: element.height)
            .overlay { if selected { Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4])) } }
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").padding(7).background(.regularMaterial, in: Circle())
                        .gesture(DragGesture().onChanged { value in
                            if size == nil { model.checkpoint(); size = CGSize(width: element.width, height: element.height) }
                            if let size { model.editElement(element.id) { $0.width = min(model.document.paper.width - element.x, max(30, size.width + value.translation.width)); $0.height = min(model.document.paper.height - element.y, max(20, size.height + value.translation.height)) } }
                        }.onEnded { _ in size = nil; model.flush() })
                }
            }
            .offset(x: element.x, y: element.y)
            .allowsHitTesting(editing)
            .onTapGesture { model.selectedCanvasID = element.id; onActivate() }
            .gesture(DragGesture().onChanged { value in
                guard editing else { return }
                if origin == nil { model.checkpoint(); origin = CGPoint(x: element.x, y: element.y); model.selectedCanvasID = element.id; onActivate() }
                if let origin { model.editElement(element.id) { $0.x = min(model.document.paper.width - $0.width, max(0, origin.x + value.translation.width)); $0.y = min(model.document.paper.height - $0.height, max(0, origin.y + value.translation.height)) } }
            }.onEnded { _ in origin = nil; model.flush() })
    }
    @ViewBuilder private var content: some View {
        switch element.kind {
        case "image":
            if let data = element.image {
                #if os(iOS)
                if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                #else
                if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
                #endif
            }
        case "text": Text(element.text).font(.system(size: element.fontSize, weight: element.bold ? .bold : .regular)).foregroundStyle(element.color.color).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case "ellipse": Ellipse().fill(element.color.color)
        case "line", "arrow":
            Canvas { context, size in
                var path = Path(); path.move(to: CGPoint(x: 4, y: size.height / 2)); path.addLine(to: CGPoint(x: size.width - 5, y: size.height / 2))
                if element.kind == "arrow" { path.move(to: CGPoint(x: size.width - 18, y: size.height / 2 - 10)); path.addLine(to: CGPoint(x: size.width - 5, y: size.height / 2)); path.addLine(to: CGPoint(x: size.width - 18, y: size.height / 2 + 10)) }
                context.stroke(path, with: .color(element.color.color), lineWidth: 3)
            }
        default: RoundedRectangle(cornerRadius: 12).fill(element.color.color)
        }
    }
}

struct NotebookProTools: View {
    @ObservedObject var model: NotebookPageModel
    @State private var photo = false
    @State private var inspector = false
    @State private var message = ""
    private var selected: NotebookCanvasElement? { model.document.elements?.first { $0.id == model.selectedCanvasID } }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Button("Photo / PNG", systemImage: "photo") { photo = true }
                Menu("Shape", systemImage: "square.on.circle") {
                    ForEach(["rectangle", "ellipse", "line", "arrow"], id: \.self) { kind in Button(kind.capitalized) { model.addElement(NotebookCanvasElement(kind: kind)) } }
                }
                Button("Text", systemImage: "textformat") { model.addElement(NotebookCanvasElement(kind: "text", color: .ink)) }
                Button("Style & layers", systemImage: "slider.horizontal.3") { inspector = true }
                Button("Copy", systemImage: "doc.on.doc") { copy() }.disabled(selected == nil)
                Button("Paste", systemImage: "doc.on.clipboard") { paste() }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    if var element = selected { element.id = UUID().uuidString; element.x = min(model.document.paper.width - element.width, element.x + 16); element.y = min(model.document.paper.height - element.height, element.y + 16); model.addElement(element) }
                }.disabled(selected == nil)
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red) }
            }.font(.caption).padding(.vertical, 4)
        }
        .sheet(isPresented: $inspector) { inspectorView }
        .fileImporter(isPresented: $photo, allowedContentTypes: [.image]) { result in
            Task { do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try await Task.detached(priority: .userInitiated) { try Self.importImage(url) }.value
                model.addElement(NotebookCanvasElement(kind: "image", width: 260, height: 220, image: data)); model.flush()
            } catch { message = error.localizedDescription } }
        }
    }
    nonisolated private static func importImage(_ url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
    private var inspectorView: some View {
        NavigationStack {
            Form {
                if let selected {
                    Section("Selected element") {
                        if selected.kind == "text" {
                            TextField("Text", text: binding(selected.id, \.text, ""), axis: .vertical)
                            Slider(value: binding(selected.id, \.fontSize, 22), in: 10...100) { Text("Text size") }
                            Toggle("Bold", isOn: binding(selected.id, \.bold, false))
                        }
                        ColorPicker("Colour", selection: Binding(get: { selected.color.color }, set: { value in model.checkpoint(); model.editElement(selected.id) { $0.color = NotebookColor.from(value) } }))
                        Slider(value: binding(selected.id, \.opacity, 1), in: 0.05...1) { Text("Opacity") }
                        HStack {
                            Button("Bring to front") { reorder(selected.id, front: true) }
                            Button("Send to back") { reorder(selected.id, front: false) }
                        }
                        Button("Delete element", role: .destructive) { model.checkpoint(); model.document.elements?.removeAll { $0.id == selected.id }; model.selectedCanvasID = nil; model.edited() }
                    }
                }
                Section("Layers · tap to select") {
                    ForEach((model.document.elements ?? []).reversed()) { element in
                        Button { model.selectedCanvasID = element.id } label: { Label(element.kind == "text" ? element.text : element.kind.capitalized, systemImage: model.selectedCanvasID == element.id ? "checkmark.circle.fill" : "circle") }
                    }
                }
                Section("Drawing tools") {
                    ColorPicker("Ink colour", selection: Binding(get: { model.inkColor.color }, set: { model.inkColor = NotebookColor.from($0) }))
                    Slider(value: $model.inkWidth, in: 1...20) { Text("Brush width") }
                    Slider(value: $model.inkOpacity, in: 0.05...1) { Text("Brush opacity") }
                    Text("Choose Pen or Highlighter above to draw. Shapes and arrows can be moved and resized to make diagrams.").font(.caption)
                }
            }.formStyle(.grouped).navigationTitle("Canvas tools").toolbar { Button("Done") { model.flush(); inspector = false } }
        }.frame(minWidth: 320, minHeight: 420)
    }
    private func binding<T>(_ id: String, _ path: WritableKeyPath<NotebookCanvasElement, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { model.document.elements?.first { $0.id == id }?[keyPath: path] ?? fallback }, set: { value in model.editElement(id) { $0[keyPath: path] = value } })
    }
    private func reorder(_ id: String, front: Bool) {
        guard var elements = model.document.elements, let index = elements.firstIndex(where: { $0.id == id }) else { return }
        model.checkpoint(); let element = elements.remove(at: index); elements.insert(element, at: front ? elements.count : 0); model.document.elements = elements; model.edited()
    }
    private func copy() {
        guard let selected, let data = try? JSONEncoder().encode(selected) else { return }
        #if os(iOS)
        UIPasteboard.general.setData(data, forPasteboardType: "com.sathi.canvas-element")
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .init("com.sathi.canvas-element"))
        #endif
    }
    private func paste() {
        #if os(iOS)
        let data = UIPasteboard.general.data(forPasteboardType: "com.sathi.canvas-element")
        let text = UIPasteboard.general.string
        #else
        let data = NSPasteboard.general.data(forType: .init("com.sathi.canvas-element"))
        let text = NSPasteboard.general.string(forType: .string)
        #endif
        if let data, var element = try? JSONDecoder().decode(NotebookCanvasElement.self, from: data) { element.id = UUID().uuidString; model.addElement(element) }
        else if let text { model.addElement(NotebookCanvasElement(kind: "text", text: text, color: .ink)) }
    }
}
