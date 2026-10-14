# Fitbit Air example

Interactive Android demo for every operation currently supported by
`fitbit_air`: paired-device detection, one-pulse toggling, persistent low/high
strength, and a restore-safe two-pulse preview.
It also reads model/firmware/link information, scans heart-rate sensors, and
provides a live heart-rate display while Google Health sharing is active.

Pair the Air in Google Health first, connect the Android phone, then run:

```bash
flutter run
```

For heart rate, open Google Health → Connections → Air → Share heart rate to
start sharing. Return to the demo and select Live heart rate. Stop the stream
before sending a haptic. Discovery is also available when selecting a receiver
for the first time.

The headless test buttons start an example-only Android foreground service and
run the SDK in a fresh Flutter engine without an Activity. The operation starts
after 15 seconds so you can press Home first. The read-only test sends no
haptic command; the vibration test attempts the two-pulse preview and restore.
The outcome is shown when you return to the demo. This is not an FCM receiver
or an automatic relay of phone notifications. See
[`doc/background.md`](../doc/background.md) for current test results and limits.

The haptic test also submits the same command twice to demonstrate duplicate
suppression; it must still produce only the single two-pulse preview. The
example holds a bounded CPU wake lock while work runs and releases it afterward.

The optional battery-access research button opens a secure session, reads
device info, and shows selected raw battery fields. Units/scale are unverified;
it is not the same as the standard GATT battery percentage (absent on this Air).

Wrist taps and full activity statistics remain research work. Opening a concurrent
Goldengate haptic session can disturb Google Health's tracker transport even
though its Bluetooth client stays connected; uninterrupted sync is not proven.
