# Vicont-family communications

Protocol ID: **`vicont`**. This reference describes the current Flutter implementation, the original-client findings it preserves, and remaining unknowns. It does not identify an exact scooter model or guarantee acceptance of every command.

## Source map and evidence

| Concern | Source |
| --- | --- |
| Advertisement matching, GATT, session and reactions | [vicont_protocol.dart](../../flutter_app/lib/integrations/vicont/vicont_protocol.dart) |
| Framing, constants and conversions | [vicont_codec.dart](../../flutter_app/lib/integrations/vicont/vicont_codec.dart) |
| Semantic command encoding and confirmation | [vicont_commands.dart](../../flutter_app/lib/integrations/vicont/vicont_commands.dart) |
| Nullable reading offsets | [vicont_decoder.dart](../../flutter_app/lib/integrations/vicont/vicont_decoder.dart) |
| Protocol/sample vectors | [protocol_test.dart](../../flutter_app/test/protocol_test.dart) |
| Connection/confirmation behavior | [controller_test.dart](../../flutter_app/test/controller_test.dart) |
| Earlier interoperability findings | [PROTOCOL.md](../PROTOCOL.md) |

Framing, motor offsets, configuration sentinels and inverse start-mode switch behavior are **source-confirmed**. The tests preserve supplied telemetry samples. Exact-model feature availability, the meaning of all handshake bytes and regional restrictions remain **unverified**. Extended speed selection and retry/timeout policy are **app behavior**.

## Discovery and GATT

Candidate advertisement prefixes are `E-S`, `VC_`, `VC-`, `SN`, `VA-`, `ZL`. They select a protocol candidate, not a manufacturer/model proof.

The transport tries layouts in this order:

| Layout | Service | Notify characteristic | Write selection |
| --- | --- | --- | --- |
| `fff0-fff1` | `FFF0` | `FFF1` | Same characteristic if writable; otherwise the first writable characteristic in that service |
| `fee0-fee2` | `FEE0` | `FEE2` | Same rule within `FEE0` |

Bluetooth short UUIDs expand to `0000xxxx-0000-1000-8000-00805f9b34fb`. Notifications or indications must be supported. Automatic mode prefers **with-response on iOS** and **without-response on Android**, falling back to the other mode if required by characteristic properties. The selected concrete mode is logged. The generic transport also supports explicitly separate notification/write services for future integrations; this Vicont profile does not configure one.

Flutter waits **one second** after notification subscription, then sends these literal frames in order:

```text
FA AF A5 5A 01 00 5B
FA AF A5 FA 01 00 5B
```

These are source-confirmed constants. The second frame is not generated using the ordinary checksum rule; do not normalize it. On Android, Flutter requests MTU **255** before subscribing, with a two-second fallback wait; iOS negotiates its own MTU. The extracted client delays each write **300 ms**. Flutter keeps an initial **300 ms** settling period and a **300 ms** minimum gap after each completed write, with serialized dispatch. Once that gap has elapsed while idle, the next command can send immediately. The original helper scheduled independent timers; Flutter's gap policy avoids adding the same idle wait again.

Setup remains pending until a parsed code-1 reply or sufficiently sized code-16/17/18/171 report arrives. A silent session fails after eight seconds following the handshake instead of saving a false successful connection. Early reports also receive their pending binding reaction once ready. The plugin's public notification stream does not expose a separate CCCD-ready event; the one-second subscription delay remains a compatibility measure, not proof of peripheral readiness. Connection timeout is 18 seconds, a characteristic write times out after 3 seconds, and the controller's default command-confirmation timeout is 3 seconds. Those timeouts are app policy, not protocol requirements. See the [connection audit](CONNECTION_AUDIT.md) for evidence and remaining hardware checks.

## Frame format

```text
TX: FA AF A5 | ZT | CODE | LEN | DATA[LEN] | CHECKSUM
RX:            ZT | CODE | LEN | DATA[LEN] | CHECKSUM
```

