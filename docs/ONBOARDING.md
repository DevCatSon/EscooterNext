# Setup and Bluetooth permissions

The setup flow is implemented in [connect_screen.dart](../flutter_app/lib/ui/connect_screen.dart).

## Real connection

1. **Prepare:** opens automatically on first launch. Switch on the scooter and keep it nearby. Setup can be closed using the close icon, or Demo Mode opened, without Bluetooth access. There is no separate Not now button. Its presentation is remembered locally; dismissing it or using Demo Mode does not mark scooter setup complete.
2. **Connect:** explicitly select **Find my scooter** to request the applicable system permission and begin discovery. Select an actual result, choose an integration if necessary, and wait for connection setup.
3. **Name:** after the first real pairing, choose a scooter name and select **Save name**. Blank names cannot be saved. The nickname is separate from the Bluetooth identity used for reconnect.
4. **Ready:** after the connection and naming steps succeed, **Open dashboard** returns to the vehicle. Cancelling an in-flight operation cannot later show success.

After a successful real connection, the device is saved. First-time setup completes when the scooter name is saved; an unfinished naming step resumes on a later launch. Storage failures keep that step available for retry. Later launches skip the introduction and reconnect to that saved device when **Settings → Auto reconnect** is enabled (the default). Existing installations with a saved device are treated as already set up. First launch without a saved device does not initialize Bluetooth until **Find my scooter** is selected.

Reconnect runs on launch, on returning to the foreground, or after an unexpected link loss. Failed attempts retry after 2, 5, 10, 20 and 30 seconds, then stop until another foreground session or explicit action. Backgrounding cancels scheduled retries and unfinished automatic attempts; an already connected session is left to the platform. **Disconnect**, **Cancel reconnect**, **Forget saved scooter** and Demo Mode suppress retries for the current session. A new explicit connection or re-enabling Auto reconnect permits them again. Auto reconnect can be disabled persistently in Settings. Each attempt still requires the normal permissions and a recognizable scooter response; a Bluetooth link alone does not complete setup.

## Permission behavior

| Platform | Request and handling |
| --- | --- |
| Android 12+ | Nearby-device Bluetooth scan/connect permission |
| Android 7–11 | Location permission/services required by Android's BLE discovery APIs; the app does not collect geographic coordinates |
| iOS | CoreBluetooth requests Bluetooth access when the BLE plugin is initialized for discovery/connection, including enabled reconnect to a previously saved scooter |

On Android, a plugin observer can replay the pre-grant unauthorized state just after the system grants access. The transport waits for the updated ready state instead of treating that replay as a fresh denial. iOS authorization denial remains actionable. Errors stay visible with retry/settings guidance; a failed permission check never reports a scooter as connected.

## Demo Mode

**Try Demo Mode** opens a local simulated vehicle without permissions, scanning or radio writes. It does not save a fake device identity or add real-model observations. The same UI reads a separate simulated telemetry session, visibly identified as a demo. Exiting Demo Mode resets connection-scoped state and returns to the connection home, clearing the selected tab and pushed settings pages. It does not automatically connect to a physical scooter.

## Units

**Settings → Speed & distance** changes the scooter's km/mile setting and waits for its reported confirmation. **Settings → Temperature** saves a local Celsius/Fahrenheit display preference; code-16 Celsius readings are converted only for display. Unknown values remain dashes. Unconfirmed raw BMS temperatures are left raw.

## Phone speed and personalization

[Settings → Speed calculation](PERSONALIZATION.md) offers Scooter, Phone and Mixed speed. Phone/Mixed request foreground location only when explicitly selected; they do not change Bluetooth pairing permissions. GPS runs only during a real ready connection in the foreground. Theme settings and the four bundled app icon presets are described in the same guide.

## Accessibility

Setup uses platform navigation, brief optional state transitions and explicit progress/error text. Reduce Motion suppresses custom movement and repeating discovery animation. Small screens and larger text retain usable controls. See the [design research](../flutter_app/design/MOTION_SETUP.md) and [testing guidance](../CONTRIBUTING.md#checks).

## Find and dashboard readings

**Find** is a momentary action: each press sends one locate request (`52`, payload `[1]`). The scooter determines how long it sounds. The button does not latch into an on/off state or send background repeats.

Dashboard battery, speed, trip, total distance and voltage use brief numeric transitions. Stored telemetry and accessibility values always retain the actual latest report. First readings, missing values, unit changes and Reduce Motion update immediately.
