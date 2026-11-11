# Connection audit — 2026-10-21, build 7

The user reported that connecting to a real scooter produced no working data or controls. No capture from that failing session was available during this audit. The changes below correct source-confirmed differences and a reproduced setup-state defect; they do not establish the root cause on that scooter or claim a successful physical test.

## Reference identity and scope

The supplied decompiled Vicont client was read locally from `vicont_extract/jadx_out/resources/assets/apps/__UNI__D837DE5/www/app-service.js`. Its SHA-256 is `63fcd163af85f6c8d172de36f1b4cebfc10e3d5333abeb96834ec0943e010eb0`.

REA parent Evidence: `ev_f16708a87d7b631c55d3105749dcf726c17036b8dcb0c77a83e02f1bb8c537bf`. The source was parsed as inert text and was never executed. Only `app-service.js` was selected; 31 other inventoried files remained outside analysis, and semantic graph capacity was reached. Focused source reads of the functions below supplied the exact behavioral comparisons. Static analysis does not prove runtime success or scooter acceptance. The extracted app is not redistributed here.

The preserved native reference at Git commit `2e8406c` was also compared: `ScooterBleManager.kt` and `ProtocolCodec.kt` under the former `app/src/main/java/com/devcat/escootercontrol/ble/` tree. The native application remains removed from the active repository.

## Findings and corrections

| Finding | Evidence locator in the original bundle | Build 7 behavior |
| --- | --- | --- |
| When FFF0 exists, the client selects notifyInfo[1], which is FFF0/FFF1. Both our native and Flutter implementations had preferred FEE0. | `common/utils/Bluetooth/Ble.js`, `getBLEDeviceServices`; notifyInfo construction in `App.vue` | Prefer usable FFF0/FFF1, then FEE0/FEE2. Separate writable-characteristic fallback remains app behavior. |
| iOS chooses `write`; other platforms choose `writeNoResponse`. Flutter previously preferred no response on both. | `Ble.js`, `writeBle`, platform conditional before `uni.writeBLECharacteristicValue` | Prefer with-response on iOS and without-response on Android; fall back within advertised properties. Log the actual selection. |
| The original requests MTU 255. The native reference retained this, but Flutter omitted it. | `Ble.js`, `getBLEDeviceServices`, `uni.setBLEMTU` | Request 255 on Android before subscribing to avoid overlapping application GATT operations. Continue on timeout/failure as the native reference did. iOS negotiates its own MTU. |
| Original writes are deferred 300 ms. Flutter had no write delay. | `Ble.js`, `writeBle`, its outer 300 ms timer | Restore the delay for Vicont. Serializing delayed writes is app policy, not an exact replay of the client's independent timers. |
| Both fixed handshakes were already correct. | `pages/tabBar/homePage/homePage.vue`, `onBLENotifyResult` | Keep both byte-for-byte, including the unusual second checksum. |
| Flutter reported ready and saved the scooter after writes completed even if no response arrived. Reproduced with a silent fake peripheral. | Current controller behavior and regression test | Require a recognized startup reply/live report, with an eight-second response deadline after the handshake. Do not issue the version query or save a new successful connection if silent. |
| Reports received during setup skipped protocol reactions until another report arrived. | Current controller regression test | Apply pending binding reaction once setup becomes ready, without duplicating it on each heartbeat. |
| Parsed-only logs discarded incomplete notifications and omitted selected write properties. | Current diagnostics path | Record raw notification boundaries and errors. Keep GATT/platform/MTU metadata outside the bounded rolling entries for later export. |

The original binding behavior also depends on a server-side `versionType` gate. That eligibility remains unknown; the existing local binding policy is preserved, not newly verified for all models.

## Validation and remaining work

Regression tests exercise the actual transport through a fake BLE backend: Android/iOS write dispatch, MTU-before-subscription ordering and cancellation. Controller tests cover silent/incomplete responses, early status/binding handling and cancelling a response wait. Existing command vectors and reported-state UI confirmation remain in place.

Physical validation is pending on both operating systems. Capture the Diagnostics log shortly after a failed attempt, together with app build, phone OS, scooter advertised name/model and firmware if known. Needed checks are the chosen GATT channel, write result, raw handshake response, live status and a confirmed control change. The public plugin API exposes no separate notification-subscription completion event; the compatibility delay cannot by itself prove CCCD readiness. Corrupted-length parser recovery and model/region restrictions also require actual traffic before changing wire assumptions.

## Receive-path follow-up — 2026-10-24, build 13

The user reported continued failure on a Pixel, with constantly arriving apparently garbled data and possible checksum errors. No log from that session was supplied. This follow-up fixes reproduced receive-path defects; it does not establish what corrupted or misaligned the actual device traffic.

The decompiled bundle was compared again, with the same SHA-256 above. REA parent Evidence: `ev_dd0b28819a2a886bcb5c931044a931945d8b671ebcafb4d77fdc9246a86e4989`. Only `app-service.js` was selected and parsed as inert text; 31 other inventoried files were unselected, and semantic retention was partial. Focused reads of `App.vue`'s notification callback (character offset 699121) and `homePage.vue`'s `writeDisposeHandle` (2074004) establish the comparisons below, without executing the extracted application.

The supplied original native app in Documents was also read directly, rather than assuming it matched the historical Git snapshot. Its `ProtocolCodec.kt` SHA-256 is `33ea17a9d0222c26397005f9eb877cf8281cb4a35a25f5ccc88e1a706aeda004`; `ScooterBleManager.kt` is `ca94e6370b8556858864f8bc3f16f847c63f1f274ca7a83c58bdc8f40ba07f3a`. That copy rejects checksum-failed packets before decoding. The decompiled Vicont client's callback processes each notification directly and does not check its length/checksum first. These are different receive policies, not evidence that all firmware emits the same data.

| Reproduced defect | Correction |
| --- | --- |
| A stale partial packet or damaged length could absorb subsequent valid notifications. A leading garbage byte could turn two real packets into one bogus frame. | Recover at complete checksum-valid known packets, including new notification boundaries. Preserve verified split-packet reassembly and normal coalesced packets. |
| Checksum-failed packets still changed telemetry and ZT, satisfied pending commands and could establish setup readiness or trigger binding writes. | Emit diagnostic-only events for rejected input. Keep the last verified state, sync byte and receive timestamp. Require valid packets for command confirmation and setup readiness. |

Outgoing checksum arithmetic, both handshake literals, toggle polarity and binding acknowledgement values match the compared implementations and were left unchanged. GATT selection and platform write modes were also left unchanged. The RX recovery rule is bounded by the format's one-byte length, but remains heuristic because RX has no magic prefix; an additive checksum is not authentication.

Four new regression cases failed against the previous code and passed after the correction. Additional tests cover checksum-failed startup, setup recovery, repeated leading garbage and frame-like patterns inside a legitimate split payload. Review also reproduced and corrected premature recovery inside an incomplete known packet. All 136 Flutter tests pass and static analysis is clean. Device validation is still required: reproduce with build 13, then copy the Diagnostics frame log promptly if communication fails again. Raw notification boundaries and recovery messages are retained for that comparison.
