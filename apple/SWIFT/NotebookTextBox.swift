import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct NotebookTextBox: View {
    @ObservedObject var model: NotebookPageModel
    let id: String
    let editing: Bool
    let onActivate: () -> Void
    @State private var moveStart: CGPoint?
    @State private var sizeStart: CGSize?
    private var index: Int? { model.document.textObjects.firstIndex { $0.id == id } }
    var body: some View {
        if let index {
            let item = model.document.textObjects[index]
            ZStack(alignment: .topLeading) {
                if editing {
                    NotebookNativeText(model: model, item: Binding(get: { model.document.textObjects.first(where: { $0.id == id }) ?? item }, set: { next in
                        guard let position = self.index else { return }; model.replaceText(next)
                    }), selected: model.selectedTextID == id, onSelect: { model.selectedTextID = id; onActivate() })
                } else {
                    Text(item.text).font(item.notebookFont).underline(item.underline).foregroundStyle(item.color.color)
                        .multilineTextAlignment(item.alignment == "center" ? .center : item.alignment == "right" ? .trailing : .leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if editing && model.selectedTextID == id {
                    Rectangle().stroke(.blue.opacity(0.55), lineWidth: 1).allowsHitTesting(false)
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15)).padding(8).background(.regularMaterial, in: Circle())
                        .offset(x: item.width - 16, y: item.height - 16)
                        .gesture(DragGesture().onChanged { value in
                            if sizeStart == nil { model.checkpoint(); sizeStart = CGSize(width: item.width, height: item.height) }
                            guard let start = sizeStart, let position = self.index else { return }
                            model.document.textObjects[position].width = min(model.document.paper.width - item.x, max(90, start.width + value.translation.width))
                            model.document.textObjects[position].height = min(model.document.paper.height - item.y, max(48, start.height + value.translation.height))
                        }.onEnded { _ in sizeStart = nil; model.edited() })
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 15)).padding(8).background(.regularMaterial, in: Circle()).offset(x: -16, y: -16)
                        .gesture(DragGesture().onChanged { value in
                            if moveStart == nil { model.checkpoint(); moveStart = CGPoint(x: item.x, y: item.y) }
                            guard let start = moveStart, let position = self.index else { return }
                            model.document.textObjects[position].x = min(model.document.paper.width - item.width, max(0, start.x + value.translation.width))
                            model.document.textObjects[position].y = min(model.document.paper.height - item.height, max(0, start.y + value.translation.height))
                        }.onEnded { _ in moveStart = nil; model.edited() })
                }
            }.frame(width: item.width, height: item.height).offset(x: item.x, y: item.y).allowsHitTesting(editing)
        }
    }
}

#if os(iOS)
struct NotebookNativeText: UIViewRepresentable {
    let model: NotebookPageModel
    @Binding var item: NotebookTextObject
    let selected: Bool
    let onSelect: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.backgroundColor = .clear; view.delegate = context.coordinator
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        var font = UIFont.systemFont(ofSize: item.fontSize, weight: item.bold ? .bold : .regular)
        if item.italic, let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) { font = UIFont(descriptor: descriptor, size: item.fontSize) }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = item.alignment == "center" ? .center : item.alignment == "right" ? .right : .left
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(item.color.color), .underlineStyle: item.underline ? NSUnderlineStyle.single.rawValue : 0, .paragraphStyle: paragraph]
        let signature = "\(item.fontSize)-\(item.bold)-\(item.italic)-\(item.underline)-\(item.alignment)-\(item.color)"
        if view.text != item.text || signature != context.coordinator.signature {
            let range = view.selectedRange
            view.attributedText = NSAttributedString(string: item.text, attributes: attrs)
            view.selectedRange = NSRange(location: min(range.location, (item.text as NSString).length), length: 0)
            context.coordinator.signature = signature
        }
        view.typingAttributes = attrs
        if selected {
            model.undoTyped = { [weak view] in guard let manager = view?.undoManager, manager.canUndo else { return false }; manager.undo(); return true }
            model.redoTyped = { [weak view] in guard let manager = view?.undoManager, manager.canRedo else { return false }; manager.redo(); return true }
            if !view.isFirstResponder { view.becomeFirstResponder() }
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NotebookNativeText; var signature = ""
        init(_ parent: NotebookNativeText) { self.parent = parent }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.onSelect() }
        func textViewDidChange(_ textView: UITextView) { parent.item.text = textView.text }
    }
}
#else
struct NotebookNativeText: NSViewRepresentable {
    let model: NotebookPageModel
    @Binding var item: NotebookTextObject
    let selected: Bool
    let onSelect: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView(); scroll.drawsBackground = false
        let view = scroll.documentView as! NSTextView
        view.drawsBackground = false; view.isRichText = false; view.allowsUndo = true; view.delegate = context.coordinator
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        var font = NSFont.systemFont(ofSize: item.fontSize, weight: item.bold ? .bold : .regular)
        if item.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = item.alignment == "center" ? .center : item.alignment == "right" ? .right : .left
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(item.color.color), .underlineStyle: item.underline ? NSUnderlineStyle.single.rawValue : 0, .paragraphStyle: paragraph]
        let signature = "\(item.fontSize)-\(item.bold)-\(item.italic)-\(item.underline)-\(item.alignment)-\(item.color)"
        if view.string != item.text || signature != context.coordinator.signature {
            let selection = view.selectedRange()
            view.textStorage?.setAttributedString(NSAttributedString(string: item.text, attributes: attrs))
            view.setSelectedRange(NSRange(location: min(selection.location, (item.text as NSString).length), length: 0))
            context.coordinator.signature = signature
        }
        view.typingAttributes = attrs
        if selected {
            model.undoTyped = { [weak view] in guard let manager = view?.undoManager, manager.canUndo else { return false }; manager.undo(); return true }
            model.redoTyped = { [weak view] in guard let manager = view?.undoManager, manager.canRedo else { return false }; manager.redo(); return true }
            if view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotebookNativeText; var signature = ""
        init(_ parent: NotebookNativeText) { self.parent = parent }
        func textDidBeginEditing(_ notification: Notification) { parent.onSelect() }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.item.text = view.string } }
    }
}
#endif
