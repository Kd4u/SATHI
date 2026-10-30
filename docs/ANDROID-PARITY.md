# Native Android client

Android 10 and later; Android 13 tested on a OnePlus Nord. The client uses native Material 3 Views, not MUI's React components or a web view. Android 12+ can use wallpaper-derived dynamic colours; older devices use a brand palette. Five preset themes and manual accent colours remain available. Phone bottom navigation becomes a navigation rail on larger screens.

## Shared behaviour

- Google account sign-in, account-scoped local files, Firestore snapshot protocol and background/manual sync use the same record keys as Apple.
- Timetable import retains source lecture IDs. Manual review, slot correction, elective/section selection and supplementary programme workbooks are available. A new semester archives the previous one.
- Today merges classes and custom activities, including overlapping events. Classes and activities can be rescheduled. Dashboard lecture tiles retain their original numbering.
- OD, attendance, fingerprint and signed-sheet confirmations use shared proof records. A first Android proof tap includes the fields required by Swift's decoder. Notification proof actions queue a network sync.
- Notebook shelf, cover/paper choices, page insertion, duplication, deletion, typing, native pen/eraser, zoom, image/shape layers and PDF sharing are available. Documents retain unknown fields and original Apple drawing data.

## Platform equivalents and limits

Android countdown notifications and notification actions replace ActivityKit/Dynamic Island. Notification channels expose sound/vibration controls to the OS. Alarms and background sync are subject to Android battery restrictions; they are not a guarantee of exact delivery while the app is suspended. No permanent foreground service is used. Home Screen widgets resize between today and three-day layouts; launcher widget stacking depends on the launcher. Shortcuts open Today, Notebooks and Add activity.

Apple PencilKit's binary drawing format is not editable by Android Canvas. Android preserves those bytes and displays an explanation; other notebook layers remain available. Android ink is stored as a transparent image layer in the existing shared document schema, which Apple can display. PDF export refuses to silently omit Apple-only ink when a rendered preview is unavailable. This is not full cross-platform vector-ink editing.

Menu/laundry attachments are local to each device. They use Android's file picker and an installed viewer for opening images/PDFs. Production Firebase configuration and release signing keys are ignored private files.

## Verification

Run `./gradlew assembleRelease lintRelease testReleaseUnitTest assembleDebugAndroidTest` with an SDK/JDK configured. Device instrumentation checks parser/snapshot compatibility, atomic persistence, native view rendering and portable ink/eraser behaviour without changing account attendance. Live cloud propagation must additionally be checked with the same Google account on two devices; a passing build alone does not establish it.
