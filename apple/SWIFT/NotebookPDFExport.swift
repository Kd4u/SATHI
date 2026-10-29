import Foundation
import CoreGraphics
import CoreText
import PencilKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

nonisolated enum NotebookPDFSource: Sendable { case file(URL), draft(NotebookPageDocument) }
nonisolated enum NotebookPDFExport {
    static func export(title: String, sources: [NotebookPDFSource], destination: URL) throws -> URL {
        guard !sources.isEmpty, let consumer = CGDataConsumer(url: destination as CFURL) else { throw NotebookFailure.invalidRange }
        var initial = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &initial, [kCGPDFContextTitle: title] as CFDictionary) else { throw NotebookFailure.missingPage }
        for source in sources {
            try autoreleasepool {
                let page: NotebookPageDocument
                switch source {
                case .draft(let value): page = value
                case .file(let url): page = try JSONDecoder().decode(NotebookPageDocument.self, from: Data(contentsOf: url))
                }
                var rect = CGRect(x: 0, y: 0, width: page.paper.width, height: page.paper.height)
                let data = withUnsafeBytes(of: &rect) { Data($0) }
                context.beginPDFPage([kCGPDFContextMediaBox: data] as CFDictionary)
                draw(page, in: context, scale: 2)
                context.endPDFPage()
            }
        }
        context.closePDF(); return destination
    }
    static func thumbnail(_ page: NotebookPageDocument) -> CGImage? {
        let scale = 0.16
        let width = max(1, Int(page.paper.width * scale)); let height = max(1, Int(page.paper.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale); draw(page, in: context, scale: scale)
        return context.makeImage()
    }
    static func fitText(_ item: NotebookTextObject, height: Double) -> (String, String, Double) {
        let font = CTFontCreateUIFontForLanguage(.system, item.fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, item.fontSize, nil)
        let string = NSAttributedString(string: item.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let setter = CTFramesetterCreateWithAttributedString(string)
        var range = CFRange()
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil, CGSize(width: max(60, item.width), height: max(40, height)), &range)
        let text = item.text as NSString
        let count = min(text.length, range.length)
        guard count < text.length else { return (item.text, "", min(height, max(48, ceil(measured.height) + 12))) }
        let safe = count > 0 ? count : text.rangeOfComposedCharacterSequence(at: 0).length
        return (text.substring(to: safe), text.substring(from: safe), max(48, height))
    }
    private static func color(_ value: NotebookColor, alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: alpha)
    }
    private static func draw(_ page: NotebookPageDocument, in context: CGContext, scale: Double) {
        let paper = page.paper; let w = paper.width; let h = paper.height; let m = paper.safeMargin
        context.saveGState()
        context.setFillColor(color(paper.background, alpha: paper.backgroundOpacity)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.setStrokeColor(color(paper.ruleColor, alpha: 0.65)); context.setLineWidth(0.55)
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { context.move(to: CGPoint(x: x1, y: h - y1)); context.addLine(to: CGPoint(x: x2, y: h - y2)) }
        switch paper.template {
        case .blank: break
        case .ruled, .custom, .cornell, .checklist:
            for y in stride(from: m + paper.safeSpacing, to: h - m, by: paper.safeSpacing) {
                line(paper.template == .cornell ? w * 0.28 : m, y, w - m, y)
                if paper.template == .checklist { context.addRect(CGRect(x: m, y: h - y + 6, width: 10, height: 10)) }
            }
            line(paper.template == .cornell ? w * 0.28 : m, m, paper.template == .cornell ? w * 0.28 : m, h - m)
            if paper.template == .cornell { line(m, h * 0.8, w - m, h * 0.8) }
        case .grid:
            for x in stride(from: m, through: w - m, by: max(8, paper.gridSpacing)) { line(x, m, x, h - m) }
            for y in stride(from: m, through: h - m, by: max(8, paper.gridSpacing)) { line(m, y, w - m, y) }
        case .dotted:
            context.setFillColor(color(paper.ruleColor))
            for y in stride(from: m, through: h - m, by: max(8, paper.dotSpacing)) {
                for x in stride(from: m, through: w - m, by: max(8, paper.dotSpacing)) { context.fillEllipse(in: CGRect(x: x, y: h - y, width: 1.4, height: 1.4)) }
            }
        }
        context.strokePath()
        if !page.drawing.isEmpty, let drawing = try? PKDrawing(data: page.drawing) {
            let bounds = drawing.bounds.insetBy(dx: -4, dy: -4).intersection(CGRect(x: 0, y: 0, width: w, height: h))
            if !bounds.isEmpty && !bounds.isInfinite {
                let image = drawing.image(from: bounds, scale: max(0.16, scale))
                #if os(iOS)
                let cg = image.cgImage
                #else
                let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                #endif
                if let cg { context.draw(cg, in: CGRect(x: bounds.minX, y: h - bounds.maxY, width: bounds.width, height: bounds.height)) }
            }
        }
        for item in page.textObjects {
            let base = CTFontCreateUIFontForLanguage(.system, item.fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, item.fontSize, nil)
            var traits = CTFontSymbolicTraits()
            if item.bold { traits.insert(.boldTrait) }; if item.italic { traits.insert(.italicTrait) }
            let font = CTFontCreateCopyWithSymbolicTraits(base, item.fontSize, nil, traits, traits) ?? base
            var alignment: CTTextAlignment = item.alignment == "center" ? .center : item.alignment == "right" ? .right : .left
            let paragraph = withUnsafePointer(to: &alignment) { pointer -> CTParagraphStyle in
                var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
                return CTParagraphStyleCreate(&setting, 1)
            }
            let string = NSAttributedString(string: item.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(item.color), NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph, NSAttributedString.Key(kCTUnderlineStyleAttributeName as String): item.underline ? 1 : 0])
            let setter = CTFramesetterCreateWithAttributedString(string)
            let rect = CGRect(x: item.x, y: h - item.y - item.height, width: max(1, item.width), height: max(1, item.height))
            context.textMatrix = .identity
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil), context)
        }
        context.restoreGState()
    }
}
