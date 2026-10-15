# Reverse-engineering status

This file separates confirmed protocol facts from candidates that are not safe
to expose through the package yet.

## Confirmed and packaged

- Direct tracker channel over BLE, Gattlink, DTLS bootstrap, and CoAP.
- Haptic setting read: `PUT /settings` with `0a0101`.
- Haptic setting write: `POST /settings` with the protobuf value `2` (low) or
  `3` (high).
- A changed setting produces one physical pulse. Restoring it produces another.
- The plugin closes its GATT client after every operation and does not alter
  pairing. Google Health remains registered and connected, but its logs show
  Gattlink sequence warnings during overlapping Goldengate sessions. A connected
  client is not proof that syncing is uninterrupted; coexistence needs further
  validation before production use.

## GATT information and standard heart rate

The current Air reports model `67`, firmware `67.20001.253.2`, manufacturer
`Fitbit`, and eight services. Standard Device Information reads are verified.
There is no `180F` Battery Service, so a battery percentage is not inferred.

`ABBAFD01` is the current connection configuration (interval, latency, timeout,
MTU, mode). `ABBAFD02` is connection status (bonded/encrypted flags and data length
limits). Both are read without subscribing to tracker traffic or opening DTLS.

The Air exposes standard heart-rate `180D` / `2A37`. Before activating its
sharing session, subscriptions returned GATT success but produced no data,
including while worn. Scanning while Google Health's “Share heart rate” page
was open discovered the Air. Connecting then produced a three-byte standard
measurement decoded to a non-zero BPM reading on 2026-10-14. Google Health
simultaneously displayed that it was sharing heart rate with the test phone.

Android's GATT history resolves the selected advertisement to the same bonded
Air connection, so this is evidence for a sharing-session prerequisite, not a
second physical address. The “Always visible” switch was off throughout and
was not changed. No private PSK or Goldengate session is needed for standard HR.

The package includes one-shot reads and a stream. Streaming was verified with
successive non-zero BPM samples roughly once per second.
Cancelling the stream removed the demo's GATT client; Google Health's client
remained connected. The read-only link status returned encrypted=true,
MTU=247, interval=150 ms. It decodes standard UINT8 or
UINT16 BPM, optional contact state, energy, and RR intervals. The observed sample
did not contain contact state or RR intervals; those optional fields remain
untested on hardware. Streaming must be stopped before a haptic operation.

References:

