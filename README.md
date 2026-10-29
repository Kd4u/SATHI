<p align="center">
  <img src="docs/assets/sathi-icon.png" width="100" alt="SATHI app icon">
</p>

<h1 align="center">SATHI</h1>
<p align="center"><a href="https://github.com/Kd4u/SATHI/actions/workflows/ci.yml"><img src="https://github.com/Kd4u/SATHI/actions/workflows/ci.yml/badge.svg" alt="Source checks"></a></p>
<p align="center">Your timetable, attendance and notes. One academic companion across your devices.</p>
<p align="center">
  <a href="LICENSE">MIT licensed</a> ·
  <a href="CONTRIBUTING.md">Contributions welcome</a> ·
  <a href="docs/SETUP.md">Build it yourself</a> ·
  <a href="docs/ROADMAP.md">Roadmap</a>
</p>

SATHI is a native academic planner for iPhone, iPad, Mac and Android. Import an Excel timetable, choose your section or subjects, record attendance, and keep your schedule and typed notes available across devices through your personal Google account.

**This is an early community MVP.** The Apple app and Android port have different levels of feature coverage. Real Android Google sign-in and two-device cloud sync still need end-to-end verification; passing local compatibility tests is not proof of that integration. Please use a test account and keep a backup when trying new builds.

## What you can do

- **Plan your day:** Today, calendar, classes, campus events and custom events.
- **Import once:** Excel `.xlsx` import with section and subject selection. A compatible cloud account can restore the saved timetable on another device.
- **Track attendance:** record class attendance, fingerprint and sheet confirmation, and official duty. Unmarked classes stay unmarked.
- **Keep notes:** Apple notebooks support typed text and PencilKit drawing. Android supports quick notes and typed text in existing pages while preserving Apple drawing data.
- **Save locally first:** the app opens its saved copy immediately. Cloud sync is explicit or roughly hourly when the operating system permits.
- **Glance at your schedule:** Apple widgets and an Android Home Screen widget use the saved timetable. Taller Android widgets show three days.
- **Make it yours:** dark/light appearance, accent colours and optional reminders.

SATHI does not connect to a college's biometric or official attendance system. Fingerprint and attendance-sheet entries are personal records. Local AI/chat and bundled language models are not part of this project.

## Platform status

| Feature | iPhone / iPad / Mac | Android |
| --- | --- | --- |
| Native app | SwiftUI | Java / Android Views |
| Minimum configured OS | iOS/iPadOS 27; macOS 26.7.1 | Android 10 (API 29) |
| Timetable, calendar and attendance | Implemented | Implemented; local/runtime tests passed |
| Personal Google sign-in and private Firestore data | Implemented | Configured; real sign-in/sync verification pending |
| Typed notes | Implemented | Quick notes and existing notebook text |
| Apple Pencil / PencilKit | Apple platforms where available | Preserved, not rendered or edited |
| New-semester archive/import | Implemented | Initial timetable import; use Apple for semester rollover |
| Widgets | WidgetKit; device checks still needed | Resizable Home Screen widget; manual checks still needed |
| Live Activities / Dynamic Island / Siri | Apple-specific implementation | Not included |

See [verification status](docs/VERIFICATION.md) for exactly what has been tested. Supporting older Apple OS versions and expanding Android parity are open contribution areas.

## Try or build SATHI

Check [Releases](https://github.com/Kd4u/SATHI/releases) for available test builds. Android APKs can be installed directly; Apple builds require your own signing setup. An Apple Personal Team build is not an App Store or TestFlight distribution.

For source builds, start with **[Setup](docs/SETUP.md)**. You will need your own Firebase project and client configuration; the maintainer's backend configuration and signing material are intentionally excluded from source control.

```text
apple/       SwiftUI app, WidgetKit extension, Xcode project and domain checks
android/     Android app, Gradle wrapper, unit and device tests
firebase/    Per-account Firestore security rules and local emulator configuration
scripts/     Firebase configuration helpers and public-source checks
docs/        Setup, architecture, verification and roadmap
```

## Contribute

Start with [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports should include the platform, OS/app version and reproducible steps with private information removed. Pull requests are welcome for accessibility, Android parity, sync tests, widgets, notebook performance and documentation.

Please do not upload real timetables with names or contact details, account exports, passwords, signing keys, authentication tokens or production Firebase configuration. Use synthetic fixtures in tests and screenshots. Report security issues privately through the process in [SECURITY.md](SECURITY.md).

## Screenshots

Actual app captures supplied by the maintainer. The iPhone captures show an earlier installed layout; the latest source may differ.

<p align="center"><img src="docs/assets/screenshots/ipad-today.png" width="800" alt="SATHI on iPad in dark mode, with a sidebar and Today overview"></p>

<table>
  <tr>
    <td><img src="docs/assets/screenshots/iphone-calendar.png" width="240" alt="iPhone calendar with class and event markers"></td>
    <td><img src="docs/assets/screenshots/iphone-semester.png" width="240" alt="iPhone semester setup with first- and second-year choices"></td>
    <td><img src="docs/assets/screenshots/iphone-appearance.png" width="240" alt="Appearance and notification settings on iPhone"></td>
  </tr>
  <tr><td align="center">Calendar</td><td align="center">Semester setup</td><td align="center">Appearance & reminders</td></tr>
</table>

[View the full Mac, iPad and iPhone gallery](docs/GALLERY.md). Android screenshots are welcome once verified on a real build. See [the screenshot checklist](docs/SCREENSHOTS.md) for future contributions.

## License

SATHI source and project-created assets are available under the [MIT License](LICENSE). Third-party SDKs and tools retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
