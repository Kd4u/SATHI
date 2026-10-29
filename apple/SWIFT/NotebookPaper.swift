import SwiftUI
import PencilKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension NotebookColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var isDark: Bool { red * 0.3 + green * 0.59 + blue * 0.11 < 0.45 }
}

struct PaperBackgroundView: View {
    let paper: PaperConfiguration
    var body: some View {
        Canvas { graphics, size in
            let rect = CGRect(origin: .zero, size: size)
            graphics.fill(Path(rect), with: .color(paper.background.color.opacity(paper.backgroundOpacity)))
            let margin = paper.safeMargin
            var rules = Path()
            func vertical(_ x: Double) { rules.move(to: CGPoint(x: x, y: margin)); rules.addLine(to: CGPoint(x: x, y: size.height - margin)) }
            func horizontal(_ y: Double, _ left: Double = 0) { rules.move(to: CGPoint(x: left, y: y)); rules.addLine(to: CGPoint(x: size.width, y: y)) }
            switch paper.template {
            case .blank: break
            case .ruled, .custom, .cornell, .checklist:
                for y in stride(from: margin + paper.safeSpacing, to: size.height - margin, by: paper.safeSpacing) {
                    horizontal(y, paper.template == .cornell ? size.width * 0.28 : margin)
                    if paper.template == .checklist { rules.addRect(CGRect(x: margin, y: y - 16, width: 10, height: 10)) }
                }
                if paper.template == .cornell { vertical(size.width * 0.28); horizontal(size.height * 0.8, margin) }
                else { vertical(margin) }
            case .grid:
                let spacing = max(8, min(80, paper.gridSpacing))
                for x in stride(from: margin, through: size.width - margin, by: spacing) { vertical(x) }
                for y in stride(from: margin, through: size.height - margin, by: spacing) { horizontal(y, margin) }
            case .dotted:
                let spacing = max(8, min(80, paper.dotSpacing))
                for y in stride(from: margin, through: size.height - margin, by: spacing) {
                    for x in stride(from: margin, through: size.width - margin, by: spacing) {
                        graphics.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(paper.ruleColor.color))
                    }
                }
            }
            graphics.stroke(rules, with: .color(paper.ruleColor.color.opacity(0.65)), lineWidth: 0.55)
        }.allowsHitTesting(false)
    }
}

struct NotebookCoverView: View {
    let book: NotebookManifest
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(book.coverColor.color.gradient)
            if book.coverStyle == "linen" || book.coverStyle == "leather" {
                Canvas { context, size in
                    var path = Path()
                    for y in stride(from: 0.0, to: size.height, by: book.coverStyle == "linen" ? 4 : 11) {
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y + 1))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                }.clipShape(RoundedRectangle(cornerRadius: 10))
            }
            HStack { Rectangle().fill(.black.opacity(0.16)).frame(width: 12); Spacer(); Rectangle().fill(.white.opacity(0.12)).frame(width: 4) }.clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "book.closed").font(.title2)
                Text(book.title).font(.headline).lineLimit(4)
                Spacer()
                Text(book.subject.isEmpty ? "NOTEBOOK" : book.subject.uppercased()).font(.system(size: 9, weight: .medium)).lineLimit(2)
            }.foregroundStyle(.white).padding(20)
        }.aspectRatio(0.72, contentMode: .fit)
    }
}

struct NotebookPaperSettings: View {
    @Binding var paper: PaperConfiguration
    var body: some View {
        Form {
            Picker("Paper", selection: $paper.template) { ForEach(NotebookPaper.allCases, id: \.self) { Text($0.title).tag($0) } }
            Picker("Size", selection: $paper.size) { ForEach(["A4", "A5", "Letter", "Custom"], id: \.self) { Text($0).tag($0) } }
            Toggle("Landscape", isOn: $paper.landscape)
            if paper.size == "Custom" {
                TextField("Width (points)", value: $paper.customWidth, format: .number)
                TextField("Height (points)", value: $paper.customHeight, format: .number)
            }
            ColorPicker("Paper colour", selection: colorBinding(\PaperConfiguration.background), supportsOpacity: false)
            ColorPicker("Rule colour", selection: colorBinding(\PaperConfiguration.ruleColor), supportsOpacity: false)
            Slider(value: $paper.backgroundOpacity, in: 0.25...1) { Text("Paper opacity") }
            Slider(value: $paper.spacing, in: 16...60, step: 2) { Text("Line spacing") }
            Slider(value: $paper.gridSpacing, in: 10...60, step: 2) { Text("Grid spacing") }
            Slider(value: $paper.dotSpacing, in: 10...60, step: 2) { Text("Dot spacing") }
            Slider(value: $paper.margin, in: 16...90, step: 2) { Text("Margins") }
            HStack {
                Button("White") { paper.background = .white; paper.ruleColor = .init(red: 0.65, green: 0.75, blue: 0.85) }
                Button("Cream") { paper.background = .init(red: 0.99, green: 0.97, blue: 0.89) }
                Button("Dark") { paper.background = .init(red: 0.10, green: 0.12, blue: 0.15); paper.ruleColor = .init(red: 0.32, green: 0.37, blue: 0.43) }
            }
            Text("Ink keeps its chosen colour. Pick contrasting ink when changing paper colour.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
    private func colorBinding(_ path: WritableKeyPath<PaperConfiguration, NotebookColor>) -> Binding<Color> {
        Binding(get: { paper[keyPath: path].color }, set: { paper[keyPath: path] = NotebookColor.from($0) })
    }
}

extension NotebookColor {
    static func from(_ color: Color) -> NotebookColor {
        #if os(iOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return .init(red: r, green: g, blue: b)
        #else
        let c = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        return .init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
        #endif
    }
}