Each field is a byte except the variable payload. Length excludes the checksum. For ordinary frames, checksum is `(ZT + CODE + LEN + sum(DATA)) & 0xFF`; the TX magic prefix is excluded. The session starts with ZT `0x5A`, then echoes the last received frame's first byte when dispatching a command. ZT is synchronization state, not an authentication key.

RX notifications can split or coalesce packets. The framer keeps incomplete tails, emits complete frames in order and clears state with a new session. Checksum-failed packets are logged and ignored: they cannot update telemetry or ZT, establish a session, trigger binding writes or confirm a command. This matches the supplied original native Android app's receive gate; the decompiled Vicont client itself dispatches notifications without this integrity check.

When a buffered fragment cannot form a valid packet, a complete checksum-valid packet at the next notification boundary can replace it. Within a completed checksum-failed packet or an unknown-opcode prefix, recovery searches for a known RX opcode with a complete valid checksum. An incomplete known packet retains its payload, and a valid reassembled packet takes priority over recovery candidates inside it. Discard counts and raw notification boundaries remain in diagnostics. RX has no magic prefix, so checksum/opcode recovery is a heuristic and cannot resolve every ambiguous damaged stream without a device capture. The additive checksum is an integrity check, not authentication.

## Gyrocopters G30 capture

An owner-supplied Pixel log from 2026-10-24 contains 91 raw notifications across codes 16–20. Every captured packet's additive checksum is valid. Each notification contains one additional `00` byte after that checksum; its meaning is unknown. The parser holds this possible trailer until the next packet establishes the boundary, so an actual zero-valued sync byte can still be reassembled. Confirmed trailers do not produce corruption/recovery messages.

The capture reports instrument hardware/software **104/37** and controller hardware/software **10/44**. The owner identified the scooter as a **Gyrocopters G30**. These values form a provisional model-catalogue match, not a unique model identifier. The shared firmware may appear on other hardware.

Representative telemetry is retained in [the G30 test fixture](../../flutter_app/test/fixtures/gyrocopters_g30_notifications.json), without the advertised name or Bluetooth address. All 91 raw notifications also replayed locally without rejected packets or recovery diagnostics. The supplied window contains no TX commands, so it establishes telemetry reception rather than control acknowledgement timing. A disconnect appears near the end, followed by reconnect attempts; the capture does not establish the cause. Diagnostic exports now retain `previousConnection` GATT details while a newer attempt is pending.

## Outgoing commands

Codes below are decimal. A semantic desired state of `1` means enabled in this app; the wire may encode it differently.

| Code | Purpose | DATA used by the app | Completion evidence |
| --- | --- | --- | --- |
| 51 | Lock | `[1]` unlock, `[2]` lock | Code 17 reported lock bit matches desired state |
| 52 | Find scooter | `[1]` start, `[2]` stop | Matching code acknowledgement; not a persistent physical-state report |
| 53 | Kick start / inverse zero start | `[2]` request bit5=1, `[1]` request bit5=0 | Code 17 bit5 matches desired state; code 53 acknowledgement alone is insufficient |
| 54 | Cruise | `[2]` on, `[1]` off | Code 17 cruise bit matches |
| 55–58 | Seat/cabin, helmet box, storage basket, brake lock | Alternating `[1]` / `[2]` pulses | Matching code acknowledgement; check the compartment itself |
| 60 | Maximum speed | `[1..31]` whole km/h; `[0]` read; `[255]` defaults | Nonempty code 60 response; returned value may differ from request |
| 61 | Starting torque | Scaled level; read/default sentinels as above | Nonempty code 61 response |
| 62 | Driving torque | Scaled level; read/default sentinels as above | Nonempty code 62 response |
| 63 | Brake strength | Scaled level; read/default sentinels as above | Nonempty code 63 response |
| 65 | Ambient light | `[mode, hue]`; mode 1–5, hue used only with mode 5 | Matching code acknowledgement; selected mode/colour are not confirmed read-back |
| 66 | Ride gear | `[1]`, `[2]`, `[3]` | Code 17 mapped gear matches |
| 67 | Unit | `[1]` km/h, `[2]` mph | Code 17 unit bit matches |
| 69 | Headlight | `[2]` on, `[1]` off | Code 17 headlight bit matches |
| 74 | Work mode | `[0]` read or `[1..3]` set | Valid code 74 reading; set must match desired value |
| 76 | Binding acknowledgement | `[1]` or `[2]` from reported lock/bound combination | Protocol reaction; original server-side eligibility gate is unavailable |
| 171 | Instrument versions | `[173]` | Code 171 or code 18 response |

