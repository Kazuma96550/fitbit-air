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

## Google Calendar → Air

The example includes an optional Android notification relay. No Google login,
Calendar API credentials, calendar database permission, or server is needed.

1. Pair the Air in Google Health and enable Bluetooth.
2. Make sure Google Calendar notifications are enabled and your test event has
   a reminder. Confirm Calendar actually posts that reminder on the phone.
3. In the demo, select **Open notification access settings** and enable
   **Calendar to Fitbit Air**. Android grants access to notifications broadly;
   the demo filters locally to Google Calendar and never reads or stores event
   titles or notification text. Return and wait for access to show connected.
4. Select **Start calendar relay**, grant Nearby devices permission if asked,
   and allow the demo's notification permission so its ongoing notification is
   visible. You can now press Home or lock the phone.
5. Create a new event with a reminder a few minutes away. Its new Google Calendar
   notification should trigger the restore-safe **two-pulse** vibration.
6. Stop using the demo's **Stop calendar relay** button or the ongoing
   notification's **Stop** action. An active haptic finishes restoration first.

Only alerts posted after the relay worker is ready are eligible. Existing
notifications, group summaries, ongoing notifications, other apps, and updates
of a previously seen notification key are ignored. The filter remembers at most
256 keys per session and rejects additional keys once full; restart the relay
for a new session. Google Calendar reusing a notification key can suppress a
later reminder in that session. Commands expire after 30 seconds while queued,
are rate-limited, and are never automatically retried. Rejected or failed work
may therefore produce no vibration. SDK completion verifies the protocol result,
not that someone physically felt it.

The relay uses an explicitly started connected-device foreground service with a
separate Flutter engine. A bounded wake lock is held only while processing work.
Other device controls are disabled while relaying. It does not automatically
restart after reboot, process death, notification-access revocation, or force
stop: open the demo and start it again. No calendar contents are persisted; only
the latest status is stored locally. Google's private Bluetooth protocol and
Android power management still limit reliability; repeated deep-idle delivery
and Google Health coexistence require physical validation.
