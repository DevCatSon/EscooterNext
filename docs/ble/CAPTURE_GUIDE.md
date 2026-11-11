# Capture and identification evidence

Work with your own or explicitly authorized scooter, stationary and supported. Record one action at a time. Do not probe arbitrary raw commands or test motor-driving behavior for the sake of a log.

## Record context

Include app version/commit, phone OS, scooter marketing/model label, controller/instrument firmware integers, country/region if relevant, active integration and chosen GATT layout. Model names, firmware and app versions are distinct evidence fields.

In Flutter, connect then open **Settings → Scooter models** to review identification and **Diagnostics** for frame/type logs. A `TYPE` event records protocol selection or updated model/firmware evidence; it is not a guarantee of exact-model identification. Notes should say whether a model was automatically matched, manually selected or user-defined.

## Reproduce one observation

1. Note the last reported state and expected change.
2. Start from a fresh, bounded log if practical. Perform one UI action.
3. Preserve TX and relevant RX frames, timing, any reported state change, the timeout/error and whether the physical behavior matched.
4. Note disconnect/reconnect outcomes and whether another client was connected. Keep a failed or rejected write in the evidence rather than labeling it supported.
5. For a setting, distinguish request, acknowledgement and read-back. For a switch, show the relevant status bit before and after. A beep or successful write alone is insufficient.

## Export review

**Copy frame log** produces schema-versioned JSON with `at`, `direction`, `message` and optional structured fields. Log directions include TX/RX, RX-RAW, LINK, ERROR, INFO, TYPE and DEMO. RX-RAW preserves each notification, including partial or unrecognized packets. The in-memory log is bounded to 240 entries; copy it soon after reproducing the issue. The optional top-level `connection` object preserves the last attempt's GATT service/characteristic properties, chosen write mode, platform and Android MTU result after its startup entries leave the rolling log. If a newer attempt has replaced that context, `previousConnection` retains the most recent configured connection. **Copy model data** exports model definitions and observation values; internal per-device Bluetooth ID keys are omitted.

Exports still contain advertised/model names, timestamps, firmware and raw bytes. Device identifiers may also appear inside raw payloads or platform error text. **Exports are not guaranteed anonymous.** Review the complete text before posting it publicly. Replace names/addresses/serials/account information consistently, note every redaction, and avoid changing bytes needed to reproduce a checksum or offset without explaining that change. Use a minimal synthetic packet when it can demonstrate a bug without exposing captured identifiers.

Do not post provisioning profiles, signing keys, extracted apps, device screenshots containing personal notifications, account email addresses or unreviewed platform logs.

## Contribution format

```text
Model / firmware / region:
App commit and phone OS:
Integration and GATT layout:
Evidence: source trace / supplied capture / live device / inference
Before state:
Action and requested value:
TX/RX (sanitized, with timing):
Reported result and physical result:
Redactions and remaining unknowns:
```

Update the appropriate [family reference](README.md) and tests only after the evidence supports the interpretation. Do not infer a complete capability list from one accepted command.
