# Contributing to SATHI

Thanks for helping make academic planning easier across platforms.

1. Fork the repository and create a focused branch.
2. Follow [setup](docs/SETUP.md) using your own Firebase test project and signing identity.
3. Describe the problem or desired behaviour in an issue before a large change.
4. Make the change, run the relevant checks below and include reproducible verification.
5. Open a pull request explaining the before/after behaviour, tests and remaining limitations.

## Checks

On macOS with Xcode selected:

```sh
apple/SyncChecks/run.sh
```

For Android with JDK 21 and the SDK installed:

```sh
cd android
./gradlew assembleDebug lintDebug testDebugUnitTest
```

Device tests are optional locally but required evidence for device-specific fixes. `AndroidRuntimeTest` starts the app and uses disposable local fixtures. Run it on an emulator/test phone with no personal SATHI data. It does not verify Google OAuth or real cloud sync.

## Compatibility matters

- Keep stable session IDs, JSON schemas, account boundaries and existing notes/attendance. Discuss migrations before changing them.
- Never resolve a sync conflict by silently overwriting a device's pending edits.
- Keep disk/network work away from drawing, typing and initial cached UI presentation.
- No production credentials, user exports, personal screenshots or private signing files in patches.
- Prefer native platform conventions and accessible labels, scalable text and adequate contrast.
- Unmarked attendance is unknown, not automatically present. Preserve the distinction between class attendance, fingerprint, sheet and official duty.
- Do not add AI/chat or language-model dependencies as incidental scope.

Small documentation and accessibility fixes are welcome without an issue first. For a security problem, follow [SECURITY.md](SECURITY.md) instead of posting exploit details publicly.

By submitting a contribution, you agree to license that contribution under this project's MIT License. Be respectful: critique the code, explain tradeoffs and avoid harassment or personal attacks.
