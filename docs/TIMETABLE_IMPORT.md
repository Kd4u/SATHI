# Timetable import and validation

The native importer uses deterministic XLSX parsing, not a trained language model. It pairs dated cells with faculty rows, keeps source cell IDs, separates programme sheets and extracts explicit section labels. First-year selection includes all subjects for the chosen programme/section; second-year selection uses electives and one section per subject.

Supported patterns include `MBA_01_SECA` through `SECD`, `MBADBM_01`, `MBAHHM_01`, `Section A` sheets, parenthesized or plain `Sec B`, and hyphenated lecture counters such as `Analytics - 10`. Roman numerals and embedded course numbers remain intact. A time range on its own line overrides the column time. A final start-only header may inherit the previous slot's duration; that inference is listed for review.

Faculty titles include Professor, Prof., Dr., Mr., Mrs. and Ms. A missing instructor can be accepted only when the same course has explicit faculty elsewhere in that worksheet; it remains flagged. Unknown entries stay visible as events with review warnings rather than being silently discarded. Credits are estimates from the existing count mapping and remain unverified for other counts.

Older saved imports with numbered names receive an identity repair on Apple. Original local timetable/preferences are backed up before replacement; class IDs, dates, attendance, notes and edits are retained, and selected subject keys are mapped to the repaired identities. This cannot recover classes skipped by an older importer: import the source workbook again when that is necessary. Existing semester preservation applies to reimports.

## Regression evidence

Five maintainer-supplied workbooks (terms I–V, including combined programme workbooks) were tested locally. All 3,094 entries with explicit faculty were retained. Term V produced 420 classes in 23 subject/section groups; Advanced Business Analytics has 20 sessions, and B2B Marketing retains sections A and B. These are retention and fixture checks, not independently labelled semantic accuracy or a guarantee for unseen formats. The source workbooks and student data are not published.

`SyncChecks/Study/check.swift` covers normalization, section/programme labels, identity repair, idempotence and stable IDs alongside existing attendance/archive checks. Run `apple/SyncChecks/run.sh`.

For an actual workbook audit, compile `SyncChecks/Import/main.swift`, `TimetableModels.swift` and `TimetableLogic.swift` with CoreXLSX and its dependencies from a local Mac build, then run the executable with an existing output directory followed by XLSX paths. It exports reports for comparison against source cells. Keep those exports private. Inspect faculty pairing, subject names, programme, section and time—not merely a total class count.

Combined programmes need explicit worksheet labels to be separated automatically. Unlabelled mixed cells or a future unrelated format require review and additional parser fixtures; do not report them as successfully recognized without checking.
