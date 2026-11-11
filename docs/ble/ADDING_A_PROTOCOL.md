# Adding a BLE protocol

The shared controller manages permissions, connection cancellation, queued writes, command timeouts and UI state. Each `ScooterProtocol` owns a fresh `ProtocolSession` with its handshake, framing, decoding, command encoding, confirmation rules and protocol-specific acknowledgements. One scooter connection is active at a time. Multiple protocol implementations can be registered; this is not simultaneous multi-scooter control.

First determine whether the scooter uses an existing wire protocol. A new model using the same packets generally needs catalogue data, not a duplicated protocol implementation. A different handshake, encryption/authentication scheme, framing or command set belongs in a separate module.

## Evidence first

1. Open a protocol/model issue with the scooter model, firmware, country/region where known, GATT layout and permitted source/capture evidence. Remove personal identifiers using the [capture guide](CAPTURE_GUIDE.md).
2. Create a document here from [PROTOCOL_TEMPLATE.md](PROTOCOL_TEMPLATE.md). Mark every unknown explicitly. Do not commit extracted proprietary apps, firmware dumps, account credentials or personal logs.
3. Record permissions, authentication and write modes before attempting control. Do not reuse the Vicont handshake on unknown hardware.

## Implementation

1. Create `flutter_app/lib/integrations/<family>/` and implement the interfaces in [scooter_protocol.dart](../../flutter_app/lib/integrations/scooter_protocol.dart). Keep packet framing, commands and decoding in that directory. The existing [Vicont integration](../../flutter_app/lib/integrations/vicont/vicont_protocol.dart) is a complete example, split into protocol/session, codec, decoder and commands.
2. Define a stable unique protocol ID, a display label, an advertisement matcher, supported `ScooterControl` actions, default visible features and numerical control ranges. Match only evidence known to identify that protocol. Broad names or a common GATT service alone may be ambiguous.
3. Supply `BleConnectionProfile` layouts with full UUIDs or Bluetooth short UUIDs. Notification and write characteristics can differ, including across services. An explicit write characteristic never falls back to an unrelated writable characteristic. `GattWriteMode` can require writes with or without response; automatic mode prefers with-response on iOS and without-response on Android, within advertised capabilities. Notification/write delays, an Android MTU request and requiring an initial protocol response belong to the integration profile.
4. Decode fragmented/coalesced packets inside the session and emit `ProtocolEvent` snapshots. Normalize common readings to the units used by `Telemetry` (km/h, km, volts, percent and Celsius where confirmed). Leave unknown values null. The Vicont session rejects checksum-failed frames and records mismatches in diagnostics without changing telemetry or completing commands.
5. Return a `ProtocolRequest` for each supported semantic command. Its encoder runs when the serialized queue dispatches the command, using the latest reported state. The confirmation predicate must check a relevant reply or reported state, not merely a successful BLE write. Mark read-only and lock-safe actions deliberately. Unsupported actions return null and must be omitted from `controls` and `ranges`.
6. Register the implementation in [ProtocolRegistry.standard](../../flutter_app/lib/integrations/protocol_registry.dart). No controller or screen changes are needed for existing semantic actions. The connection screen offers a choice when more than one registered integration matches. Unknown or ambiguous matches never send a speculative handshake.
7. Add source/capture vectors and fake-transport tests. [alternate_protocol.dart](../../flutter_app/test/support/alternate_protocol.dart) and [integrations_test.dart](../../flutter_app/test/integrations_test.dart) prove that a second implementation can use different GATT services, packets, telemetry and confirmation rules. This synthetic fixture is only in tests and is not advertised as a supported real scooter.

The current production registry contains the existing Vicont-family integration only. No other manufacturer's protocol or model support is invented. An integration that needs additional authentication, encryption, subscriptions or transport operations should extend the transport contract explicitly, with tests.

If setup requires a reply, enable `requiresResponse` on the profile and emit `ProtocolEvent.isSessionResponse` only for recognizable startup responses or sufficiently complete live reports. Test silence, early replies and cancellation as well as success. Keep simulation independent of real Bluetooth writes and discard all session state on disconnect.

## Validation and documentation

Add packet/checksum/scaling vectors, short/malformed/fragmented-frame cases, fake-transport confirmation/timeouts, disconnect races and integration-specific GATT tests. A synthetic fixture proves modularity, not scooter support. Record real-device outcomes separately for Android/iOS, model, firmware and tested actions.

Add a row to the [BLE index](README.md), link source/tests from the family document, update [PROTOCOL.md](../PROTOCOL.md) only if shared conclusions change, and add any evidence-backed model records using [catalogue rules](../MODELS.md). Preserve firmware/region limits and call out unsupported actions in the release notes.

Use the ordinary [contribution guide](../../CONTRIBUTING.md). Maintainer review is required before publishing a support claim or releasing a new integration.
