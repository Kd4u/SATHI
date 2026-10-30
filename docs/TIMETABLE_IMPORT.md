# Timetable import and validation

The Apple importer combines a trained cell-role classifier with explicit XLSX decoding and source-cell validation. See [training and evaluation](../training/timetable/README.md). It pairs dated cells with faculty rows, keeps source cell IDs, separates programme sheets and extracts section labels. First year includes all subjects for the chosen programme/section; second year uses elective/section selection.

Supported patterns include `MBA_01_SECA` through `SECD`, `MBADBM_01`, `MBAHHM_01`, `Section A` sheets, parenthesized/plain `Sec B`, and lecture counters such as `Analytics - 10`. Roman numerals and embedded course numbers remain intact. Inline time ranges override column times. A final start-only header can inherit the preceding slot's duration, with an explicit review warning. Shared and inline Excel strings are supported.

Faculty titles include Professor, Prof., Dr., Mr., Mrs. and Ms. The classifier also handles missing/TBD/guest faculty; those classes remain flagged for review. Unknown entries remain visible with warnings. Credits use the existing class-count mapping and remain unverified for other counts.

## Saved data matters

An earlier saved Term V report contained 380 classes because it skipped column J, whose header was only `21:15`. Renaming numbered subjects did not restore those 40 entries. The original source contains 420 classes. Data Driven Decision Making, Marketing Analytics and Services Marketing have 20 sessions each; the truncated saved report contained 18, 18 and 16.

A safe reimport supplement now requires every existing class ID, source cell, date, time, subject and section to match. It can add omitted classes while preserving attendance, selections, notes, custom events, edits and the semester identity. It backs up the original report first. A different timetable follows the existing semester-archive flow. Original workbooks are retained privately on the importing device under its account's `ImportSources` directory for later audit/reparsing; they are not automatically published or included in the cloud timetable JSON.

The older numbered-name repair also backs up timetable/preferences before changing course identities and mapping selected keys. It preserves class IDs. A name repair alone cannot recover missing cells.

## Validation

All five supplied workbook variations were audited against reviewed source-cell labels and per-subject/section counts, including blank/TBD/guest instructor cases. See the training folder for the measured results and limitations. Do not treat a model score, a retained-faculty count or a successful build as proof that a device's saved timetable is complete.

Run `apple/SyncChecks/run.sh` for model inference, safe supplement, normalization, stable IDs, attendance, archive, account, sync and notebook checks. For an actual workbook audit, compile `SyncChecks/Import/main.swift`, `TimetableModels.swift`, `TimetableCellClassifier.swift` and `TimetableLogic.swift` with CoreXLSX and dependencies from a Mac build. Run the executable with an output directory, model JSON path and XLSX paths; keep its reports private and compare every source-cell identity and per-subject count.

Mixed programmes currently require explicit worksheet labels for automatic separation. Unlabelled mixed cells and unrelated layouts need review and additional fixtures. No future-format accuracy guarantee is claimed.
