# Reverse-engineering status

This file separates confirmed protocol facts from candidates that are not safe
to expose through the package yet.

## Confirmed and packaged

- Direct tracker channel over BLE, Gattlink, DTLS bootstrap, and CoAP.
- Haptic setting read: `PUT /settings` with `0a0101`.
- Haptic setting write: `POST /settings` with the protobuf value `2` (low) or
  `3` (high).
- A changed setting produces one physical pulse. Restoring it produces another.
- Short-lived coexistence with Google Health: the plugin closes its GATT client
  after every operation and does not alter pairing.

## Live activity and heart rate

Google Health reads `GET liveactivity` once per second in its normal direct
communications session. The response is `LiveActivity.Activity`, effectively:

```proto
message Activity {
  optional int32 timestamp = 1;
  optional int32 steps = 2;
  optional int32 distance = 3;
  optional int32 calories = 4;
  optional int32 elevation = 5;
  optional int32 active_minutes = 6;
  optional int32 heart_rate = 7;
  optional HeartRateConfidence heart_rate_confidence = 8;
  optional int32 daily_zone_minutes = 9;
  optional int32 weekly_zone_minutes = 10;
}
```

On the tested Fitbit Air, the endpoint returned CoAP `4.01 Unauthorized` over
the bootstrap DTLS session used by the haptic setting. It apparently requires
the normal mobile-data DTLS identity and paired-device PSK. The package does not
attempt to obtain that private credential, so live activity is not in the
public API.

## Incoming interactions

The decompiled stack contains device-state/on-wrist events and unsolicited CoAP
resource handlers. `ON_WRIST_ALERT` is not evidence of a user tap, however, and
no wrist-tap event payload has been confirmed. Tap detection remains open work.

Other candidates—notifications, alarms, battery alerts, sync status, and the
ping characteristic—must be traced and tested individually. They should not be
added to the stable Dart surface until their payload, side effects, credential
requirements, cleanup, and Google Health coexistence are verified.
