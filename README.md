# Escooter Next

**Escooter Next** is an open-source replacement for Vicont's scooter companion app, built with Flutter for Android and iOS and maintained by **DevCatSon**.

The aim is to make everyday scooter controls and vehicle data easier to access, without an account. The app connects directly over Bluetooth and stores preferences and scooter records on your phone. Vicont scooters are the current focus; support may expand to other scooter families as their protocols are documented and tested.

## Features

- Dashboard with battery, speed, trip distance, total distance and voltage.
- Headlight, cruise, Kick start, lock and riding modes, where supported.
- Speed-limit selection from 1–31 km/h, subject to the scooter's firmware and region.
- Sensor readings, Celsius/Fahrenheit and speed/distance units.
- Saved scooter, automatic reconnect and a local model catalogue.
- Scooter, phone GPS or mixed dashboard speed.
- Accent themes, custom colors and four bundled app icon presets.
- Light/dark appearance, larger text, screen-reader labels and Reduce Motion.
- Demo Mode to explore the interface without a scooter.

## Compatibility

The app targets **Android 7.0+** and **iOS 15+**. It currently implements the Vicont-family Bluetooth protocol. Other scooter families are not implemented yet.

This is a development preview. Exact-model compatibility and full physical Bluetooth validation remain pending on Android and iOS. Available controls depend on the scooter's firmware, model and region; a local model record cannot unlock firmware restrictions. See the [BLE support reference](docs/ble/README.md) for implementation status and evidence.

This project is independent and is not affiliated with Vicont or other scooter manufacturers.

## Get started

[GitHub Actions builds](https://github.com/DevCatSon/EscooterNext/actions/workflows/flutter-validate.yml) include debug Android APKs and unsigned iOS app bundles. Open a successful run and scroll to **Artifacts**. The [original Android app](https://github.com/DevCatSon/EscooterControl) is kept as a separate legacy project.

Follow [building from source](docs/BUILDING.md) to run the app or create an Android/iOS build. Android APKs are written to `flutter_app/build/app/outputs/flutter-apk/`.

On first launch, choose **Set up scooter** to pair your scooter, or **Try Demo Mode** to explore the app. The [setup guide](docs/ONBOARDING.md) explains permissions, saved scooters and automatic reconnect.

## Documentation

- [Documentation index](docs/README.md)
- [App architecture](docs/ARCHITECTURE.md)
- [Vicont Bluetooth protocol](docs/ble/VICONT.md)
- [Adding another scooter protocol](docs/ble/ADDING_A_PROTOCOL.md)
- [Privacy and local data](docs/PRIVACY.md)

## Contributing

Bug reports, fixes, documentation and scooter protocol findings are welcome. See the [contributing guide](CONTRIBUTING.md) for development checks and the pull-request process.

## License

[MIT](LICENSE). Dependencies and the Windows iOS build-tool patches retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
