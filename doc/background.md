# Background notification integration

`fitbit_air` controls the device; it does not receive push messages, observe
other apps' notifications, or keep the Android app alive. These responsibilities
belong to the host app. A displayed phone notification is not automatically
forwarded to the Air.

## Current evidence

- Foreground haptics have been physically verified.
- The example includes a user-started `connectedDevice` foreground service
  which creates a separate Flutter engine and calls the existing SDK without
  an attached Activity. Permissions must already be granted.
- In the first display-off headless haptic test, BLE connection, discovery and
  tracker subscription succeeded. Native DTLS attempted its normal-identity
  fallback, but a usable session was not established before the 45-second SDK
  deadline. The operation returned TIMEOUT and the service stopped.
- This demonstrates that the plugin can execute headlessly, **not** that
  background vibration is reliable. It does not establish whether display-off
  execution caused the failure; session contention remains a candidate.
- A separate headless `readDeviceInfo()` trial succeeded, returning an available
  model field and automatically stopping the service. The display was turned
  off after starting the trial, but was awake by the subsequent check, so this
  is not a verified sustained-screen-off test.
- A subsequent **release-mode** headless haptic trial succeeded with the demo
  backgrounded and display awake. The SDK verified restoration of the original
  setting; the user confirmed feeling the two pulses. The separate service-owned
  engine had no attached Activity, and the service stopped after completion.
  This confirms the existing SDK can perform haptics headlessly under these
  conditions, but not guaranteed delivery in arbitrary background/idle states.

## Reproduce locally

1. Run the example and grant Nearby devices permission.
2. Choose the headless test. It starts an Android foreground service immediately,
   while the Activity is visible. Android controls notification visibility; on
   newer Android versions without notification permission it may appear only
   in the system's active-apps UI, not the notification drawer.
3. Press Home or lock the phone. After 15 seconds, a fresh service-owned engine
   invokes either `readDeviceInfo()` or `vibrate()`.
4. The service records only the outcome locally and stops. Return to the demo
   for the result, or inspect `adb logcat -s AirHeadlessTest`.

The service is not exported and accepts no remote intents. It is example code,
not a background service installed by the package. The haptic test makes at
most one SDK call; it does not repeatedly retry sessions. A timeout must not
trigger automatic repeated pulses: a lost response does not prove the command
never reached the device.

## What a notification app still needs

For your own push messages, implement message reception and dispatch eligible
commands to a live service/engine. For other apps' notifications, Android's
NotificationListenerService requires explicit user-granted notification access;
it is a separate integration, not provided here.

Grant Bluetooth permissions while a screen is visible. Queue/deduplicate
commands, expire stale messages, rate-limit haptics and avoid simultaneous SDK
operations across engines. Serialization in version 0.1.0 is per plugin
instance, **not a process-wide queue**. Neither FCM delivery nor foreground
service startup from arbitrary background states is guaranteed. Do not rely
on a bare background callback for an operation that can take 45 seconds.

Remaining validation before promising reliable delivery: screen-off/idle
operation, process restart,
duplicate messages, unavailable-device cleanup, and Google Health coexistence.
No push provider or end-to-end remote delivery has been tested by this example.

References:

- [Android background BLE guidance](https://developer.android.com/develop/connectivity/bluetooth/ble/background)
- [FCM Flutter background handling and execution limits](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
