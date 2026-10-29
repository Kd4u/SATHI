# Build and run

## Firebase for your fork

1. Create a Firebase project. Enable Google in Authentication → Sign-in method and choose a support email.
2. Create a Cloud Firestore database and deploy the per-account rules in `firebase/firestore.rules` to **your** project. Do not use public test rules.
3. Register an Apple app and an Android app with identifiers matching your build. The source defaults are `com.karandeepsinghpersonalteam.SWIFT` and `com.karandeep.sathi`; independent forks should choose their own identifiers.
4. Download the Apple `GoogleService-Info.plist` and Android `google-services.json`. Keep both untracked.
5. Run the configuration helpers:

```sh
python3 scripts/configure_apple.py /path/to/GoogleService-Info.plist
python3 scripts/configure_android.py /path/to/google-services.json
```

The Apple helper also sets the reversed OAuth callback in `apple/AppInfo.plist`, which Git will show as a local change. Do not commit its production values. Android's helper extracts the app matching the Gradle package name, including a **web/server OAuth client ID**, into an ignored asset file. Register the SHA-1 of the key used to sign your Android build in Firebase before downloading the Android configuration.

When changing Apple bundle identifiers, update the app/extension build settings and the matching keychain/background-task identifiers in `AppInfo.plist`, entitlements and Swift shared/background files. Keep the app and widget access groups aligned. Changing IDs on an existing installation can also change access to its saved/keychain data; do this only on your development copy.

## iPhone, iPad and Mac

- macOS with **Xcode 27** for the currently configured deployment targets.
- The source currently targets iOS/iPadOS 27 and macOS 26.7.1. Lowering these targets requires API-availability review; older Apple OS support is a roadmap item.
- Swift Package Manager resolves Firebase, Google Sign-In and CoreXLSX automatically. The lockfile is checked in.

Open `apple/SWIFT.xcodeproj`, select the **SWIFT** scheme and choose a simulator, Mac or connected device. Under Signing & Capabilities choose your own team for both the app and widget target, configure your Firebase files, then Run.

The public project has no maintainer signing team. A free Apple Personal Team is suitable for personal development, with Apple's provisioning limits; it does not provide App Store/TestFlight distribution. A copied Mac `.app` needs its frameworks embedded and a valid configuration/signature for its capabilities. This repo does not ship the maintainer's Apple-signed binary or private renewal scripts.

Domain checks do not need a signed build or live Firebase account:

```sh
apple/SyncChecks/run.sh
```

If Xcode is not the selected developer directory, set `DEVELOPER_DIR` to your own Xcode installation for that command.

## Android 10 and later

Install Android Studio or the official Android SDK command-line tools, JDK 21 and SDK components `platforms;android-35`, `build-tools;35.0.0` and `platform-tools`. Point Android Studio to `android/`, or create an ignored `android/local.properties` with `sdk.dir=/your/android/sdk`.

```sh
cd android
./gradlew assembleDebug lintDebug testDebugUnitTest
```

The debug APK is `app/build/outputs/apk/debug/app-debug.apk`. Configure Firebase before signing in. A source checkout without Firebase configuration displays setup instructions rather than connecting to the maintainer's backend.

For USB installation, enable Developer options → USB debugging on your phone and approve the computer. Then:

```sh
adb devices
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Use `-s YOUR_DEVICE_SERIAL` when more than one device is connected. `-r` replaces the same-package, same-signature installation while retaining app data. An APK signed with your key cannot update a maintainer-signed APK; do not uninstall a personal copy containing unsynced data just to work around a signature mismatch.

### Release signing

Create your own Android signing key and keep it private. Copy `android/signing.properties.example` to ignored `android/signing.properties` and fill in its values. The release build uses those local credentials:

```sh
./gradlew assembleRelease
```

Without a signing configuration, Gradle produces an **unsigned** release APK. Do not distribute that file as an installable release. Signed Android APKs do not have the Apple Personal Team seven-day renewal limit. Keep the same key and increment `versionCode` for updates.

## Test a complete sync flow

Use a separate test Google account, never a real class's exported records as a fixture.

1. Import a small synthetic timetable on device A and sync.
2. Sign in with the same account on B and restore/sync without importing again.
3. Record attendance on A; sync A, then B; confirm the same class status.
4. Edit different records offline on A and B; sync and verify both changes survive.
5. Edit the same record on both; verify the conflict is reported and neither draft disappears.
6. Create/edit a typed note; sync and verify the content and account boundary.
7. Sign in with a different account and confirm the original account's private data is not shown.

Background jobs, widgets, notifications, Google account chooser and Pencil hardware also need real-device checks. Unit tests cannot establish those behaviours.
