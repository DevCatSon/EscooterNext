# Privacy and local data

This describes the current app implementation, not a store certification or a promise about the phone operating system's own services.

## Data used by the app

Bluetooth discovery exposes nearby advertised names, service UUIDs, signal strength, platform device IDs and available manufacturer data. A real connection supplies vehicle telemetry, firmware fields, raw protocol frames and control responses. Android device IDs and iOS opaque UUIDs are kept as local connection identifiers; the app does not convert iOS IDs into MAC addresses.

Flutter preferences store the saved scooter/name, setup presentation/completion, reconnect, temperature-unit and speed-source preferences, appearance and theme colors, per-device model/feature choices, local model definitions and identification observations. The model store is bounded; the frame log keeps up to 240 entries in memory. Data stays in app-local storage unless the user explicitly copies/exports it. App-level encryption or cloud synchronization is not implemented; operating-system backup/storage behavior is controlled separately by the device.

There is no application account, analytics, advertising or app-level network client. Optional Phone/Mixed speed uses Android LocationManager or iOS Core Location while a real scooter is connected and the app is in the foreground. Only speed, accuracy and sample age reach Flutter; coordinates are not stored, logged or transmitted. Selecting these modes explicitly requests foreground location permission. Scooter speed needs no GPS. Older Android BLE APIs separately require Location permission/services for scanning. Permissions are checked for discovery/connection, including enabled automatic reconnect to a saved scooter. A fresh setup introduction does not request them. Demo Mode does not scan, write BLE, replace the saved real scooter or create real-model observations.

App icon selection uses only the four presets bundled with the app and is kept by the operating system. The app does not import or export custom icon images or request photo-library access. See [personalization](PERSONALIZATION.md).

## Exports and removal

Frame/model exports omit the internal database's Bluetooth ID association keys. Advertised names, model names, firmware, timestamps and raw bytes remain, and platform errors or payloads can contain additional identifiers. Exports are not guaranteed anonymous. See the [capture review guide](ble/CAPTURE_GUIDE.md) before posting anything publicly. Copying exports places them on the system clipboard.

**Clear frame log** removes the in-memory diagnostic entries, not the model database. **Forget saved scooter** disconnects and removes that device's saved connection/settings/observation. Reusable user model definitions remain; there is currently no individual-model delete action. Clearing application data or uninstalling removes local application storage subject to the OS's backup/restore behavior; it does not retract previously exported text or public issue attachments.

## Questions

Use repository issues for questions and bug reports, with personal details removed from attachments. Store privacy disclosures should be checked against the actual release and dependencies before submission.
