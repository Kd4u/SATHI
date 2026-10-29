# Verification status

Initial public-source snapshot prepared on 2026-10-29. Results below distinguish the original configured development builds from a contributor's build using their own Firebase/signing setup.

## Confirmed on the configured development build

- Apple Release builds succeeded for Mac and iOS; the app was installed/launched on a Mac and iPad.
- The copied Mac app's embedded-framework dependencies and code signature were checked. Its original development profile still has Apple's free provisioning expiry; no private signature is published here.
- Android Release build and lint completed. Seven JVM compatibility tests passed: wire format, independent/deleted records, conflicts, edits made during sync, attendance penalties/OD, deduplicated exam labels and stable Excel cell IDs.
- The signed Android APK installed on a OnePlus Nord AC2001 running Android 13.
- Three runtime checks passed on that Nord: native activity startup, Android XML/JSON compatibility and atomic local file operations. An Android XML parser incompatibility found during those checks was fixed before the delivered APK.
- The release APK's signing certificate matched the Firebase Android OAuth registration and APK signature verification passed.

## Still requires end-to-end / manual checks

- Android Google sign-in and real two-device Firestore sync with a human test account.
- Complete notebook revision/conflict behaviour across both clients, large libraries and lifecycle changes during typing.
- Widget content/refresh on each real platform and Android widget resizing.
- Reminder delivery with lock screen, battery optimisation, reboot and notification permissions.
- Older Apple OS support and Android 10 runtime coverage. The Android minimum API is 29 and lint API checks passed, but physical testing so far used Android 13; an Android 10 emulator attempt did not establish runtime coverage.
- Accessibility, large text, rotation, tablet layout and real Pencil hardware interactions.
- Independent privacy/security review and automated Firestore rule tests.

The public source removes the maintainer's backend/signing configuration and makes Android signing portable. Public CI exercises local checks and an unsigned/debug Android build, not authentication against a private production project. Do not label a CI artifact as a production-verified app.

## Public contributor copy checked on 2026-10-29

The sanitized Android project built in Debug, passed lint and all seven unit tests without maintainer signing/configuration files. The Apple command-line domain runner passed merge, journal, account isolation, study/attendance, widget/cadence and notebook-foundation checks using the installed Swift toolchain. Public-source scanning passed after excluding private configuration and generated artifacts. These local results do not establish real OAuth/cloud behaviour or hosted CI success.
