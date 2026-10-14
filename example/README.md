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

Wrist taps and full activity statistics remain research work. Opening a concurrent
Goldengate haptic session can disturb Google Health's tracker transport even
though its Bluetooth client stays connected; uninterrupted sync is not proven.
