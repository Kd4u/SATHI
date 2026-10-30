# Timetable review and everyday tools

## Apple

- **Check my timetable** is available from subject review and Settings. Switch Day/7 days, tap predicted classes to include/exclude them, edit class name/date/slot/teacher/section, correct an entire time slot, or promote an event that was actually a class. Saving is explicit and backs up the original report. Manual selected IDs are scoped to the semester and included in account preferences.
- **Whole timetable** shows every uploaded subject, with programme and section selectors. Missing programme schedules can be uploaded alongside the current schedule. Extra imported classes have namespaced IDs; existing class IDs, selections and attendance are retained. MBA/DBM/DBAI/HHM require meaningful worksheet labels or an explicit programme selection for an additional upload.
- Onboarding asks semester/course/section before the first upload. Semesters 1–3 include all courses for the chosen section; semesters 4–6 retain elective/section selection. Profile name/course and derived year are in Settings. End-of-semester import is exposed on Today and Settings after the source schedule/exams finish.
- Fingerprint/sheet crosschecking is optional and defaults off. With it on, class cards expose one-tap proof controls. With it off, ordinary attendance records are used without the proof mismatch penalty. Existing proof records remain stored.
- Subject dashboards open numbered lecture tiles. Numbers are derived from the selected source timetable, so a reschedule override retains the lecture number. Associated guest activities appear as G tiles, without shifting ordinary numbers. Tiles support attendance/OD and rescheduling. Added activities include quiz, guest lecture, presentation, placement, workshop and meeting.
- Classes and activities retain overlapping entries. Rescheduling preserves class IDs and uses private semester-scoped overrides for imported events. Custom events retain their UUIDs.
- The Today summary is compact, and date browsing no longer shows an unrelated global next-class strip. Calendar has a week strip plus a compact monthly option. Past semesters have explicit navigation; archives retain complete imported reports, selected session IDs, attendance, proofs, edits and custom events.
- Mess menu and laundry buttons are optional. They open a locally saved photo/PDF and an Edit/replace action. These documents are account-local on the importing device and are not automatically uploaded to cloud storage.

## Notebooks

Normal mode retains paper, ink and typing. Pages start centred in the viewport. Edit Pages exposes insertion, duplication and soft removal. The iPad eraser accepts pencil or finger input and hides the native picker while explicitly erasing so it does not restore the previous ink tool.

**Pro canvas** is an explicit mode on the same page, not a separate unsaved editor. It adds image/PNG imports, text elements, rectangles/ellipses, line/arrow diagram elements, drag/resize, colour/size/bold controls, opacity, layer ordering, duplicate, and element/text clipboard actions. Ink colour/width/opacity are available alongside native pen/highlighter tools. Existing text objects remain native editable text. Pro content persists in the page document, follows existing chunked asset sync and is included in PDF export. Normal mode displays the content without the editing chrome. PDF export is checked with a rasterized translucent shape and text fixture.

Use the updated build on every Apple device before editing Pro pages: older Apple builds do not preserve the new layer fields when saving a page. Quit and reopen an already-running Mac copy after installing the update.

This is a basic native canvas, not a Canva integration: automatic connector routing/snapping, grouped transforms, arbitrary font libraries, rich document imports and collaborative live editing are not implemented. Page removal is recoverable through retained assets, not a permanent cloud purge. Direct Apple Pencil feel, eraser behaviour, gesture conflicts, photo-library permissions, hardware keyboard shortcuts and real two-device asset sync still need real-device user verification; unit/build checks are not proof of those interactions.

## Android scope

Android respects the shared semester-scoped manual selected IDs and optional proof-crosscheck preference. It adds more accent colours, Android 12+ wallpaper accents, a translucent rounded navigation bar and the same basic custom activity types. The Android app still uses its existing importer and typed-note editor. The Apple manual-review UI, Pro canvas, local campus-document UI and full history navigation have not been ported to Android in this update. Unknown Apple page fields remain preserved by its JSON editing path.

## Verification

Run `apple/SyncChecks/run.sh` and Android `assembleDebug lintDebug testDebugUnitTest`. New checks cover old/new page JSON, image bytes/opacity/layer order, optional preferences, manual ID precedence across clients and opt-in penalties. Signed Apple builds must also succeed before installation. Do not delete accounts, notes or previous semesters to resolve a build or migration issue.
