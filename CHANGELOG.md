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
