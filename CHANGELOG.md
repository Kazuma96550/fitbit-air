## Unreleased

- Fix Google Health sync stalling for about a minute after every DTLS command.
  The Air has one Gattlink/DTLS channel shared by all clients on the link; our
  session left Google Health's channel out of sync until its ~60 s watchdog
  reconnected. Commands now end with a handoff: a short session that refuses
  the Air's key, which makes the Air reset the link for every client, after
  which the SDK goes silent so Google Health re-handshakes alone. Results are
  returned after the handoff (typically 1–3 s). Verified in five vibrations on
  a Pixel 7 Pro, including the relay worker and Google Health in foreground.

- Serialize command Bluetooth callbacks with teardown, discard stale native
  callbacks/completions, and track partially initialized resources for cleanup.
  These fix lifecycle races; Health sync coexistence still needs phone validation.

- Expose bounded, process-wide command cleanup diagnostics in demo reports,
  including teardown failures and app-local transport ownership. This aids
  Health sync investigation; it does not establish or fix the underlying cause.

- Fix empty WhatsApp capture by inspecting unread notifications immediately,
  retaining results after listening stops, and exposing safe diagnostic counts.
- Add explicitly confirmed exact-chat-name rules when message notifications lack
  a conversation ID; show duplicate-name/rename limitations before saving.
- Simplify relay setup with a visible Choose people card, collapsed completed
  device setup, clearer capture states and a nearby sanitized debug report.

- Add example-only WhatsApp/WhatsApp Business conversation allowlists with
  explicit 60-second local capture, app-scoped conversation matching,
  fail-closed handling of missing IDs and controls locked while relaying.
- Keep conversation labels/IDs out of diagnostic reports and Android backups;
  direct-chat selection supports people, while selected groups allow all senders.

## 0.1.2

- Organize the example into Relay, Device and Lab screens with a shared named
  action controller, explicit transport ownership, and safe relay-stop handoff.
- Add app search/icons, setup checks, a relay-aware vibration test, and bounded
  persistent metadata history with terminal outcomes, latency and recovery hints.
- Add saved research durations, structured bounded trial results, sanitized JSON
  export, manual physical-observation markers, stable control keys and opt-in
  physical-device integration scenarios. Existing research tools remain available.

- Generalize the example relay to a saved app allowlist with an installed-app
  picker, including WhatsApp. Accept newer MessagingStyle timestamps on reused
  chat notification keys while suppressing duplicate updates and old history.

- Add an example-only Google Calendar notification relay with notification-access
  setup, foreground Start/Stop controls, duplicate filtering and bounded haptic
  dispatch. WhatsApp relay smoke success was user-reported on 2026-10-16;
  long-term reliability and the revised UI still need physical validation.

- Allow bounded 30–90 second secure-event research trials; use 90 seconds for
  alarm dismissal so delayed events can be observed after the gesture.

- Acknowledge valid POSTs on both event routes with CoAP `2.04`, matching
  Google Health's event handler; reject malformed event payloads with `4.00`.
- Add a manual tap-attempt marker independent of LED confirmation in the demo.
- Add an alarm-dismissal observation trial with separate manual onset, attempt,
  and stopped-vibration markers; the demo does not create alarms.
- Observe additional incoming routes, decode bounded `eventsSecure` event IDs,
  and report partial observation duration on interruption. `WRS_ON` receipt
  verified in a bootstrap session, including both presence states during a
  user-confirmed removal/replacement trial.
- Add a dedicated wrist-presence trial with manual action markers in the demo.
- Add experimental, bounded `watchWristPresence()` with typed device-reported
  states and phone receipt times.
- Guide physical tap research with timed quiet/tap intervals and explicitly
  manual LED-observation markers in the demo; no tap-detection API is claimed.
- Fix the incoming CoAP request-filter JNI signatures to match the installed
  transport; add ABI regression tests for active native constructors.
- Add bounded, opt-in secure protocol-event observation. Startup/sync and
  wrist-presence events verified on hardware; wrist-tap detection remains open.
- Add a fixed read-only resource-access probe without exposing response bodies.
  Device-info access succeeds; alarms, live activity and sync status are denied
  in the tested bootstrap session.

## 0.1.1

- Add bounded haptic command dispatch with expiry, duplicate suppression,
  rate limiting, and no automatic retry of ambiguous device failures.
- Guard transport ownership across Flutter engines in the same process.
- Add bounded CPU wake-lock handling to the example headless service.
- Verify one controlled screen-off haptic with physical user confirmation and
  simulated duplicate suppression; deep-idle/restart reliability remains open.
- Add research-only battery-resource access and selected raw-field decoding;
  bootstrap GET access verified, units/percentage scale not yet claimed.
- Update installation instructions for the published 0.1.0 package and describe
  the broader Bluetooth API beyond haptics.
- Add user-started, headless read/haptic tests to the Android example and
  document background integration limitations. Headless reads and release-mode
  haptics verified on Pixel 7 Pro; user physically confirmed the pulses.
- Include the full Apache-2.0 license for the adapted JNI bindings.
- Add Dart dispatcher regression tests and native lease/protobuf tests to CI.

## 0.1.0

- Add opt-in, local-only diagnostic BLE event monitoring (not tap detection).
- Preserve JNI binding names in minified Android builds and allow bounded
  haptic recovery requests to finish before reporting an operation failure.
- Add read-only device information, BLE service inventory, and link diagnostics.
- Add standard heart-rate discovery, verified readings, continuous streaming,
  and read cancellation. Google Health heart-rate sharing must be active.
- Add direct Android BLE discovery for an already-paired Fitbit Air.
- Add bounded haptic command with best-effort restoration and verification.
- Add typed read/set intensity controls and a verified single-pulse toggle.
- Load the compatible native transport from a certificate-pinned, installed
  Google Health APK without redistributing its binary or reading private data.
- Include adapted Apache-2.0 Golden Gate JNI-facing Kotlin bindings.
- Add a demo app covering every supported operation and a typed Dart API.
