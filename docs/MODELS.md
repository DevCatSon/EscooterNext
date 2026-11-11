# Local model catalogue

Protocols describe communication. Model records describe evidence-based identification, visible controls and decorative artwork. The bundle includes an owner-reported **Gyrocopters G30** profile and the unconfirmed Vicont family fallback. Model identification and telemetry evidence do not establish that every control works on every unit.

Bundled data is [scooter_catalog.json](../flutter_app/assets/scooter_catalog.json), schema version 1.

## Gyrocopters G30

The owner identified the scooter as a Gyrocopters G30 and supplied a Pixel capture on 2026-10-24. Automatic matching requires the Vicont protocol, an `SN_` advertised-name prefix and all four reported firmware integers: instrument hardware **104**, instrument software **37**, controller hardware **10**, controller software **44**. The owner's full advertised serial name and Bluetooth address are not bundled.

This is a provisional firmware-based match: other scooters may share the same electronics, and a firmware update may require manual selection through **Settings → Scooter models**. The profile retains the existing headlight, cruise and Kick start visibility defaults and uses a transparent G30 product illustration generated from the owner’s photographs. The [artwork reference](../flutter_app/design/G30_ARTWORK.md) records its provenance and prompts. It does not claim additional controls. See the [G30 capture findings](ble/VICONT.md#gyrocopters-g30-capture) for the communication evidence.

## Model record

This is a synthetic example, not a supported model claim:

```json
{
  "id": "example-commuter",
  "name": "Example commuter",
  "protocolId": "vicont",
  "advertisedNames": ["VC_EXAMPLE"],
  "namePrefixes": [],
  "requiredServices": ["fee0"],
  "firmware": {"controllerHardware": 2, "controllerSoftware": 27},
  "features": ["headlight", "cruise", "kickStart"],
  "artwork": "assets/models/example.png",
  "source": "Describe the source trace or hardware capture here"
}
```

Matching firmware keys are `instrumentHardware`, `instrumentSoftware`, `controllerHardware` and `controllerSoftware`, using the reported integer values. Available feature keys are `headlight`, `cruise`, `kickStart`, `ambient`, `seat`, `helmet`, `storage` and `brakeLock`. A model cannot enable a command missing from its protocol's supported controls.

Declare model artwork in `flutter_app/pubspec.yaml` and place the image in `flutter_app/assets/`.

## Matching rules

A record has a stable ID/name, protocol ID, optional exact advertised names/prefixes, required service UUIDs and instrument/controller firmware integers. All populated evidence categories must match. Exact names outrank broad prefixes; additional evidence refines the result. Equal best matches remain ambiguous. A record with no identifying constraints is only a family fallback.

A model can enable visibility only for controls its protocol implements. Firmware/region restrictions still apply. Prefer an exact, evidence-backed match to a broad prefix that could select the wrong scooter. New records need a source note and a [capture/source record](ble/CAPTURE_GUIDE.md).

## Device settings and local records

**Settings → Scooter models → Save this model** saves a user-defined entry from current evidence and visible feature choices. It is not promoted to hardware-verified support. Manual model selection remains with that device; automatic matching can refine defaults as new firmware/GATT evidence arrives. Nicknames remain independent of the model label/artwork.

Explicit per-device feature overrides take precedence. **Feature support → Use model defaults** removes those overrides. A different scooter does not inherit the prior device's choices. Existing saved-device records migrate to the original integration.

Local preferences retain at most 64 user model definitions and 128 device/observation records. Observations hold advertised name, protocol, GATT layout/services, reported firmware, model-match outcome and first/last seen times. They update on identification changes rather than every telemetry sample. Demo Mode adds no real observations. Forgetting a scooter removes its device settings and observation; reusable model definitions remain.

## Artwork and export

Use a declared bundled asset or `icon:scooter`; missing images fall back to that symbol. Remote image loading and gallery import are not implemented. Use original or properly licensed images and record provenance in [third-party notices](../THIRD_PARTY_NOTICES.md).

**Copy model data** exports schema-versioned definitions and observations without the internal Bluetooth ID association keys. Names/raw evidence can still identify a device. Review exports using the [capture guide](ble/CAPTURE_GUIDE.md) and [privacy document](PRIVACY.md) before sharing. Public catalogue contributions should be minimal model records, not an owner's entire local database.

Diagnostics records structured `TYPE` events when protocol selection, firmware or model evidence changes. **Copy frame log** includes those fields with TX/RX messages; clearing that log does not clear the model database.