Ambient UI modes are Off, Chase, Banner, Steady and Color for wire values 1–5. The byte can carry hue 0–255; it is not an arbitrary RGB payload. The UI exposes only the implemented presets.

Binding acknowledgement uses a differing `(locked, bound)` pair: locked→`[1]`, unlocked→`[2]`. Repeated identical eligible pairs are suppressed; a changed pair can trigger another acknowledgement. The remembered pair resets with the session. No complete BLE equivalent of the original remote `versionType` gate has been established. Do not generalize this reaction to another family.

Raw diagnostic commands bypass the normal semantic confirmation UI; their byte encoding is validated, but sending a raw frame does not prove success. They require an unlocked ready connection and are not a protocol-discovery tool to run against unknown scooters.

## Start mode interpretation

The original client calls `sendSwitch(53, startingModeState)`, reads code 17 DATA byte 0 bit5, labels its switch **zero start**, and shows it selected when that bit is zero. It sends `[1 == currentState ? 1 : 2]`.

This app labels the complementary bit5=1 state **Kick start**. That English interpretation is not a literal label found in the source. While pending, Flutter displays the last reported value. No supported model/country unlock command is known; a beep, successful GATT write or acknowledgement does not prove the setting changed.

## Configuration scaling

All writes use `[0]` to read and `[255]` to restore defaults. Zero therefore cannot mean a writable 0 km/h speed limit.

| Setting | Display range | Write conversion | Response conversion |
| --- | --- | --- | --- |
| Speed | 1–31 km/h | Whole km/h byte, even when display units are miles | DATA[0], preserved even outside selectable range |
| Starting torque | 1–10 | `level * 20` | `round(raw / denominator * 10)`, clamped 1–10; fallback denominator 99 |
| Driving torque | 1–10 | `level * 20` | Same display formula; fallback denominator 25 |
| Brake | 0–9 | `1` for level 0, otherwise `floor(level / 9 * 200)` | `round(raw / denominator * 9)`, clamped 0–9; fallback denominator 99 |

`raw` is DATA[0]. A response of exactly two bytes supplies DATA[1] as denominator when positive; otherwise the command-specific fallback applies. Raw torque/brake bytes are retained separately. A returned speed different from the request is shown as reported; a timeout restores the last reported UI setting. The app's 31 km/h selection cap does not establish controller acceptance or achievable speed.

## Incoming telemetry

Offsets below are zero-based into DATA. Multibyte words are unsigned big-endian. Omitted fields retain their prior readings; never-received fields remain null. Code 16 current and motor-speed units, and BMS capacity/temperature units, are not established by the implementation's names.

### Code 16 — motor readings

| Offset | Reading | Conversion |
| --- | --- | --- |
| 0–1 | Voltage | ×0.01 V |
| 2–3 | Current | Raw integer, units unconfirmed |
| 4–5 | Speed | ×0.1 km/h |
| 6 | Charge | Percent |
| 7 / 8 / 9 | Controller / motor / battery temperature | Integer °C |
| 10–11 | Motor speed | Raw integer, units unconfirmed |

### Code 17 — status and distances

