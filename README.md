# fitbit_air

Experimental Flutter access to a Fitbit Air over its direct Android Bluetooth
transport: haptic controls, live heart rate, device information, and connection
diagnostics. Haptics are one use case, using this communication path:

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

Install the published package:

```bash
flutter pub add fitbit_air
```

Or add it to `pubspec.yaml`:

```yaml
dependencies:
  fitbit_air: ^0.1.1
```

For unreleased development changes only, use the Git repository instead:

The current development version is **0.1.2**. Secure-event and wrist-presence
diagnostics described below require this version; they are not in the published
0.1.1 release.

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
| Device model, firmware, manufacturer | GATT read verified on Pixel 7 Pro / Air firmware 67.20001.253.2 |
| BLE services and connection status | Read-only discovery and link status decoder implemented |
| Scan advertised heart-rate sensors | Experimental; requires Nearby devices scan permission |
| Restore/verify prior vibration intensity | Physically verified |
| Root/OAuth/private PSK required | No, for the bootstrap haptic path |
| Detect taps on the Air | Not implemented |
| Headless haptics | Release-mode background and one controlled screen-off command verified; long-term/idle reliability unresolved |
| Raw diagnostic events | Opt-in research stream; no confirmed tap decoder |
| Battery resource | Bootstrap read access verified; selected raw fields available in diagnostics, units/scale unverified |
| Heart rate | Standard BLE readings and continuous updates verified; requires an active Google Health sharing session |
| Google Health coexistence | Plugin releases GATT; Google Health remains connected. Concurrent Goldengate sessions produced packet-sequence warnings, so uninterrupted sync is not yet proven |
| iOS | Not implemented |
| Non-arm64 Android | Untested; requires a compatible library in the installed Google Health APK |

The Google Health implementation contains a `GET liveactivity` resource with
steps, activity, and heart-rate fields, but the Air rejects it with CoAP `4.01`
in the bootstrap session available to this plugin. It is therefore documented
as research rather than exposed as a misleading public API. See
[`doc/research.md`](doc/research.md).

`readDeviceInfo()` returns available standard fields, the actual GATT service
inventory, and the read-only connection configuration/status. Battery is
nullable: the tested Air does not expose the standard Battery Service.

Heart rate uses the separate standard Bluetooth Heart Rate Service. Start the
sharing flow in Google Health (Connections → Air → Share heart rate). Keep that
page open during initial discovery. `scanHeartRateDevices()` finds advertised
sensors, and `readHeartRate(deviceId: ...)` reads one measurement. With sharing
already active for this phone, `readHeartRate()` uses the paired Air directly.

`watchHeartRate()` keeps one Bluetooth client open and streams measurements;
cancel its subscription to release that client before sending a haptic:

```dart
final subscription = FitbitAir.watchHeartRate().listen((sample) {
  print('${sample.beatsPerMinute} bpm');
});
// Later:
await subscription.cancel();
```

An accepted subscription alone does not guarantee data: the Air accepted it
but sent nothing before sharing was active. `cancelOperation()` cancels reads
and scans; haptic writes finish their verification before returning.

### Experimental device events

Import `package:fitbit_air/fitbit_air_diagnostics.dart` to use
`FitbitAirDiagnostics.watchDeviceEvents()`. This monitors a limited set of
link-status and unclassified BLE characteristics, not the encrypted tracker
channel. It enables notification subscriptions but sends no haptic/control
commands. The demo keeps a bounded event log in memory only. Payloads may
contain sensitive device data; do not upload them without user consent.

These events are **not wrist-tap detection**. The first physical tap test was
inconclusive: subscriptions succeeded, but the connection ended before any
tap-related payload could be established. Cancel the stream before using
other SDK operations. Health Connect and historical stats are deferred.

`FitbitAirDiagnostics.watchSecureEvents()` observes incoming CoAP `events`
POSTs for 30 seconds by default after its `ready` event. Research trials may
set `durationSeconds` from 30 to 90; the total deadline is that duration plus
15 seconds, so slow negotiation can shorten observation. Unlike the passive BLE monitor, it opens a separate
Golden Gate session and acknowledges valid event POSTs. Startup/sync events
were decoded on hardware; a user-reported double-tap sequence produced no
identified tap event in the recorded window. This is **not a tap or on-wrist
API**. Unknown IDs remain unknown; no settings, sync or haptic commands are
sent. Cancel before another operation; Google Health coexistence is not
guaranteed. The demo keeps only a bounded in-memory log.

The monitor decodes both `events` and `eventsSecure`, acknowledging valid
EventSet POSTs with `2.04` and rejecting malformed bodies with `4.00`.
Five other source-traced incoming routes retain a `4.04` rejection response.
The two event routes use the same bounded event-ID decoder; other probes expose only route,
method and byte count. Both `WRS_OFF` and `WRS_ON` were received through
`eventsSecure` during a user-confirmed removal/replacement trial in a bootstrap
session. Tap correlation still needs confirmation. An `interrupted` event reports actual observation
time before a transport error; an incomplete trial cannot establish that a
gesture produces no event. The demo includes a separate wrist-presence trial
with manual removal/replacement markers. Start it on the phone when ready.

For typed, experimental presence events, use
`FitbitAirDiagnostics.watchWristPresence()` from the diagnostics import. Each
event has `state` (`AirWristPresence.onWrist` or `offWrist`), `receivedAt`, and
`sourcePath`. It shares the monitor's 30-second window and transport ownership;
it retains repeated reports and supplies no synthetic initial state. Phone
receipt times do not establish the time the tracker detected a transition.

`FitbitAirDiagnostics.probeReadOnlyResources()` checks a fixed GET allowlist
and returns status/body length, never raw response bodies. On the tested Air,
device info succeeded; alarms, live activity and sync status returned `4.01`.
See [research notes](doc/research.md) for scope and limitations.

`FitbitAirDiagnostics.probeBatteryAccess()` opens a separate Golden Gate
session and performs a read-only GET of the device-info resource. Access was
verified on the tested Air. It returns CoAP status and selected raw battery
fields, not a verified percentage or voltage unit. This is an explicit research
operation with the same Google Health coexistence caveat as other secure
sessions; it is never run automatically by standard GATT reads.

## Background and notification integration

For notification-triggered commands and the headless Android test, see
[`doc/background.md`](doc/background.md). A release-mode headless haptic was
physically verified with the demo backgrounded. A controlled screen-off command
also completed with duplicate suppression. An earlier trial timed out during
session establishment; long-term and deep-idle reliability remain unproven.
The host app must provide message reception and lifecycle management;
a phone notification alone does not trigger the Air.

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
- Starting with 0.1.1, that transport guard also covers separate Flutter engines
  in the same Android process. It cannot lock Google Health's separate process.
- Operations normally have a 45-second deadline. Secure-event research capture
  allows 30–90 seconds of observation plus 15 seconds for connection setup.
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
