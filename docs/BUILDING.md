# Building from source

Run the commands below from `flutter_app/`. See [Contributing](../CONTRIBUTING.md#checks) for formatting, analysis and tests.

## Android

Use Flutter 3.47.0 / Dart 3.13.0, JDK 21 and Android SDK 37. The project uses Android Gradle Plugin 9.1.1, Gradle 9.3.1, compile SDK 37 and target SDK 36. The minimum supported Android version is Android 7.0 / API 24.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --split-per-abi
```

Debug APKs are under `build/app/outputs/flutter-apk/`. Use `app-arm64-v8a-debug.apk` on a typical modern Android phone and `app-x86_64-debug.apk` in the Android emulator. These use development signing. Local release builds are unsigned. The GitHub Actions release job signs the Android preview for direct downloads.

For Android hot reload with `flutter run`, select the Original icon first. Flutter 3.47 discovers a real enabled default launcher activity but does not discover activity aliases. A normal installed app can use any icon preset.

## iOS with Xcode

The iOS runner targets iOS 15 or newer and declares Bluetooth access in `ios/Runner/Info.plist`. All selected iOS plugins, including the local `packages/platform_features` bridge, include Swift Package Manager manifests. The bridge supplies foreground phone speed and bundled icon preset switching; see [personalization](PERSONALIZATION.md). A connected iPhone is not required to compile an unsigned app:

iOS authorization is requested by CoreBluetooth when an explicit scan/connect initializes the BLE plugin. It does not depend on permission-handler's SwiftPM permission flags; that package handles the Android permission flow.

```bash
flutter pub get
flutter build ios --debug --no-codesign
```

Signing, installation and physical Bluetooth validation are separate steps. No Apple account, signing identity, provisioning profile or device registration is stored in this project.

## iOS on Windows with xcross

The installed xtool is useful for SwiftPM projects; this Flutter project uses [xcross](https://github.com/arxdeus/xcross) for Flutter engine, plugin and runner compilation. Its SDK/compiler setup can build without a connected iPhone. Device deployment still needs the owner's Apple authentication and a connected, trusted device; xcross's launcher requires iOS 17 or newer.

Run from **Developer PowerShell for Visual Studio**, using the x64 host tools. Select your existing xcross configuration through `XCROSS_CONFIG`. It should point to the Flutter SDK, Swift 6.4.1 toolchain, LLVM and an extracted Darwin SDK. Do not copy that machine-specific file or Apple SDK into Git.

The local xcross 2.0.6 tool needs workarounds for nested plugin framework paths, Swift build-plan paths, serial Windows Swift compilation and app icon packaging. Windows has no `actool`, and upstream skips the main asset catalogue. Our pinned patch copies the primary and three alternate raster icon sets into the bundle and declares all four iPhone/iPad presets in `Info.plist` before signing. Xcode continues using the original asset catalogue. The helpers keep tool changes inside ignored build folders:

```powershell
$env:XCROSS_CONFIG = 'C:\path\to\your\xcross\config.yaml'
.\tool\prepare_xcross.ps1
.\tool\build_ios.ps1 -Xcross "$PWD\build\xcross-local\bundle\bin\xcross.exe"
```

`prepare_xcross.ps1` fetches the pinned xcross 2.0.6 source at `c28c6bc4a5a3e64888a1303ede777be49f34390b`, applies the checked-in patches and compiles a local tool. It leaves the installed xcross/xtool executables unchanged. The patched plan reader still rejects invalid iOS header paths; it excludes host compilation commands and normalizes Windows extended path prefixes. The deployment patch preserves existing Apple development certificates when no signing slot is available, instead of revoking them automatically.

`build_ios.ps1` defaults to the patched local executable. It temporarily copies the affected packages into `build/xcross-plugin-overrides`, corrects their Swift-only framework paths, then restores the normal dependency resolution in `finally`. It does not modify the shared Pub cache. Its default build creates an unsigned IPA without contacting Apple for signing; add `-Mode release -Deploy` to sign, install and launch on a connected trusted iPhone using the owner's existing xcross authentication. It also exposes the installed Windows Swift runtime/manifest libraries for host manifest execution. Never commit `pubspec_overrides.yaml`, tool caches, Apple SDKs, credentials, private keys or provisioning files.

The helper forwards the version and build number from `pubspec.yaml` for both build and deployment, so stale generated Xcode settings cannot give a new preview the previous build number. Python 3 verifies all four presets' icon declarations, dimensions, opaque RGB content, foreground location permission and version metadata. The Windows Swift patch uses one compilation job to avoid Swift 6.4.1 module-cache crashes. Custom iOS native features must stay in registered plugins: xcross generates its own runner instead of compiling arbitrary files in `ios/Runner/`. To check an exported IPA independently:

```powershell
$appVersion = ((Select-String -Path pubspec.yaml -Pattern '^version:').Line -replace '^version:\s*', '').Trim() -split '\+'
python tool/verify_ios_bundle.py build/xcross-ios/escooter_control.ipa --version $appVersion[0] --build $appVersion[1]
```

If a build fails, the helper reports the compiler diagnostics. A successful source build is not evidence that an iPhone has run or connected to a scooter.

The project uses a team-prefixed development bundle identifier when xcross signs a device build. This keeps test installations in the signing team's namespace without storing its account or team identifier in the project. Development signing and the phone's developer-trust confirmation are separate from compilation. Trust is completed on the phone in Settings → General → VPN & Device Management. An AOT release build can then open normally without an attached debugger; it must be signed again when its provisioning profile expires.

The xcross patches retain their upstream AGPL-3.0 license and attribution; see [third-party notices](../THIRD_PARTY_NOTICES.md). See [distributing builds](#distributing-builds) before sharing a release.

Physical iPhone installation and the Demo Mode dashboard were verified on iOS 26.6.1 on 2026-10-20. The screenshot and deployment notes are kept in the local review artifacts, outside Git. Scooter Bluetooth operation on iOS remains unverified.

## Distributing builds

1. Update the version/build in `pubspec.yaml` and run the relevant checks and builds for the reviewed source commit.
2. Verify the package ID, version, icon and permissions. Test on the intended phone/scooter and record model, firmware, OS, controls tested and remaining limitations.
3. Keep signing material outside Git. Android previews on GitHub Releases use the dedicated Escooter Next signing key; Android debug APKs use a separate development key. An unsigned iOS build needs an Apple signing identity and provisioning before installation. Use the standard Xcode archive/export process for App Store distribution.
4. For a stable release, review device results and known issues, and include the source commit, signing status, and artifact hashes in the release notes.

The [mobile workflow](../.github/workflows/flutter-validate.yml) builds Android and unsigned iOS candidates for each commit in a branch push (up to GitHub Actions’ 256-commit matrix limit). It also builds the proposed merge for pull requests. Artifact names include the commit SHA. Pushes to `main` and manual runs on `main` build a universal Android APK, sign and verify it in the `android-release` environment, and publish it with a SHA-256 checksum on [GitHub Releases](https://github.com/DevCatSon/EscooterNext/releases). Other branches and pull requests upload debug Android builds. iOS bundles remain unsigned and are archived before upload to preserve their contents and permissions.

Retain the app and dependency licenses, including the separately licensed xcross patches in [third-party notices](../THIRD_PARTY_NOTICES.md). Keep signing identities, profiles, Apple authentication, SDKs and local build caches outside source control.
