# Architecture

SATHI has two native clients and one compatible Firebase data contract. SwiftUI code is in `apple/`; Java Android Views code is in `android/`. There is no shared UI runtime and no client-side admin credential.

## Local-first flow

Clients scope saved files to the authenticated Firebase UID rather than sharing a global cache between accounts. Local writes use atomic replacement. A cached timetable is shown immediately; network requests and workbook parsing should not block drawing, typing or initial presentation.

Clients check the account snapshot once on launch without blocking the cached UI. Completed imports and onboarding selections upload immediately; ordinary edits use explicit Sync or roughly hourly opportunities, subject to platform scheduling and battery limits. No real-time Firestore listener is used for the main timetable.

## Timetable snapshot

`users/{uid}/sathi/snapshot` has `schema: 1`, a Firestore bytes `payload` and an `updatedAt` server timestamp. The payload is a JSON object containing `records`, a map of keys to **base64-encoded JSON bytes**, matching Swift Codable `Data`.

Keys include `timetable`, `selection`, `attendance:{id}`, `event:{uuid}`, `study:preferences`, `study:semesters`, `study:proof:{id}` and `study:override:{id}`. Preserve unknown keys byte-for-byte. Session IDs derived from worksheet/cell/index allow attendance to refer to the same imported class on both platforms. Swift dates use seconds from 2001-01-01 unless the model specifies a date string.

Sync uses a three-way comparison between a saved baseline, the local snapshot and the remote snapshot, inside a Firestore transaction. Independent edits merge; divergent changes to the same key produce a conflict. JSON record comparisons ignore object-key order and formatting differences across clients. An explicit conflict choice selects this device or cloud for conflicting records. A timetable conflict also selects its associated subject selection, semester index and study preferences as one bundle, preventing an accepted timetable from showing zero classes under another import’s selection. Both snapshots and the baseline are saved in private SyncConflictBackups before a resolving transaction writes; independent edits are retained. In-flight edits still use the normal conflict-protected merge. Android also merges edits made while the request was running into the local result, so a network response cannot discard fresh local typing/changes.

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
