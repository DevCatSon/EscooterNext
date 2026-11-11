# Speed, themes and app icons

## Dashboard speed

**Settings → Speed calculation** has three choices. Scooter reported speed is the default and preserves the scooter's last reported wheel-speed value. Phone reported speed uses the operating system's location speed estimate and shows a dash without a usable reading. Mixed combines both sources when they are fresh and agree; it falls back to the available source if one is missing. Demo Mode always uses simulated speed. The dashboard tile is always labelled **Live speed**, including compact layouts; source and fallback details appear in Speed calculation settings.

Phone speed requires user-approved foreground location access. Android requests Fine and Coarse together and requires Precise Location; on iPhone select While Using the App and enable Precise Location for useful readings. Selecting Phone or Mixed explicitly can request permission. Restoring a saved choice never opens a permission prompt automatically. Collection runs only with a real ready scooter connection while the app is in the foreground; pausing, disconnecting, entering Demo Mode or selecting Scooter stops it. No background location entitlement or service is used.

Native Android LocationManager/Core Location supply speed in metres per second. The app converts to km/h internally and uses the scooter's unit preference for display. Coordinates never cross the native channel, enter diagnostic logs or get saved. Phone speed changes the dashboard display only: BLE frames, speed limits, trip distance, odometer and battery calculations retain their existing meanings.

### Mixed estimate and quality checks

A phone reading must be finite and nonnegative, at most three seconds old (including its native age), with horizontal accuracy at most 25 metres and reported speed uncertainty at most 1.5 m/s. When speed uncertainty is unavailable, horizontal accuracy must be at most 15 metres. A valid stationary zero is retained. Mixed also expires scooter speed after three seconds without a speed-bearing packet; unrelated packets do not refresh it.

The scooter protocol provides no speed uncertainty. The estimator assumes a scooter uncertainty of `max(1 km/h, 5% of speed)` and a phone uncertainty of `max(0.5 km/h, reported uncertainty × 3.6)`, defaulting to 1.5 m/s when unavailable. It uses inverse-variance weighting with the phone share limited to 25–85%. These are application heuristics, not measured sensor calibration. If disagreement exceeds `max(8 km/h, three times the combined uncertainty)`, the accepted phone reading takes precedence instead of averaging conflicting values. The settings screen shows the current source/fallback status.

Mixed is an estimate. GPS can lag during acceleration and behave poorly indoors or among tall buildings; wheel readings can differ with tyre size, pressure or slip. Combining them does not guarantee greater accuracy in every situation. Outdoor comparison against an independent reference is still required for calibration claims.

## Themes

**Settings → Theme** offers Ocean, Mint, Sunset, Violet, Graphite and Custom. Custom accepts a six-digit RGB hex color. Material color generation builds matching light/dark palettes; **Appearance** independently selects System, Light or Dark. The selected color tints the full-screen gradient, cards, control rows, input surfaces, dashboard and navigation bar. Background and dashboard gradients interpolate during theme changes, and text contrast is checked for both light/dark palettes and extreme custom colors. Driving mode colors retain their meaning. Theme changes preserve navigation and do not make every telemetry update rebuild the app shell.

## Installed app icon presets

**Settings → App icon** offers Original, Material 3, Midnight and Volt, using the project's wheel/bolt artwork. Android uses a default launcher entry and three activity aliases; Android 13+ changes their enabled states atomically. A small default entry forwards launch arguments to the always-enabled Flutter activity, keeping its engine independent of icon selection. Older Android enables the new alias before disabling the previous one. Launcher refresh timing depends on the phone. Supported Android launchers can also use the provided monochrome themed icon.

On iPhone, UIKit can switch only between icons bundled with the app. The app checks support, awaits the system result and reads the actual current icon rather than claiming success early. iOS can display its own confirmation. Both Xcode asset settings and Windows bundle packaging include all four presets for iPhone/iPad.

## Native implementation and verification

Android code lives in `MainActivity.kt` and `PlatformFeatures.kt`. iOS code lives in the local `packages/platform_features` SwiftPM Flutter plugin. It must be a plugin because xcross 2.0.6 generates its own runner and does not compile arbitrary Runner Swift sources. Xcode and xcross both register the plugin through Flutter's generated registration.

The Windows helpers stage plugin manifests in ignored build storage. The pinned Swift workaround serializes Windows plugin compilation to avoid Swift 6.4.1 implicit Clang module cache crashes. The icon verifier checks all four presets, version metadata and foreground location declarations. Compilation and bundle checks do not replace device testing for permission transitions, GPS quality, launcher changes or iOS system dialogs.

## Platform references

- [Apple: CLLocation speed](https://developer.apple.com/documentation/corelocation/cllocation/speed)
- [Apple: location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
- [Android: Location speed and accuracy](https://developer.android.com/reference/android/location/Location)
- [Android: LocationManager](https://developer.android.com/reference/android/location/LocationManager)
- [Apple: alternate icon API](https://developer.apple.com/documentation/uikit/uiapplication/setalternateiconname(_:completionhandler:))
- [Apple: configuring app icons](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- [Android: PackageManager component settings](https://developer.android.com/reference/android/content/pm/PackageManager)
