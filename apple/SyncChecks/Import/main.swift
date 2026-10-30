import Foundation
guard CommandLine.arguments.count >= 4 else {
    fatalError("Usage: import-check OUTPUT_DIRECTORY MODEL.json WORKBOOK.xlsx [WORKBOOK.xlsx ...]")
}
for path in CommandLine.arguments.dropFirst(3) {
 let report = try TimetableLogic().read(url: URL(fileURLWithPath: path), modelURL: URL(fileURLWithPath: CommandLine.arguments[2]))
 let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent + ".json")
 try JSONEncoder().encode(report).write(to: output)
 print("\(report.workbook): \(report.sessions.count) classes; \(report.subjects.count) subject/section groups; \(report.warnings.count) warnings")
 for warning in report.warnings.prefix(5) { print(warning) }
}
