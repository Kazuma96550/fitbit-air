# Fitbit Air example

Interactive Android demo for every operation currently supported by
`fitbit_air`: paired-device detection, one-pulse toggling, persistent low/high
strength, and a restore-safe two-pulse preview.

Pair the Air in Google Health first, connect the Android phone, then run:

```bash
flutter run
```

The app does not unpair the Air or stop Google Health. Wrist taps, heart rate,
and activity statistics are not yet exposed because they require a transport
session or event path that has not been independently authenticated.
