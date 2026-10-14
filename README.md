# fitbit_air

Experimental Flutter access to a Fitbit Air over its direct Android Bluetooth
transport. The supported operations are physically verified haptic controls:

```text
Flutter → Android BLE → Gattlink → DTLS bootstrap session → CoAP /settings → Air
```

This is not a Fitbit Web API wrapper. It does not require OAuth, root, unpairing,
or access to Google Health's private data. The Air must already be paired to the
same Android phone in the installed Google Health app.

> [!WARNING]
> This is independent reverse-engineering research, not an official Google or
> Fitbit SDK. It relies on private, version-sensitive device protocols and on a
> compatible, authentic Google Health installation. Android arm64 is the only
> configuration tested so far. Reliable wrist-tap detection has not been decoded.

## Install

Until the first pub.dev release, use the public Git repository:

```yaml
dependencies:
  fitbit_air:
    git:
      url: https://github.com/ThoreKoritzius/fitbit-air.git
```

The plugin contributes the Android Bluetooth permissions. Android 12+ asks the
user for Nearby devices access on first use.

## Use

```dart
import 'package:fitbit_air/fitbit_air.dart';

if (await FitbitAir.isAirPaired()) {
  // Exactly one pulse. This alternates and retains low/high strength.
  final result = await FitbitAir.pulse();
  print('${result.previousIntensity} → ${result.currentIntensity}');
}
```

The public haptic operations have deliberately different semantics:

- `pulse()` produces one pulse by alternating low/high strength and leaves the
  new strength active from the plugin's perspective. Google Health may later
  reconcile its own stored setting after the plugin disconnects.
- `setHapticIntensity()` persistently selects low or high and produces one pulse
  only when the value changes.
- `getHapticIntensity()` is read-only.
- `vibrate()` is the restore-safe preview: it changes the strength, waits, then
  restores it. That necessarily produces two pulses.

Every write is read back and verified. The restore-safe operation also makes a
best-effort restoration if its main sequence fails.

## Run the example

Connect an Android phone with a Fitbit Air already paired in Google Health, then:

```bash
cd example
flutter run
```

## Current scope

| Capability | Status |
|---|---|
| Detect an Android-bonded Fitbit Air | Implemented |
| Trigger a short Air haptic | Physically verified from this package on Pixel 7 Pro (2026-10-14) |
| Exactly one pulse | Implemented and protocol-verified; alternates the persistent strength |
| Read/set low or high vibration strength | Implemented and verified |
| Restore/verify prior vibration intensity | Physically verified |
| Root/OAuth/private PSK required | No, for the bootstrap haptic path |
| Detect taps on the Air | Not implemented |
| Live heart rate | Not implemented |
| Google Health coexistence | Verified after the haptic test; plugin released GATT and Google Health remained connected |
| iOS | Not implemented |
| Non-arm64 Android | Untested; requires a compatible library in the installed Google Health APK |

The Google Health implementation contains a `GET liveactivity` resource with
steps, activity, and heart-rate fields, but the Air rejects it with CoAP `4.01`
in the bootstrap session available to this plugin. It is therefore documented
as research rather than exposed as a misleading public API. See
[`doc/research.md`](doc/research.md).

## Native compatibility and provenance

The package and its APKs do **not** redistribute Google's `libxp.so`. At runtime,
the Android plugin verifies the installed `com.fitbit.FitbitMobile` signing
certificate, reads the matching library from that app's publicly installed APK
split, and copies it to this app's private code cache for loading. The cached
copy is keyed by Google Health's version and update timestamp.

The JNI-facing Kotlin bindings are adapted from the Apache-2.0 Golden Gate
Android bindings at commit `b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa`.
See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for provenance.

This arrangement avoids distributing a proprietary native binary or reading
Google Health's private files, but it creates a strict compatibility dependency:
a Google Health update can change the JNI ABI and require corresponding binding
updates in this package.

## Safety and compatibility

- The operation is serialized; concurrent calls return `BUSY`.
- A 45-second deadline closes the GATT connection.
- Google Health remains the pairing owner. This plugin opens a short-lived
  connection and does not unregister, factory-reset, or alter pairing keys.
- The plugin accepts the native implementation only from the expected signed
  Google Health package; a look-alike package is rejected.
- Firmware or Google Health updates may change the private protocol.
- Do not use this package for medical or safety-critical behavior.

## Name and trademarks

The Dart package name `fitbit_air` was unclaimed on pub.dev when checked on
2026-10-14. Availability is not a reservation until publication. Fitbit and
Google are trademarks of their respective owners; this project is unaffiliated.

## License

Plugin code is MIT licensed. Adapted upstream source retains its Apache-2.0
license. The runtime-loaded Google Health library remains subject to its owner's
terms and is not part of this distribution.