| Offset | Interpretation |
| --- | --- |
| Byte 0 bits 0–2 | Raw gear; 1→Eco, 2→Drive, 3/4/5→Sport; other values unknown |
| Byte 0 bit3 / bit5 / bit6 / bit7 | Headlight / kick-start interpretation / cruise / miles |
| Byte 1 bit1 / bit5 / bit6 | Locked / ambient enabled / bound flag |
| Bytes 2–3 | Trip distance ÷100 km |
| Bytes 4–5 | Odometer in km |

### Versions, sensors and BMS

| Code | Offsets and interpretation |
| --- | --- |
| 18 | Bytes 2,3: instrument hardware/software; 6,7: controller hardware/software; byte 8: available-gear bitmask, bit0 representing gear 1 |
| 19 | Words at 0,2,4,6,8,10: throttle, brake1, brake2 and their three raw sensor readings |
| 31 | Words 0,2,4,6,8,10,12: BMS ID, voltage ×0.01, current ×0.01, cycles, rated capacity, remaining capacity, temperature. Flags at byte 1 overlap the low ID byte, preserving the source decoder. At least 6 bytes are required before applying BMS fields; later words are optional. Capacity/temperature units remain raw; current's physical units need confirmation. |
| 60–63 | DATA[0] is setting raw value; optional denominator rules above |
| 74 | For 2+ bytes, second-to-last byte; otherwise first byte. Values outside 1–3 are ignored. Layout variations still need hardware validation. |
| 171 | DATA[0], DATA[1]: instrument hardware/software |

### Reproducible example vectors

These are protocol test examples, not newly collected hardware captures. ZT is `5A`:

```text
Unlock:           FA AF A5 5A 33 01 01 8F
Lock:             FA AF A5 5A 33 01 02 90
Request bit5=0:   FA AF A5 5A 35 01 01 91
Headlight on:     FA AF A5 5A 45 01 02 A2
Read speed limit: FA AF A5 5A 3C 01 00 97
Request 31 km/h:  FA AF A5 5A 3C 01 1F B6
```

## Open questions

Exact model names/firmware restrictions, unsupported service variants, all handshake meanings, complete capability detection, reliable compartment state, raw sensor units and complete checksum/corrupted-stream behavior need additional evidence. Keep new family documents and model matches scoped to [documented captures](CAPTURE_GUIDE.md), not marketing names or visual similarity.

## Battery and total-distance display audit

The original client was checked again on 2026-10-24 against the supplied G30 capture. Its `app-service.js` SHA-256 remains `63fcd163af85f6c8d172de36f1b4cebfc10e3d5333abeb96834ec0943e010eb0` (source identity and analysis scope are recorded in the [connection audit](CONNECTION_AUDIT.md)). Focused source reads establish these mappings:

| Field | Original source location (zero-based byte offset) | Original display behavior |
| --- | --- | --- |
| Battery | `App.vue`, offset 709482: `surplus=parseInt(a.substr(18,2),16)` | Code-16 payload byte 6 is displayed directly as percent; the battery bar uses the same value. UI locations: 174283, 734498 and 752338. No voltage estimate is substituted. |
| Trip | `App.vue`, offset 711168 | Code-17 payload word 2 is divided by 100 before display. |
| Total distance | `App.vue`, offset 711236 | Code-17 payload word 4 is not scaled. Dashboard locations 733211 and 751024 pass it to `kmTMile`; that helper, at 2464101, returns it unchanged for kilometres and multiplies by 0.6213712 for miles. |

Flutter matches those mappings. The captured G30 total-distance bytes `03 84` decode to **900 km**, and battery byte `64` decodes to **100%**. This confirms interpretation of the reports, not the physical distance actually travelled or the accuracy of the scooter's battery gauge. No unsupported factor of ten/hundred or voltage-based replacement has been applied.

The original receive callback routes code 20 to its telemetry helper, but that version's helper has no code-20 value-decoding branch. It supplies no alternative battery or odometer value. The app's Find button now uses one `[1]` request per press; `[2]` remains a documented wire stop value rather than a persistent UI toggle.
