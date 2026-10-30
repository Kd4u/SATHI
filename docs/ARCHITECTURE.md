# Architecture

SATHI has two native clients and one compatible Firebase data contract. SwiftUI code is in `apple/`; Java Android Views code is in `android/`. There is no shared UI runtime and no client-side admin credential.

## Local-first flow

Clients scope saved files to the authenticated Firebase UID rather than sharing a global cache between accounts. Local writes use atomic replacement. A cached timetable is shown immediately; network requests and workbook parsing should not block drawing, typing or initial presentation.

Clients show cached data immediately and check cloud on launch/foreground. An account-scoped Firestore listener requests a merge when a committed server snapshot changes, so a Sync tap on one device reaches other open clients. Pending/local/cache-only notifications and equivalent JSON are ignored to avoid write loops. Mobile listeners detach in background; foreground restore and hourly OS background opportunities handle suspended devices. Completed imports/onboarding upload immediately; ordinary local edits are committed by Sync or hourly opportunities.

## Timetable snapshot

`users/{uid}/sathi/snapshot` has `schema: 1`, a Firestore bytes `payload` and an `updatedAt` server timestamp. The payload is a JSON object containing `records`, a map of keys to **base64-encoded JSON bytes**, matching Swift Codable `Data`.

Keys include `timetable`, `selection`, `attendance:{id}`, `event:{uuid}`, `study:preferences`, `study:semesters`, `study:proof:{id}` and `study:override:{id}`. Preserve unknown keys byte-for-byte. Session IDs derived from worksheet/cell/index allow attendance to refer to the same imported class on both platforms. Swift dates use seconds from 2001-01-01 unless the model specifies a date string.

Sync uses a three-way comparison between a saved baseline, the local snapshot and the remote snapshot, inside a Firestore transaction. Independent edits merge. Divergent changes keep both drafts, but block only the conflicting records: unrelated attendance/OD/events can still commit. The local checkpoint advances only successful records, retaining the original baseline for unresolved conflicts and retries. JSON record comparisons ignore object-key order and formatting differences across clients. An explicit conflict choice selects this device or cloud for conflicting records. A timetable conflict also selects its associated subject selection, semester index and study preferences as one bundle, preventing an accepted timetable from showing zero classes under another import’s selection. Both snapshots and the baseline are saved in private SyncConflictBackups before a resolving transaction writes; independent edits are retained. In-flight edits still use the normal conflict-protected merge. Android also merges edits made while the request was running into the local result, so a network response cannot discard fresh local typing/changes.

The shared snapshot stays below the Firestore document-size limit; clients reject oversized payloads before committing. Do not store drawing blobs inside this single document.

## Notes, archives and journal

Private study assets live below `users/{uid}/studyAssets/{id}`. A head contains metadata, a revision and a chunk count; content is stored in versioned chunk documents. A new head is published transactionally after content upload. Revision checks prevent silently replacing a notebook edited elsewhere.

The Apple notebook store indexes metadata with SwiftData and loads pages on demand. Page documents contain paper settings, typed text objects and raw PencilKit data. Android preserves fields it cannot interpret and currently edits typed text only. Full notebook creation and semester archive viewing are not yet Android parity features.

Activity entries are private payloads under `users/{uid}/activity/{id}` with server commit timestamps. Use immutable entry IDs and do not log passwords, OAuth tokens or private credentials. Android currently uploads its own journal; its full history UI is not implemented.

## Glanceable surfaces

Apple widgets/Live Activities use a saved shared schedule surface, not a Firebase request on each refresh. Android's `ScheduleWidget` uses the local snapshot and selects one or three days based on widget height. OS refresh policy means widgets and reminders are not precise delivery guarantees.

## Attendance

Unmarked means unknown. Official duty counts as present. Fingerprint and sheet confirmation remain distinct from attendance. The current configurable app policy can penalize a fingerprint/sheet mismatch by marking the next three scheduled classes missed; this is a user-facing planning rule, not a connection to institutional records. Keep all affected classes visible in the timetable.

## Timetable extraction and cell-role model

Apple decodes XLSX cells with CoreXLSX and applies a small trained logistic cell-role classifier from `SWIFT/TimetableCellRole.json`. It runs locally in native Swift and distinguishes class candidates from events/background. Source positions, time parsing, name normalization, programme/section handling and completeness checks remain explicit. See [training/evaluation](../training/timetable/README.md) and [import repair](TIMETABLE_IMPORT.md). Android currently uses its existing deterministic parser; no Android model integration is claimed here.

A matching-timetable supplement requires every saved class identity and source/date/time/subject/section to remain present, then permits added cells while retaining selections, attendance and semester state. Original workbooks are retained privately on the importing device for future audit. Those source files are not automatically uploaded as part of the shared JSON snapshot.


## Import completeness and legacy repair

Parser revision 2 includes trailing start-only time headers when a complete preceding slot supplies a valid duration. The inferred end is shown for review. No class is generated to meet a target count. Subject/section counts are recomputed from actual source sessions.

Apple can re-read preserved ImportSources on launch for a legacy import, only accepting a strict supplement with every existing class ID/date/time/source/subject/section unchanged. The previous timetable is backed up before replacement. Attendance, custom events, manual selections and notebook files are retained.

During sync, a revision-2 strict supplement can replace a matching legacy partial import automatically on either side. Two revision-2 schedules, changed class identities and different semesters still require conflict resolution; a genuine cancellation must not be mistaken for an incomplete legacy parse. Raw workbooks remain private local sources.