- [Bluetooth Heart Rate Service specification](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html)
- [Google Health heart-rate sharing instructions](https://support.google.com/googlehealth/answer/14236705?hl=en)

The Google Health source uses `aspen/request/adv_on`,
`aspen/request/session/accept`, and `aspen/info` for its sharing flow. These
resources have not been probed or exposed through this package.

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

Further source inspection identifies incoming `POST events` with an
`EventSet.Set` protobuf body. `GoldenGateCommandHandler` registers its handler
with `CoapGroupRequestFilterMode.GROUP_1`; `EventConsumer` handles `WRS_ON` and
`WRS_OFF` as wrist-presence transitions. `Event` also contains RSET, BSNC, CGPS,
PING, AOFL and UNKNOWN, but no explicit tap enum. The existence of PING does
not identify a tap or a vibration command. Event parsing and authorization
would need separate hardware validation before exposing an on-wrist API.

### Secure event observation (2026-10-15)

The release demo now registers the local `events` POST handler with GROUP_1
and decodes bounded `EventSet.Set` payloads, including unknown uint32 IDs.
It acknowledges valid POSTs with `2.04`, but does not respond by issuing the
settings/sync operations that Google Health's `EventConsumer` would run.
No outgoing reset, alarm, haptic or configuration commands were sent.

During the measured 30-second window, READY was recorded at 08:17:39.837 on
the phone, followed by `RSET` at 08:17:40.296 and `BSNC` at 08:17:41.785.
Observation completed at 08:18:09.856 with two POSTs and no dropped POSTs.
The user reported performing the requested three double-taps, but their reply
arrived after completion; exact physical timing cannot be independently
established. No identifiable tap event appeared in the recorded window.
This does not establish that taps are unavailable through a different resource,
firmware state or normal paired-device session. At this stage wrist-presence
events had not been received; see the later route probe below. `RSET` here is a received protocol event, not an
instruction from the demo to reset the device.

The first incoming-request attempt crashed the demo's native loop. Comparing
the installed app's JNI declarations identified an ABI mismatch in the adapted
`CoapGroupRequestFilter`: `create()` returns `NativeReferenceCreationResult`,
not a pointer-valued Long; `setGroup()` and `destroy()` return Int status codes,
not void. These declarations and status handling are corrected. A subsequent
release APK received both events without that crash. Reflection tests now
protect these signatures and the active native constructor signatures. This is
not a guarantee of compatibility with future Google Health native versions.
Google Health's process remained running, which alone does not prove its sync
was uninterrupted.

### Read-only resource boundary (2026-10-15)

One bootstrap session issued the following sequential GETs, with no writes:

| Resource | CoAP result | Body bytes |
| --- | --- | --- |
| `/md/606` | `2.05 Content` | 79 |
| `liveactivity` | `4.01 Unauthorized` | 0 |
| `/alarms` | `4.01 Unauthorized` | 0 |
| `/sync/status` | `4.01 Unauthorized` | 0 |

The public diagnostic result contains only path, status and byte count; it
does not expose alarm/health data or device identifiers from the response body.
This is a fixed allowlist, not an arbitrary resource or write API. These results
apply to the tested firmware and bootstrap role, not all Fitbit devices or roles.

### Tap-path reassessment and physical positive control

The user subsequently reported that double-tapping did not produce a visible
status LED flash. This does not prove the tracker failed to recognize every
earlier attempt (the LED can also be obscured), but it means recognized gestures
were not established as a positive control. Google's [Air guide](https://support.google.com/googlehealth/answer/17033101?hl=en)
documents a firm double-tap waking the status light, and double-tap alarm
dismissal. It does not document a phone-facing gesture API.

The example now guides a 30-second secure-event trial: five seconds of quiet,
20 seconds for spaced double-taps, then five seconds of quiet. A user can mark
an observed LED flash while the capture is active. These timestamped manual
markers are explicitly distinguished from Bluetooth events and stay in the
bounded local log. A marker is delayed by the user's reaction time and is not
an exact sensor timestamp. This instrumentation is not a tap detector.

Additional source tracing narrowed the remaining leads:

- `GoldenGateCommandHandler.registerResourceHandlers()` registers both
  `events` (GROUP_1) and `eventsSecure` (GROUP_0), using the same event decoder.
  `StackPeer.getDtlsEventObservable$lambda$0$4` changes the local filter to
  GROUP_0 only when the session identity is neither `BOOTSTRAP` nor `hello`.
  The current monitor covers `events` in the bootstrap session. This is not
  evidence that `eventsSecure` carries taps, nor that changing our local filter
  changes the tracker's authorization or event emission behavior.
- `agxl` maps `phy` (`TRACKER_TAP_SUCCESS`) into `agjq` (`TrackerTapped`). Its
  producer is `pwl` receiving `pid.TAPPED`; `ooi` emits that result after
  `oxu.showPairingCodeOnDevice(TAP)` completes `ozn`, named
  `DisplayClassicPairConfirmation`, using `AirlinkPacketDecoder`. This is a
  classic pairing flow. The Golden Gate `PairCommandsHandler` instead sends
  `PUT pair/display` and maps success to `DISPLAYED_CODE`, not `TAPPED`.
  No pairing operation was invoked during this investigation.
- `AspenRemoteUi.AspenInfo.AspenState` describes heart-rate-sharing states
  (`SHARING_HR`, `SHARING_PAUSED`, connection/session states). The feature name
  is not evidence for remote gesture input.
- The inspected `LiveActivity.Activity` schema exposes summary activity/heart
  rate fields, not raw acceleration samples. Its existence therefore does not
  establish a route for implementing our own accelerometer tap classifier.

Next evidence needed: repeated LED-confirmed taps correlated with incoming
events and compared against quiet/movement controls. If the bootstrap path
still has no signal, a read-only capture of the normal Google Health session
can test whether recognized taps cause traffic at all, though encrypted
traffic timing alone cannot establish a reliable gesture decoder. A useful
package API still requires identified semantics, false-positive tests and
coexistence verification; it is not implemented yet.

### Additional incoming routes and WRS_ON receipt

The diagnostic monitor now registers observers for the other phone-side routes
traced in `GoldenGateCommandHandler`: `eventsSecure`, `sync/request`, `md/3d02`,
`md/1802`, `sb/reply` and `sb/delete-records`. They return `4.04`, retaining the
response used when those routes were absent from this endpoint. This differs
from Google Health's full handlers, which can acknowledge and act on requests.
These local GROUP_1 observers do not issue requests to tracker resources or
obtain a normal paired key. Only the bounded `eventsSecure` event-ID schema is
decoded; other probes return method, route label and byte count. Raw bodies are
not returned to Dart or written to the repository. Route labels identify the
registered prefix, not arbitrary URI suffixes.

An earlier completed 30-second trial recorded five six-byte `eventsSecure`
POSTs and two manual wrist-removal/replacement markers. Those bodies were not
retained and therefore cannot be retrospectively decoded. Repeated requests
may include retries after rejection; their count alone is not an event count
or evidence of gestures.

The later release capture started at phone time 13:17:21.988 and completed
after 30004 ms. It received `RSET` on `events`, a 12-byte `eventsSecure` POST
decoded as `[WRS_ON, RSET]` about 447 ms after ready, a 35-byte `sync/request`
POST, then `BSNC` on `events`. No posts exceeded the limits. The user reported
missing this physical trial; no manual markers were recorded. This establishes
receipt of an on-wrist event in the bootstrap session, but not physical
transition timing or tap detection. The route name and Google Health's local
GROUP_0 policy did not mean the Air would never send the route in this session.

A subsequent user-started trial ran for 30002 ms with two manual markers, one
POST on `events`, four observed requests on other routes, and none dropped.
It received an initial `WRS_ON`, then `[WRS_ON, RSET]`, followed by `WRS_OFF`
at about +10.0 seconds and `WRS_ON` at about +18.1 seconds. The user marked
removal at +11.6 seconds and replacement at +23.6 seconds and confirmed both
actions. Both reports preceded their manual markers; those reaction delays
prevent a sensor-latency estimate. This is hardware evidence for both presence
states in a physical removal/replacement trial, not a tap signal or validation
of continuous monitoring. The experimental `watchWristPresence()` Dart stream
filters only these source-traced IDs from the two EventSet routes, preserves
order and repeated reports, and retains the same bounded capture lifecycle.

A subsequent user-started tap trial covered 30001 ms. It received one `RSET`
POST on `events` and one `RSET` POST on `eventsSecure`, with no later event or
other observed route request, no dropped messages and no LED markers. The user
confirmed performing the taps and reported no LED flash. Thus adding the
second route did not identify a tap signal in this trial, while recognition
of the physical gestures remained unconfirmed. It does not justify treating
RSET or wrist-presence transitions as taps, or concluding that recognized taps
can never be observed. No further automatic capture was started afterward.

Connection reliability remains open. In the preceding attempts, one connection
timed out during secure-session setup and another received `RSET` before
Android reported a disconnect with status 257. The latter lasted less than a
second after ready. That status does not establish the underlying cause or
whether Google Health contributed. Charging/unplugging had been reported by
the user, but no causal relationship was established. Interrupted captures now
emit partial counts and actual observation milliseconds before their error;
zero coverage means the observer never reached ready. These failures cannot be
used as negative gesture trials. No pairing or Google Health settings changes
were performed to obtain these observations.

## Credential provisioning confirmation

`qax.run()` case 5 obtains JSON through the app's authenticated service using
`user/-/devices/device/<deviceId>` and the `keys` subresource. It reads
`data.attributes.primaryKey` and `secondaryKey`, each containing `key` and
`keyId`, Base64-decodes both keys, and stores them as AES SecretKey entries.
It then persists the BKS through `openFileOutput()` and `keyStore.store()`.
`qpa.call()` simply invokes `oyh.e.d().k()` to load the store. Thus these bytes
are fetched, not derived from the Bluetooth address or android_id. The latter
participates in local keystore protection, not key generation. Two named keys
do not by themselves prove the rotation schedule. No provisioning calls were
made and no credentials were extracted during this work.

The optional diagnostic stream subscribes to notifications/indications in
`ABBAFD00-E56A-484C-B832-8B17CF6CBFE8` (link status) and
`4EEE1C00-4133-479B-8663-02C84BDC14BE` (unclassified). It deliberately excludes
the tracker/DTLS service and writes only subscription descriptors. Seven
subscriptions succeeded on the tested Air; two initial link-status values
arrived. During the physical double-tap trial, the peripheral terminated the
connection (HCI reason 0x13, Android GATT status 257). Google Health reconnected
with the existing bond. No tap-correlated payload was established. The cause
and exact timing relative to the taps remain unresolved; this is inconclusive,
not proof that taps cannot be observed.

A later passive observation stayed connected through the observation window
with all seven subscriptions accepted. It received only one link-configuration
notification and no identifiable tap payload. The requested physical sequence
was not confirmed before cleanup, so this is not a completed negative tap
trial. The monitor was explicitly stopped to release its Bluetooth client.

## Battery source lead

The tested Air has no standard Battery Service. Decompiled Google Health
`CoapRequestUtils.providePathForProtocol()` maps protocol numbers to hexadecimal
`/md/` resource paths, and `ProtobufTranslatorsRegistry` maps decimal 1542
(0x606) to `DeviceInfoTranslator`. This identifies `/md/606` as a candidate
device-information resource, with `DeviceInfo.Info` fields `onCharger = 10`,
`voltage = 12`, and `batteryLevel = 13`.

A read-only hardware probe subsequently returned CoAP `2.05 Content` through
the bootstrap path. This resource is therefore accessible on the tested Air;
it must not be grouped with the rejected `liveactivity` resource. The optional
diagnostic API exposes only access status and these selected battery fields,
not the original body or its device identifiers. The selected fields were also
decoded on hardware; battery level was close to Google Health's displayed
percentage, but no across-firmware scale or voltage calibration was established.
Its small protobuf decoder
skips unrelated fields, rejects malformed/truncated data and preserves missing
values as absent. Units and scale remain unverified, so no percent conversion
or voltage units are claimed yet. Standard GATT device-info reads still do not
open a Golden Gate session merely to populate batteryPercent.

Other candidates—notifications, alarms, battery alerts, sync status, and the
ping characteristic—must be traced and tested individually. They should not be
added to the stable Dart surface until their payload, side effects, credential
requirements, cleanup, and Google Health coexistence are verified.
