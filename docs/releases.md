# Releasing Warrant Book

## Current state (v0.1.0)

- **Android:** CI builds a release-mode APK signed with the repo-owned
  **preview keystore** (`android/app/warrant_book_preview.jks`) and
  attaches it to the matching GitHub Release tag (`vX.Y.Z`). The
  keystore password is the committed default (`warrant-book-preview`)
  and is also overridable via the `WB_KEYSTORE_PASSWORD` /
  `WB_KEY_PASSWORD` env vars in Gradle.
- **iOS:** CI builds the app for the **iOS simulator** (unsigned,
  unsigned builds only — see `ios-simulator-build` job). There is no
  published iOS build; TestFlight requires owner-side signing (below).

The preview signature is **not** suitable for Google Play or any
long-term channel: Android requires a stable upload key, and anyone
with the repo can produce APKs carrying this signature. Treat every
v0.x APK as a preview artifact.

## Building locally

```bash
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-*-release.apk
```

The host architecture matters: the Android tooling ships an x86-64
`aapt2`, so release APK builds only work on x86-64 hosts (the CI
`ubuntu-24.04` runners qualify).

## Swapping in a real release keystore

1. Generate a private keystore (keep it out of the repo, back it up
   off-site; losing it means losing the app signing identity):

   ```bash
   keytool -genkeypair -v -keystore release.jks -storetype PKCS12 \
     -keyalg RSA -keysize 2048 -validity 10000 -alias warrant-book
   ```

2. Store it base64-encoded in a repo secret named `RELEASE_KEYSTORE`,
   plus `RELEASE_KEYSTORE_PASSWORD` and `RELEASE_KEY_PASSWORD`
   secrets.

3. Point `android/app/build.gradle.kts`'s `preview` signing config at
   a CI-materialized file when the secrets are present (the CI
   `android-release-apk` job writes `$RUNNER_TEMP/release.jks` from the
   secret and exports the password env vars), or switch the
   `storeFile` path in a follow-up PR.

4. Google Play requires the upload key to be registered with Play App
   Signing; that step is owner-side and happens in Play Console.

## iOS: TestFlight is an owner-side signing task

No published iOS build exists and none is claimed. To ship to
TestFlight you need an Apple Developer account; the owner-side steps
are:

1. Open `ios/Runner.xcworkspace` on a Mac with the matching
   provisioning profile for bundle id `com.toollab.warrantBook`.
2. Set signing to the team's distribution certificate and build:
   `flutter build ipa --release` (produces
   `build/ios/ipa/warrant_book.ipa`).
3. Upload the IPA via Transporter or `xcrun altool`/`xcodegen`-free
   `xcrun iTNS` upload, then distribute through App Store Connect to
   TestFlight.

CI deliberately only compiles the simulator target (no signing
identities are available on public runners, and none are configured).

## Versioning

- `pubspec.yaml` `version:` is the single source of truth; Flutter
  injects it into Android (`versionName`/`versionCode`) and iOS
  (`CFBundleShortVersionString`/`CFBundleVersion`).
- Tag format: `vX.Y.Z` matching the pubspec version. The
  `android-release-apk` job publishes a release for the tag on
  pushes of `v*` refs from `main`; a mismatch between tag and pubspec
  fails the job.

## Google Play Data Safety & Apple privacy labels

Both declarations are drafted in [docs/privacy-labels.md](privacy-labels.md)
and state zero data collection. Submit them verbatim in Play Console /
App Store Connect when using the store forms.
