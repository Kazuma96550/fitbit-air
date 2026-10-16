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

## Notifications → Air (Google Calendar, WhatsApp, and other apps)

The example includes an optional Android notification relay. No cloud account,
notification-provider API credentials, or server is needed. Google Calendar is
selected by default; use **Choose notification apps** to select WhatsApp,
WhatsApp Business, Signal, Outlook, or other installed apps with launcher entries.
The app selection is saved on the phone, and only explicitly selected apps relay.
Stop the relay before changing the selection. At least one app must be selected.
The demo discovers launcher apps without requesting `QUERY_ALL_PACKAGES`.

1. Pair the Air in Google Health and enable Bluetooth.
2. Enable notifications for the source apps you want to test.
3. In the demo, select **Open notification access settings** and enable
   **Notifications to Fitbit Air** (previously **Calendar to Fitbit Air**).
   Return and wait for access to show connected. Updating the existing demo
   keeps the same listener identity and should retain the access grant.
4. Expand **Choose notification apps** and select **WhatsApp** or your other
   source apps. Deselect Google Calendar if you want WhatsApp only.
5. Select **Start notification relay**, grant Nearby devices permission if asked,
   and allow the demo's notification permission so its ongoing notification is
   visible. Wait until the demo says it is listening; press Home or lock the phone.
6. Have someone send a WhatsApp message. Confirm a phone notification appears;
   the Air should give the restore-safe **two-pulse** vibration. Send a second
   message to the same chat to test notification updates. Muted chats, disabled
   notifications, and messages viewed in the open chat might not post an alert.
   For Calendar, create a new event with a reminder a few minutes away instead.
7. Stop using **Stop notification relay** or the ongoing notification's **Stop**
   action. An active haptic finishes restoration first.

Only alerts posted after the worker is ready are eligible. Other apps, group
summaries, ongoing notifications and old notification reposts are ignored.
On Android 11+, for standard MessagingStyle notifications, a newer message timestamp
allows another haptic command from the same chat key, including chats already present at
startup. Repeated or older timestamps do not pulse again. One updated
notification may contain several messages and still produces one haptic command.
This depends on the source app's notification format: if it does not expose
message timestamps (or on Android below 11), updates to the same notification key
remain suppressed.
WhatsApp's physical notification behavior still needs validation on your phone.

The filter tracks at most 256 notification keys per session without evicting old
keys. At capacity, new keys are rejected, while newer messages on tracked chats
remain eligible. Commands expire after 30 seconds while queued, are rate-limited,
and are never automatically retried. Rejected or failed work may produce no
vibration. SDK completion verifies the protocol result, not physical delivery.

Android grants notification access broadly; filtering happens locally before
extracting selected apps' message timestamps. Message text, sender names, and
calendar titles are not forwarded to Flutter or stored. Only selected package
IDs and the latest outcome are persisted locally. The relay uses a user-started
connected-device foreground service and a separate Flutter engine, with a
bounded wake lock only while processing work. Other device controls are disabled
while relaying. Explicitly start it again after reboot, process death, access
revocation, or force stop. Repeated deep-idle delivery and Google Health
coexistence still require physical validation.
