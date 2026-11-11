# Protocol family record template

Copy this structure to a new family document. This template is not an implemented integration or a supported-scooter claim.

## Identity and status

- Protocol ID and source module:
- Scooter models and exact firmware tested:
- Phone OS/app versions tested:
- Evidence status and source/capture references:
- Region/model limitations and unsupported features:

## Transport and setup

- Advertisement match evidence and collision/ambiguity behavior:
- Full service, notification and write UUIDs:
- Characteristic properties and response mode:
- Pairing/authentication/encryption requirements:
- Notification ordering, delays, MTU/packet-size requirements:
- Literal handshake and synchronization rules:
- Disconnect/cancellation/reset behavior:

## Frames and commands

- TX/RX shapes, length fields, byte order and checksum/integrity rules:
- Fragmentation, buffering, malformed input and recovery:
- Opcode, semantic action, desired-state/wire-value mapping and limits:
- Relevant acknowledgement versus reported physical-state confirmation:
- Read/reset sentinel values and scaling:
- Nullable telemetry offsets, raw units and unconfirmed fields:
- Sanitized example vectors linked to reproducible tests:

## Model matching and validation

- Catalogue match constraints and verified visible features:
- Identification fields and firmware formatting:
- Source/unit tests and fake-transport cases:
- Android physical tests and outcomes:
- iOS physical tests and outcomes:
- Remaining unknowns and next evidence needed:

Add the completed record to the [BLE index](README.md) and follow [the integration process](ADDING_A_PROTOCOL.md).
