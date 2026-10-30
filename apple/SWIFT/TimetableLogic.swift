import Foundation
import CoreXLSX

// MARK: - Data models (used by ContentView.swift)

private struct TimetableCell {
    let address: String
    let column: Int
    let row: Int
    let text: String
}

// MARK: - Excel timetable reader

struct TimetableLogic {
    func read(url: URL, modelURL: URL? = nil) throws -> TimetableReport {
        guard let file = XLSXFile(filepath: url.path) else {
            throw NSError(
                domain: "SATHI", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to open this XLSX workbook."]
            )
        }

        let sharedStrings = try file.parseSharedStrings()
        let paths = try file.parseWorksheetPaths()
        var sheetNames: [String: String] = [:]
        for workbook in try file.parseWorkbooks() {
            for item in try file.parseWorksheetPathsAndNames(workbook: workbook) { sheetNames[item.path] = item.name ?? "" }
        }
        var sessions: [TimetableSession] = []
        var events: [TimetableEvent] = []
        var warnings: [String] = []
        let classifier = TimetableCellClassifier(url: modelURL)
        if !classifier.available { warnings.append("Cell-role model unavailable; deterministic matching used. Review unmatched entries.") }

        for (sheetIndex, sheetPath) in paths.enumerated() {
            let stableSheetID = "Sheet\(sheetIndex + 1)"
            let sheetName = sheetNames[sheetPath].flatMap { $0.isEmpty ? nil : $0 } ?? stableSheetID
            let sheet = try file.parseWorksheet(at: sheetPath)
            var byRow: [Int: [Int: TimetableCell]] = [:]

            for row in sheet.data?.rows ?? [] {
                for cell in row.cells {
                    let address = cell.reference.description
                    guard let position = cellPosition(address) else { continue }
                    let raw: String
                    if let sharedStrings = sharedStrings {
                        raw = cell.stringValue(sharedStrings) ?? cell.inlineString?.text ?? cell.value ?? ""
                    } else {
                        raw = cell.inlineString?.text ?? cell.value ?? ""
                    }
                    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { continue }
                    byRow[position.row, default: [:]][position.column] = TimetableCell(
                        address: address, column: position.column,
                        row: position.row, text: value
                    )
                }
            }

            guard !byRow.isEmpty else { continue }
            let rowNumbers = byRow.keys.sorted()
            let headerRow = rowNumbers.first { number in
                let cells = byRow[number] ?? [:]
                return cells.values.contains { $0.text.lowercased() == "date" } &&
                       cells.values.contains { $0.text.lowercased() == "day" }
            } ?? rowNumbers[0]
            let header = byRow[headerRow] ?? [:]
            let sheetSection = TimetableSection.label(in: sheetName)
            let explicitSections = Set(rowNumbers.filter { $0 < headerRow }.flatMap { (byRow[$0] ?? [:]).values.map { TimetableSection.label(in: $0.text) } }.filter { !$0.isEmpty })
            let hasInlineSections = byRow.values.contains { row in row.values.contains { !extractSection($0.text).1.isEmpty } }
            let inheritedSection = hasInlineSections ? "" : (!sheetSection.isEmpty ? sheetSection : (explicitSections.count == 1 ? explicitSections.first! : ""))
            let dateColumn = header.first { $0.value.text.lowercased() == "date" }?.key ?? 1
            let dayColumn = header.first { $0.value.text.lowercased() == "day" }?.key ?? 2
            var timeColumns: [(Int, String)] = header.compactMap { column, cell in
                isTimeSlot(cell.text) ? (column, cell.text) : nil
            }.sorted { $0.0 < $1.0 }

            // A few supplied schedules omit the end of the last slot. Infer only
            // from a complete preceding slot and surface that inference for review.
            for (column, cell) in header.sorted(by: { $0.key < $1.key }) where !isTimeSlot(cell.text) {
                if cell.text.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil,
                   let previous = timeColumns.last, column == previous.0 + 1 {
                    let clocks = previous.1.components(separatedBy: "-")
                    func minutes(_ clock: String) -> Int? {
                        let parts = clock.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
                        return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
                    }
                    if clocks.count == 2, let start = minutes(clocks[0]), let end = minutes(clocks[1]),
                       let next = minutes(cell.text), end > start, next + end - start < 1440 {
                        let finish = next + end - start
                        let slot = cell.text + String(format: "-%02d:%02d", finish / 60, finish % 60)
                        timeColumns.append((column, slot))
                        warnings.append("\(sheetName)!\(cell.address): inferred end time \(slot); verify against the official schedule")
                    }
                }
            }
            guard !timeColumns.isEmpty else {
                warnings.append("\(sheetName): no time-slot headers detected")
                continue
            }

            // Only reuse a course identity seen with explicit faculty elsewhere in this sheet.
            var knownCourses = Set<String>()
            var courseOccurrences: [String: Int] = [:]
            for number in rowNumbers where number > headerRow && !excelDate(byRow[number]?[dateColumn]?.text ?? "").isEmpty {
                for (column, _) in timeColumns {
                    let entries = splitEntries(byRow[number]?[column]?.text ?? "")
                    let teachers = splitEntries(byRow[number + 1]?[column]?.text ?? "")
                    for entry in entries where !isTimeSlot(entry) {
                        courseOccurrences[extractSection(entry).0, default: 0] += 1
                    }
                    if teachers.contains(where: isProfessor) {
                        for entry in entries where !isTimeSlot(entry) { knownCourses.insert(extractSection(entry).0) }
                    }
                }
            }
            for rowNumber in rowNumbers where rowNumber > headerRow {
                let row = byRow[rowNumber] ?? [:]
                let date = excelDate(row[dateColumn]?.text ?? "")
                // A dated row contains subjects/events; its following row contains faculty.
                guard !date.isEmpty else { continue }
                let day = row[dayColumn]?.text ?? ""
                let facultyRow = byRow[rowNumber + 1] ?? [:]

                for (column, defaultSlot) in timeColumns {
                    guard let cell = row[column] else { continue }
                    let source = "\(sheetName)!\(cell.address)"
                    let entries = splitEntries(cell.text)
                    guard !entries.isEmpty else { continue }
                    let inlineSlot = entries.first.flatMap { isTimeSlot($0) ? $0 : nil }
                    let slot = inlineSlot ?? defaultSlot
                    let courseEntries = entries.filter { !isTimeSlot($0) }
                    let faculty = splitEntries(facultyRow[column]?.text ?? "")

                    // Whole-cell events can span several lines; preserve their title.
                    if looksLikeEvent(cell.text) && !faculty.contains(where: isProfessor) && !courseEntries.contains(where: { knownCourses.contains(extractSection($0).0) }) {
                        events.append(TimetableEvent(
                            date: date, time: slot, title: cell.text, source: source
                        ))
                        continue
                    }

                    if entries.allSatisfy(isProfessor) {
                        warnings.append("\(source): professor appears in subject row")
                        continue
                    }

                    for (index, entry) in entries.enumerated() {
                        if isTimeSlot(entry) { continue }
                        let courseIndex = courseEntries.firstIndex(of: entry) ?? index
                        let teacher: String
                        if faculty.count == courseEntries.count {
                            teacher = faculty[courseIndex]
                        } else if faculty.count == 1 && courseEntries.count == 1 {
                            teacher = faculty[0]
                        } else if faculty.count == 1 && courseEntries.count > 1 && isProfessor(faculty[0]) {
                            // One professor explicitly covers multiple subject/section entries.
                            teacher = faculty[0]
                        } else {
                            teacher = ""
                        }

                        let courseName = extractSection(entry).0
                        let probability = classifier.classProbability(text: entry, faculty: teacher,
                            repetitions: courseOccurrences[courseName] ?? 0, knownCourse: knownCourses.contains(courseName))
                        let modelClass = (probability ?? 0) >= 0.5
                        if looksLikeEvent(entry) && !isProfessor(teacher) && !knownCourses.contains(courseName) && !modelClass {
                            events.append(TimetableEvent(
                                date: date, time: slot, title: entry, source: source
                            ))
                            continue
                        }

                        // A real subject requires a professor in the row immediately below.
                        // Unpaired entries are displayed as events, never assigned credits.
                        guard isProfessor(teacher) || knownCourses.contains(courseName) || modelClass else {
                            events.append(TimetableEvent(
                                date: date, time: slot, title: entry, source: source
                            ))
                            if !isRecognizedEvent(entry) {
                                warnings.append("\(source): no matching professor for '\(entry)' — treated as event; verify if this is a class")
                            }
                            continue
                        }

                        if !isProfessor(teacher) {
                            let confidence = probability.map { String(format: "%.1f%%", $0 * 100) } ?? "unavailable"
                            warnings.append("\(source): course with missing/unconfirmed faculty (cell-role score \(confidence)); verify instructor")
                        }
                        let (name, inlineSection) = extractSection(entry)
                        let section = inlineSection.isEmpty ? inheritedSection : inlineSection
                        guard !name.isEmpty else { continue }
                        sessions.append(TimetableSession(
                            id: "\(stableSheetID)-\(cell.address)-\(index)",
                            date: date, day: day, time: slot,
                            subject: name, section: section,
                            teacher: teacher, source: source
                        ))
                    }
                }
            }
        }

        let grouped = Dictionary(grouping: sessions) {
            $0.subject + "|" + $0.section
        }
        let subjects: [TimetableSubject] = grouped.map { key, entries in
            let first = entries[0]
            let name = first.subject + (first.section.isEmpty ? "" : " (Sec \(first.section))")
            return TimetableSubject(
                key: key, name: name, count: entries.count,
                credits: credits(for: entries.count)
            )
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if sessions.isEmpty {
            warnings.append("No classes with matched professors were found. Check the workbook layout.")
        }
        return TimetableReport(
            workbook: url.lastPathComponent,
            sessions: sessions,
            subjects: subjects,
            events: events,
            warnings: warnings
        )
    }

    // MARK: - Event classification

    private func isRecognizedEvent(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if ["ID", "QUIZ", "QUIZ SLOT", "NO CLASS", "OFF DAY"].contains(normalized) {
            return true
        }
        let phrases = [
            "QUIZ", "HOLIDAY", "HOLIDAYS", "INDEPENDENCE DAY", "REPUBLIC DAY",
            "DUSSEHRA", "DIWALI", "CHRISTMAS", "GANDHI JAYANTI",
            "EXAM", "EXAMINATION", "MID TERM", "MID-TERM", "END TERM", "END-TERM",
            "BREAK", "VACATION", "INAUGURATION", "CONVOCATION",
            "NO CLASS", "PRESENTATION", "INTERNSHIP PRESENTATION",
            "EID", "MILAD", "CHHATH", "CHATTH", "JAYANTI", "ELEGANTE", "CONCLAVE",
            "ORIENTATION", "INDUCTION", "SPORTS DAY", "CULTURAL DAY"
        ]
        return phrases.contains { normalized.contains($0) }
    }

    private func looksLikeEvent(_ text: String) -> Bool {
        isRecognizedEvent(text)
    }

    // MARK: - Excel helpers

    private func cellPosition(_ address: String) -> (column: Int, row: Int)? {
        let letters = address.prefix { $0.isLetter }.uppercased()
        let digits = address.dropFirst(letters.count)
        guard !letters.isEmpty, let row = Int(digits) else { return nil }
        var column = 0
        for character in letters.unicodeScalars {
            column = column * 26 + Int(character.value) - 64
        }
        return (column, row)
    }

    private func isTimeSlot(_ value: String) -> Bool {
        value.range(
            of: #"\d{1,2}[:.]\d{2}\s*[-–—]\s*\d{1,2}[:.]\d{2}"#,
            options: .regularExpression
        ) != nil
    }

    private func excelDate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let serial = Double(trimmed), serial > 30000, serial < 90000 {
            let date = Date(timeIntervalSince1970: (serial - 25569) * 86400)
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        if trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return trimmed
        }
        for format in ["dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy", "dd MMM yyyy", "d MMM yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: trimmed) {
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: date)
            }
        }
        return ""
    }

    private func splitEntries(_ text: String) -> [String] {
        text.replacingOccurrences(
            of: #"(?i)\(\s*sec(?:tion)?\s*\n\s*([A-Z])\s*\)"#,
            with: "(Sec $1)", options: .regularExpression
        )
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func isProfessor(_ text: String) -> Bool {
        text.range(
            of: #"(?i)^\s*(?:professor|prof\.?|dr\.?|mr\.?|mrs\.?|ms\.?)\s+"#,
            options: .regularExpression
        ) != nil
    }

    private func extractSection(_ raw: String) -> (String, String) {
        TimetableIdentity.course(raw)
    }

    private func credits(for count: Int) -> Double {
        switch count {
        case 20: return 3
        case 15: return 2.25
        case 10: return 1.5
        case 7: return 1
        default: return 0 // Unrecognized class counts require review.
        }
    }
}
