
//
//  ExcelTimetableParser.swift
//  SWIFT
//

import Foundation
import CoreXLSX

// MARK: - Subject Model

struct SubjectOption: Identifiable {
    var id: String { name }

    var name: String
    var classCount: Int
    var sections: [String]

    var credits: Double {
        switch classCount {
        case 7:
            return 1.0
        case 10:
            return 1.5
        case 15:
            return 2.25
        case 20:
            return 3.0
        default:
            return Double(classCount) * 0.15
        }
    }
}

// MARK: - Excel Parser

enum ExcelTimetableParser {

    static func parse(url: URL) throws -> [SubjectOption] {

        let accessing = url.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Currently support modern Excel files only.
        guard url.pathExtension.lowercased() == "xlsx" else {
            throw parserError(
                code: 1,
                message: "Please select an .xlsx Excel file."
            )
        }

        // XLSXFile is optional in CoreXLSX.
        guard let file = XLSXFile(filepath: url.path) else {
            throw parserError(
                code: 2,
                message:
                    "Could not open the Excel file. " +
                    "Check that it is a valid, uncorrupted .xlsx file."
            )
        }

        let sharedStrings = try file.parseSharedStrings()
        let worksheetPaths = try file.parseWorksheetPaths()

        guard !worksheetPaths.isEmpty else {
            throw parserError(
                code: 3,
                message: "No worksheets were found in this Excel file."
            )
        }

        var counts: [String: Int] = [:]
        var sectionsBySubject: [String: Set<String>] = [:]

        // Read every worksheet.
        for path in worksheetPaths {

            let worksheet = try file.parseWorksheet(at: path)

            for row in worksheet.data?.rows ?? [] {

                let rowTexts: [String] = row.cells.map { cell in
                    if let sharedStrings {
                        return cell.stringValue(sharedStrings)
                            ?? cell.value
                            ?? ""
                    }

                    return cell.value ?? ""
                }

                // Process individual cell entries.
                for rawText in rowTexts {

                    let lines = rawText.components(
                        separatedBy: .newlines
                    )

                    for line in lines {

                        let cleanedLine = normalize(line)

                        guard !cleanedLine.isEmpty else {
                            continue
                        }

                        let detectedSections = findSections(
                            in: cleanedLine
                        )

                        let subjectText = cleanedLine
                            .replacingOccurrences(
                                of: #"(?i)\b(?:section|sec|batch|group)\s*[-:]?\s*[A-Z0-9]+\b"#,
                                with: "",
                                options: .regularExpression
                            )
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                        guard isSubjectCandidate(subjectText) else {
                            continue
                        }

                        let key = normalize(subjectText)

                        counts[key, default: 0] += 1

                        sectionsBySubject[key, default: []]
                            .formUnion(detectedSections)
                    }
                }
            }
        }

        // Build the subject list.
        let results: [SubjectOption] = counts.keys
            .sorted {
                $0.localizedCaseInsensitiveCompare($1)
                    == .orderedAscending
            }
            .compactMap { key in

                guard let count = counts[key] else {
                    return nil
                }

                return SubjectOption(
                    name: key,
                    classCount: count,
                    sections: Array(
                        sectionsBySubject[key] ?? []
                    ).sorted()
                )
            }

        return results
    }

    // MARK: - Error Helper

    private static func parserError(
        code: Int,
        message: String
    ) -> NSError {
        NSError(
            domain: "SATHI.ExcelParser",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: message
            ]
        )
    }

    // MARK: - Text Normalisation

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }

    // MARK: - Section Detection

    private static func findSections(
        in text: String
    ) -> Set<String> {

        let pattern =
            #"(?i)\b(?:section|sec|batch|group)\s*[-:]?\s*([A-Z0-9]+)\b"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return []
        }

        let range = NSRange(
            text.startIndex..<text.endIndex,
            in: text
        )

        return Set(
            regex.matches(
                in: text,
                range: range
            ).compactMap { match in

                guard let captureRange = Range(
                    match.range(at: 1),
                    in: text
                ) else {
                    return nil
                }

                let label = String(
                    text[captureRange]
                ).uppercased()

                return "Section \(label)"
            }
        )
    }

    // MARK: - Subject Candidate Validation

    private static func isSubjectCandidate(
        _ value: String
    ) -> Bool {

        let text = normalize(value)

        guard text.count >= 2, text.count <= 100 else {
            return false
        }

        let lower = text.lowercased()

        // Common timetable headings and non-subject labels.
        let excluded: Set<String> = [
            "date", "day", "subject", "subjects",
            "faculty", "teacher", "teachers",
            "time", "timing", "venue", "room",
            "section", "semester", "course",
            "batch", "group", "professor",
            "class", "classes", "lecture",
            "break", "lunch", "holiday",
            "monday", "tuesday", "wednesday",
            "thursday", "friday", "saturday",
            "sunday", "morning", "afternoon",
            "evening", "free", "off"
        ]

        guard !excluded.contains(lower) else {
            return false
        }

        // Exclude faculty names with common titles.
        if lower.range(
            of: #"^(prof\.?|dr\.?|mr\.?|mrs\.?|ms\.?)\s"#,
            options: .regularExpression
        ) != nil {
            return false
        }

        // Exclude numeric values and date-like values.
        if lower.range(
            of: #"^\d+([./:-]\d+)*$"#,
            options: .regularExpression
        ) != nil {
            return false
        }

        // Exclude times such as 08:15 or 08:15-09:45.
        if lower.range(
            of: #"^\d{1,2}:\d{2}(\s*[-–]\s*\d{1,2}:\d{2})?$"#,
            options: .regularExpression
        ) != nil {
            return false
        }

        // Exclude common date formats.
        if lower.range(
            of: #"^\d{1,4}[-/]\d{1,2}[-/]\d{1,4}$"#,
            options: .regularExpression
        ) != nil {
            return false
        }

        return true
    }
}

