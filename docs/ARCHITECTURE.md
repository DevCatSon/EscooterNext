# Architecture

## Flutter application

One shared controller coordinates one active scooter connection. Multiple BLE protocol implementations can be registered; this does not mean concurrent connections to several scooters.

```text
Screens / accessible UI components
                 │ semantic actions and observable state
        ScooterController
          ├── ScooterCommands / ScooterModels / ScooterConnection
          ├── ProtocolRegistry → fresh ProtocolSession per connection
          │                       ├── handshake / packet buffering / decoder
          │                       ├── command encoding / relevant confirmation
          │                       └── protocol reactions / local simulation
          ├── ScooterTransport → reactive BLE → Android / CoreBluetooth
          └── Preferences / LocalScooterDatabase → phone-local storage
```

| Source | Responsibility |
| --- | --- |
| [controller](../flutter_app/lib/services/scooter_controller.dart) | Permission timing, discovery, connection epochs, serialized writes, command completion, bounded logs and telemetry notifications |
| [commands](../flutter_app/lib/services/scooter_commands.dart) | Protocol-independent controls and last-reported confirmation behavior |
| [model coordination](../flutter_app/lib/services/scooter_models.dart) | Identification evidence, model matching, per-device defaults/overrides and observations |
| [connection lifecycle](../flutter_app/lib/services/scooter_connection.dart) | Remembered setup, foreground reconnect, bounded retries, manual disconnect and Demo Mode isolation |
| [transport](../flutter_app/lib/services/ble_transport.dart) | Platform permissions, radio lifecycle, discovery, notification subscription and characteristic writes |
| [GATT models/selection](../flutter_app/lib/ble/ble_models.dart) | Deterministic layout selection, UUID normalization and explicit write modes |
| [protocol contract](../flutter_app/lib/integrations/scooter_protocol.dart) | Independent session, request and event interfaces |
| [Vicont integration](../flutter_app/lib/integrations/vicont/vicont_protocol.dart) | Current production protocol, with separate codec/commands/decoder |
| [catalogue](../flutter_app/lib/catalog/scooter_catalog.dart) | Evidence-based matching and ambiguity handling |
| [local database](../flutter_app/lib/catalog/local_scooter_database.dart) | Bounded model, observation and per-device settings persistence |
| [telemetry](../flutter_app/lib/core/telemetry.dart) | Immutable nullable last-reported readings |
| [app shell](../flutter_app/lib/app.dart) | Navigation, theme, messages and app-wide confirmed-lock overlay |

## Connection lifecycle

1. First launch presents setup without touching Bluetooth. Explicit discovery/connect starts permission handling; later launches can reconnect to a saved scooter when enabled. Demo Mode suppresses physical connections.
2. Discovery collects advertisements. The registry chooses a supported integration; ambiguous/unknown choices need an explicit integration selection rather than a speculative handshake.
3. Connecting reserves a session before yielding. Epoch/generation checks prevent cancelled or old callbacks from changing a newer session.
4. The transport connects, discovers GATT, selects the integration's notification/write layout and subscribes. The integration may specify a notification delay.
5. The controller serializes the integration's literal handshake and, when the profile requires it, awaits a recognizable response. Only then does it mark the link ready and persist the successful device identity.
6. The protocol buffers/decode notifications, updates nullable readings and emits confirmation/identity events. Version queries refine identification; local model matching changes feature defaults and artwork.
7. Disconnect invalidates outstanding work, completes pending requests as unsuccessful, clears connection-scoped telemetry, cancels subscriptions and discards the protocol session.

Connection profiles can request an Android MTU, notification/write delays and an initial protocol response. Vicont requests MTU 255 and requires a recognizable reply before setup succeeds. Automatic writes prefer an ATT response on iOS and no response on Android, within advertised characteristic capabilities. Raw notification boundaries and the selected GATT properties are retained in diagnostics; see the [connection audit](ble/CONNECTION_AUDIT.md).

## Control and performance rules

UI code sends semantic actions, never constructed BLE frames. A successful platform write is distinct from a relevant protocol reply, and an acknowledgement may be weaker than physical state confirmation. [Vicont](ble/VICONT.md) records those distinctions per command.

Flutter retains reported switch/setting values while pending and blocks duplicate requests. Unconfirmed start mode remains at the prior value. Lock overlays cover pushed routes and wait for reported unlock. Local visibility overrides cannot add an unsupported protocol action or bypass scooter restrictions.

PhoneSpeedMonitor manages foreground native speed samples separately from BLE telemetry. The display estimator leaves reported telemetry unchanged. Native foreground location and icon actions use a method/event channel; iOS registers these through the local SwiftPM platform_features plugin, Android through MainActivity. See [personalization](PERSONALIZATION.md) for source selection and platform constraints.

The app shell listens for appearance and palette changes separately from live data. Telemetry refreshes the current screen and lock overlay without reconstructing `MaterialApp` and its themes. Navigation state remains intact during data updates. Reported lock changes bypass the ordinary telemetry repaint throttle, including locks initiated outside the app.

Transport setup reserves its generation before awaiting cleanup. Cancelling a pending native connection completes its waiter immediately; failed setup releases its own subscription, and an obsolete attempt cannot close its replacement. Scan cancellation also checks its original epoch after awaiting the platform, so a delayed cancellation cannot reset a newer scan.

Controller disconnect cleanup checks that it still owns the session after scan cancellation before disconnecting the transport. Entering Demo Mode also checks ownership after cleanup, so a cancelled demo start cannot replace a newer real connection or undo a later disconnect.

Writes are queued with session cancellation checks; encoding can use the latest synchronization byte at dispatch. Queued user controls recheck the reported lock state before controller dispatch, including raw diagnostic commands. Read-only requests and explicitly lock-safe controls retain their normal behavior. Packet parsing and confirmation run immediately. Routine telemetry repaint notifications are coalesced to at most 10 Hz, with cached discovery/log snapshots and bounded records. These are implementation choices, not measured scooter throughput or battery-life claims.

Discovery also ignores identical advertisement metadata with RSSI changes under 4 dBm. The decoder compacts its byte buffer once per batch and reuses unchanged telemetry snapshots. These choices reduce allocations and rebuilds; they are not measured hardware speed or battery-life improvements.
