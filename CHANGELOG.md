## 0.1.1

- Guide physical tap research with timed quiet/tap intervals and explicitly
  manual LED-observation markers in the demo; no tap-detection API is claimed.
- Fix the incoming CoAP request-filter JNI signatures to match the installed
  transport; add ABI regression tests for active native constructors.
- Add bounded, opt-in secure protocol-event observation. Startup/sync events
  verified on hardware; wrist-tap and wrist-presence detection remain unverified.
- Add a fixed read-only resource-access probe without exposing response bodies.
  Device-info access succeeds; alarms, live activity and sync status are denied
  in the tested bootstrap session.
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
