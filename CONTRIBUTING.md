# Contributing

Bug reports, fixes, documentation and new scooter integrations are welcome. For a larger change, open an issue first so the approach can be discussed.

## Run the app

Install the requirements in [building from source](docs/BUILDING.md), then run from the repository root:

```sh
cd flutter_app
flutter pub get
flutter run
```

Use **Try Demo Mode** to work on the interface without connecting to a scooter.

## Report a bug

Include the app version, phone/OS, steps to reproduce, expected behavior and what happened. For Bluetooth problems, include the scooter model, firmware and active protocol/GATT layout if known. Review [diagnostic captures](docs/ble/CAPTURE_GUIDE.md) before attaching logs.

## Make a change

Work on a focused branch and keep the pull request small enough to review. Describe the problem and the resulting behavior. Update the relevant docs when behavior changes, and add tests for meaningful parsing, state, persistence or lifecycle changes.

Keep protocol encoding out of screens. Preserve reported values until the relevant response arrives. Comments should explain non-obvious decisions and point to existing documents.

## Checks

Run these commands from `flutter_app/`:

```sh
dart format --output=none --set-exit-if-changed lib test packages/platform_features/lib
flutter analyze
flutter test
```

Build the affected platform using the [build instructions](docs/BUILDING.md). Protocol tests should cover known packet vectors, malformed/fragmented input, confirmation, timeouts and cancellation. UI changes should remain usable on small screens, with larger text and Reduce Motion.

State exactly what was tested. For hardware results, record the source commit/app version, scooter model/firmware, phone/OS, GATT layout and the observed outcome. Check setup/permissions, reconnect, telemetry, reported controls, lock/unlock and any tuning you changed. Automated tests and Demo Mode are useful, but do not establish physical scooter compatibility.

## Add scooter support

Follow [adding a BLE protocol](docs/ble/ADDING_A_PROTOCOL.md) for a different wire protocol, or [model records](docs/MODELS.md) for another model using an existing protocol. Keep each protocol in its own directory. Add its communication reference and evidence to [docs/ble](docs/ble/README.md).

## AI assistance

AI-generated and AI-assisted contributions are permitted. You are responsible for understanding, reviewing and testing your contribution, and being able to explain how it works. See the [AI notice](AI_NOTICE.md).

## Pull requests and CI

Summarize the change, checks and device results in the pull request. Include screenshots for visible UI changes. Keep signing files, build output and personal captures out of Git, and retain dependency/artwork license notices.

The [mobile workflow](.github/workflows/flutter-validate.yml) checks formatting, analysis and tests, builds Android APKs, and compiles unsigned iOS bundles on macOS. It runs for pull requests and pushes to `main`; manual runs offer debug or release candidates. Artifacts are for review. Publishing remains a separate maintainer action; see [distribution](docs/BUILDING.md#distributing-builds).
