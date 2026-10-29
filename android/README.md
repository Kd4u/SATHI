# Android client

See [Setup](../docs/SETUP.md), [Architecture](../docs/ARCHITECTURE.md) and [Verification](../docs/VERIFICATION.md).

JDK 21, Gradle 8.13, compile/target SDK 35 and minimum SDK 29 (Android 10).
Run `./gradlew assembleDebug lintDebug testDebugUnitTest` after installing the SDK.
Firebase configuration and release signing are local, ignored files; no maintainer signing key is required for contributor builds.

Without Firebase configuration, the app displays developer setup instructions. CI artifacts are development builds, not production-verified releases.
