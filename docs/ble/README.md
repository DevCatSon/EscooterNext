# Bluetooth protocols

Escooter Next aims to replace Vicont's companion app. This directory documents the Bluetooth communication used for that replacement: discovery, GATT layouts, packets, commands and response handling. Other scooter families may be added later, with a separate implementation and communication reference for each family.

## Current implementation

| Family | Implementation | Validation |
| --- | --- | --- |
| [Vicont](VICONT.md), ID `vicont` | Registered protocol with FFF0/FFF1 and FEE0/FEE2 GATT layouts | Original-client source findings, packet tests and supplied telemetry samples; full physical validation remains pending on Android/iOS |
| Other scooter families | Not implemented | No device support claimed |

A protocol family, a GATT layout and an exact scooter model are distinct. Vicont discovery considers the advertised-name prefixes `E-S`, `VC_`, `VC-`, `SN`, `VA-` and `ZL`, case-insensitively. These names can overlap with other devices, so a prefix alone does not establish compatibility. Explicit integration selection is available.

The bundled `gyrocopters-g30` record uses an owner-reported model name and a provisional firmware/name-prefix match from a Pixel capture. The `vicont-generic` record remains the unconfirmed family fallback. Both retain headlight, cruise and Kick start visibility defaults. See the [model catalogue](../MODELS.md) for identification, evidence and feature rules.

## Communication references

- [Vicont protocol](VICONT.md): GATT discovery, framing, telemetry and controls.
- [Connection audit](CONNECTION_AUDIT.md): original-client comparisons and corrections following a real-device communication failure. Validation on that scooter remains pending.
- [Original interoperability findings](../PROTOCOL.md): earlier source evidence and protocol notes.

## Evidence and limitations

- **Source-confirmed:** behavior traced to the original client, summarized without redistributing the extracted application.
- **Capture/device-confirmed:** an identified model/firmware and a recorded response/action establish the finding. Include that scope; supplied test samples alone do not prove every control works on a physical scooter.
- **Implementation behavior:** describes this app's encoding, matching, timeouts or UI, without claiming hardware acceptance.
- **Unverified/inferred:** hypothesis or interpretation awaiting a source trace or device capture.

The original client fetched model capabilities from a service. A complete BLE capability bitmap or country/model unlock has not been established. Local controls and artwork describe the app's presentation defaults; they do not remove firmware restrictions.

## Add another scooter family

Follow [adding a BLE protocol](ADDING_A_PROTOCOL.md), use the [protocol documentation template](PROTOCOL_TEMPLATE.md), and collect [diagnostic evidence](CAPTURE_GUIDE.md). Each wire protocol belongs in its own `flutter_app/lib/integrations/<family>/` directory, with a reference here and an entry in the implementation table above.

An alternate synthetic protocol exists only in tests to exercise extension points; it does not represent a supported scooter. New hardware support needs its own protocol evidence and device results.
