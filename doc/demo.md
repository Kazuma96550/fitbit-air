# Demo operation and agent-driven trials

The example remains the reference app for `fitbit_air`; app permissions,
notification filtering and Android lifecycle management are not package APIs.

## Screens

- **Relay:** permission/Bluetooth/pairing setup, selected apps with search and
  icons, Start/Stop, Test vibration, and recent command activity. Selected apps
  sort first. Test vibration uses the existing relay worker while the relay is
  listening; when stopped, it uses the shared device preview action.
- **Device:** pairing, haptic controls, device information and heart rate.
- **Lab:** all existing diagnostic monitors, resource probes, headless tests,
  timed wrist-presence/alarm trials, manual markers and structured trial results.

The owner banner always identifies a running operation or relay session. Merely
opening Device/Lab does not stop the relay. An exclusive device action asks
whether to stop it, waits for any active command's verification/restoration, and
leaves the relay stopped afterward. Cancelled/incomplete trials keep their
partial observations. Haptic writes cannot be cancelled mid-restoration.

Secure-event observation can be set to 30, 60 or 90 seconds and is saved on the
phone. The guided wrist-presence and alarm trials retain fixed 30/90-second
windows. Manual markers remain separate from device-reported events. Neither a
successful command nor an absence of events establishes a physical sensation or
a negative gesture result.

## Shared controller and stable controls

`example/lib/demo/demo_controller.dart` exposes the same named actions used by
the buttons. A device integration test can pass a `DemoController` to `DemoApp`,
wait for `initialized`, inspect `actionIds`, and invoke `runAction(id)`.

Core IDs: `checkPaired`, `preview`, `pulse`, `setLow`, `setHigh`, `readDeviceInfo`,
`scanHeartRate`, `watchHeartRate`, `watchDeviceEvents`, `watchSecureEvents`,
`wristPresenceTrial`, `alarmTrial`, `probeBattery`, `probeResources`,
`headlessHaptic`, `headlessRead`. Heart-rate discovery additionally registers
`readHeartRate0`/`watchHeartRate0`, etc.; these indices are local to a scan and
are not persistent sensor identities.

A second operation is rejected while one is active or the relay owns the
transport. Tests must explicitly call `stopRelayAndWait()` before an exclusive
action. A finished Future does not by itself establish success: inspect the latest
trial's `outcome` and `errorCode`. Streams remain active until completion or `cancelCurrent()`; that
method is a control action, not a second device operation. There is no automatic
retry for an ambiguous device write and no arbitrary outgoing protocol command
endpoint in the release APK.

Stable Flutter keys are part of the demo's test interface:

| Purpose | Key |
|---|---|
| Navigation | `nav-relay`, `nav-device`, `nav-lab` |
| Ownership and cancellation | `operation-owner`, `cancel-operation` |
| Relay controls | `relay-toggle`, `relay-status`, `test-vibration` |
| App selection | `app-picker`, `app-search`, `app-<packageName>` |
| Device/research action | `action-<actionId>` |
| Saved observation duration | `secure-duration` |
| Confirm/decline relay stop | `stop-relay-for-operation`, `keep-relay` |
| Physical user observation | `marker-felt-vibration`, `lab-marker-felt-vibration` |
| Report export | `export-report`, `lab-export` |

Buttons also have descriptive labels and status updates use accessibility live
regions. Android UI tools can use those labels; Flutter integration tests should
prefer keys or controller action IDs. Do not rely on screen coordinates or
notification titles.

## Structured reports and privacy

**Copy sanitized report** copies JSON to the clipboard. It contains schema/demo
versions, export time, up to 100 relay history entries, the last 20 in-memory
trials (up to 100 observations each), and up to 100 standalone manual markers.
Relay history survives an app process restart; trial results do not, so export
before ending a research session. Clear relay history removes only that history.

Trial records include operation/parameters, phone start/end timestamps, duration,
outcome, error code and bounded observations. Interruption records retain actual
reported observation coverage. Known device model/firmware and protocol event
IDs/names can appear; raw BLE payloads, Bluetooth addresses/sensor IDs, account
data, notification contents and sender names are not included. Heart-rate
receipt timing can be recorded, but readings are not exported. Source application
package IDs and command timings remain in relay history. Treat exports as
research data and review them before sharing.

Relay stages distinguish `detected`, `queued`, `verified`, `expired`,
`queue_full`, `failed`, `cancelled`, `duplicate`, and `interrupted`. Total latency
includes queue time and Bluetooth setup. `verified` is a protocol receipt, not
proof someone felt vibration. A process killed without cleanup can leave a
`queued` entry without a terminal result; do not infer delivery or replay it.

## Running integration scenarios on a Mac or test machine

Run from `example/`, with a connected Android phone, the Air already paired in
Google Health, and Nearby devices access granted. Run one trial at a time. The
integration test never re-enables a stopped relay.

```bash
# Navigation and setup only; no device commands or haptics.
flutter test integration_test/demo_smoke_test.dart -d YOUR_DEVICE_ID

# Opt in to a read-only device-information trial.
flutter test integration_test/demo_smoke_test.dart -d YOUR_DEVICE_ID \
  --dart-define=AIR_DEVICE_TESTS=true

# Explicitly opt in to one restore-safe two-pulse haptic as well.
flutter test integration_test/demo_smoke_test.dart -d YOUR_DEVICE_ID \
  --dart-define=AIR_DEVICE_TESTS=true --dart-define=AIR_HAPTIC_TESTS=true
```

To save the structured result to `example/build/air-demo-report.json`, use the
included host driver (same opt-in flags):

```bash
flutter drive --driver=test_driver/demo_driver.dart \
  --target=integration_test/demo_smoke_test.dart -d YOUR_DEVICE_ID \
  --dart-define=AIR_DEVICE_TESTS=true
```

The driver writes sanitized reports on success and assertion failure. An active
operation when the harness ends is recorded as interrupted, not successful. The
binding exposes `reportData` to that integration driver. For interactive
trials, use the copy button and physical manual markers. Default automation must
not claim physical confirmation or send haptics without the explicit haptic flag.
APK builds run on a development machine or CI. Device integration tests require
a connected test phone.

## 0.1.2 acceptance and release

Before merge/publication, run CI package checks and the release APK build, then
record the following on a paired phone:

- Upgrade without losing selected apps or notification access; navigate all
  three screens and verify opening Lab leaves the relay running.
- Trigger a Calendar reminder and two separate WhatsApp messages in the same
  chat with the phone locked. Compare detection/queue/result history and actual
  sensation. Check an unselected app does not buzz.
- Use Test vibration with the relay both on and off. Confirm the two-pulse
  behavior/restoration and mark physical sensation separately.
- Start a Lab operation while relaying, decline once, then accept. Ensure an
  in-flight haptic finishes before the Lab operation starts; resume explicitly.
- Complete and cancel a bounded secure-event trial. Confirm saved duration,
  manual markers, partial/interrupted outcomes, and sanitized export.
- Check unavailable Air/Bluetooth-off/notification-access revocation and cleanup;
  do not repeatedly retry uncertain writes. Confirm Google Health still works.

Record phone/Android, Air firmware and Google Health versions alongside exact
steps and observations. A user reported successful WhatsApp relay operation on
2026-10-16; detailed versions and a structured trial report were not captured.
That smoke report does not establish idle/reboot/overnight reliability. This UI
revision needs its own physical acceptance test. Tag/publish 0.1.2 only after that
checklist passes. Automatic reboot recovery and durable replay protection remain
future work.

## Selected WhatsApp conversations (after 0.1.2)

This example-only feature is independent of the published 0.1.2 plugin. The demo
is `0.1.3-dev.2` and the app bar shows `dev.2`. It supports WhatsApp and WhatsApp
Business; other app selections retain their existing behavior.

1. Stop the relay. In **Choose people**, enable WhatsApp notifications if needed
   and turn on **Only selected WhatsApp chats**. An empty list allows no WhatsApp
   notifications; it never means “allow all”.
2. Leave a WhatsApp message unread and tap **Find chats**. The app immediately
   inspects currently visible WhatsApp notifications, then listens for new ones
   for up to 60 seconds. Capture never vibrates. You can close the demo and have
   the chosen person send a notification while their WhatsApp chat is closed.
3. Select the observed chat. Results remain available for five minutes after
   listening ends or you tap **Stop listening**. You no longer have to return
   within the 60-second listening window.
4. An available **Conversation ID** rule matches the app-scoped Android shortcut
   ID. Existing selections from dev.1 keep their original IDs.
5. If WhatsApp provides message-notification metadata and a chat title without
   a conversation ID, the app offers an **Exact name** rule. Enabling it requires
   explicit confirmation. It matches the exact notification chat title and can
   match any other chat with the same title. Rename changes can stop matching;
   title formats may vary between notification updates. This is a less reliable
   option, not an equivalent stable identity. The native bridge also requires
   `allowNameMatch: true` before saving such a rule. No silent downgrade occurs.
6. Start the relay and test a fresh message with the phone locked. Have someone
   from an unselected chat send a message too: that chat should not vibrate.

Selecting a direct chat provides person-level filtering. Selecting a group allows
**all senders in that group**, not one member. Sender matching inside a group is
not implemented. Duplicate chat titles are ambiguous for exact-name rules: use
conversation IDs when available or avoid selecting ambiguous names. Name rules
use the current notification's conversation title (or title), never any sender
found in historical messages. They require message metadata; generic app titles,
blank titles and titles longer than 512 characters are rejected. Nonmatching or
unusable metadata is skipped in restricted mode. WhatsApp must actually post a
usable notification; this experimental relay is not a delivery guarantee.

**Troubleshooting** retains safe counts for notifications seen, unread snapshot,
summaries, ongoing notifications, missing IDs, usable name-only candidates,
unusable metadata and parse/access errors. These counts distinguish “listener
received nothing” from “received an unsupported notification”. They remain visible
after listening ends and can be copied with **Copy sanitized debug report**.
Counts contain no names, IDs, notification keys, titles, or message text. Snapshot
inspection is capture-only: it never queues haptics. Relay startup still records
existing notifications as a baseline, and freshness/duplicate checks still apply
to newly posted notifications.

Capture holds up to 32 candidates in memory. Unsaved results are discarded after
the selection window, listener disconnection, relay start, explicit forgetting or
process death. Up to 64 selected names and hashed rule IDs persist in app-private
preferences until removed or app data is cleared. Message bodies are not read by
capture. Conversation preferences are excluded from Android cloud backup and
device transfer. The restriction toggle is stored separately, so a restored
restricted setup with no chats remains restricted. Forgetting chats does not
turn off the restriction. Existing app selections and notification access survive
an upgrade.

Reports include only restriction state, selected-chat count and allowlisted
numeric capture diagnostics, never names, IDs or candidate lists. Raw shortcut
IDs and exact title rules are hashed with app/type namespaces before storage.
The preexisting stable-ID hash format is preserved for upgrades.

For agent-driven local setup, use `DemoController.configureConversations` with
`captureConversations` (`enabled`), `restrictConversations` (`enabled`),
`selectConversation` (`id`, `enabled`, optional explicit `allowNameMatch`), or
`clearConversations`. The native bridge and controller reject mutations while
the relay is running. Stable UI keys include `conversation-picker`,
`restrict-conversations`, `capture-conversations`, `conversation-<id>`,
`confirm-name-match`, `cancel-name-match`, `capture-diagnostics`,
`capture-details`, `copy-capture-report` and `clear-conversations`. Private
capture data is available only in local controller state; do not copy names/IDs
into test logs or PRs.

Physical acceptance remains pending. Test active/unread notification discovery,
new messages, return after the listening window, missing-ID diagnostics, name-rule
confirmation/cancellation, allowed versus unselected chats, repeated messages,
selected/unselected groups, Business/app separation, private notifications,
process restart, removal/forgetting, all-chat mode and unchanged Calendar behavior.
Inspect reports for identity leaks. Local tests cannot establish what metadata
WhatsApp supplies on the paired phone.

### Investigating Health sync after relay use (dev.3)

The copied debug report now includes `transport`: the app-local lease and the
last 16 command cleanup traces across UI and worker engines. Each fixed cleanup
step reports `returned`, `failed`, or `not_present`. No exception text, device
address or notification content is retained. `returned` confirms only that the
API call returned, not a physical disconnection or a healthy tracker session.
Passive device-event monitor teardown is outside the trace scope. History is
memory-only and resets when the app process exits; copy it before force-stopping.

1. With relay off, verify Google Health can sync.
2. Start relay, send one allowed notification and verify vibration.
3. Stop relay, wait until it says off, then try Health sync again.
4. If sync fails, return to the demo and copy the debug report before changing
   Bluetooth or force-stopping. Note whether sync also failed while relay was on.
5. Force-stop the demo in Android Settings and retry Health sync. If still stuck,
   toggle Bluetooth off/on and retry. Report which step restored sync.

A quiet relay should not intentionally retain its command GATT client for 15
minutes. Failed teardown is one hypothesis; shared Bluetooth or tracker protocol
state is another. These diagnostics do not automatically reset Bluetooth or the
tracker, and are not a confirmed fix for Health sync failures.

Dev.4 serializes command GATT callbacks on the main lifecycle thread and checks
session identity after queueing, including native outgoing packets, DTLS-ready
notifications and operation completions. Cleanup invalidates session identity
before disposing native resources. Partially constructed sinks and endpoints
are registered for cleanup before subsequent initialization can throw. Regression
tests exercise callbacks arriving during setup, after cleanup and after a new
session replaces the old one. These address code-level races, not a confirmed
explanation or fix for Google Health error 3000. Test both idle relay-on sync and
sync after stopping; a vibration still opens a separate secure tracker session
which can contend with Health during the operation.

### Root cause and fix (dev.5)

Logcat from both apps on the paired phone established the cause. The Air
exposes a single Gattlink/DTLS channel (`ABBAFF01`/`ABBAFF02`) and every GATT
client on the shared BLE link receives its notifications. When the SDK opens
its session, the Air resets that channel and its DTLS handshake; Google Health
logs `unexpected reset complete`, foreign packet sequence numbers, and its own
`resetting DTLS`. Our handshake completes; Google Health's does not. After the
SDK disconnects, Google Health logs `Data Ack Timeout` and `max resend count
reached` until its watchdog disconnects and reconnects about 60 s later. Any
sync in that window fails, and repeated relay vibrations extend the outage.

The Air retries a failed handshake by resetting the link for all clients and
offering its other identity (normal mobile key ↔ bootstrap key). Dev.5 uses
this: after each DTLS operation, the plugin starts a short handoff session
whose key resolver refuses every identity. When the Air resets the link
(`GattlinkSessionResent`), the plugin stops transmitting before replying and
closes. Google Health resynchronizes and handshakes alone, without a
disconnect. If no reset arrives within 10 s, the plugin closes as before.

Each command's entry in the debug report's `transport.cleanupHistory` now
includes `channelHandoff`: `reset_observed` (handed back), `deadline` (the Air
did not reset; Google Health may again need its ~60 s reconnect), `link_lost`,
`failed` or `interrupted`. Operations without a DTLS session omit it. The
handoff depends on observed Air firmware behavior, not a documented contract.
On other phones or firmware, a report with `deadline` or `failed` is the
signal that it does not apply there; the command result is unaffected.

Measured on 2026-10-16 (Pixel 7 Pro, Android 17, Google Health 5.10.1):
without the handoff, Google Health was out of sync for 57–61 s after each
vibration. With it, Google Health restarted DTLS at the handoff and logged
no ack timeouts or watchdog disconnects in five vibrations: four from the UI
engine (three with Google Health in the foreground polling the Air) and one
from the running relay worker. Google Health sometimes performs one more
DTLS restart 5–20 s later without errors; its cause is not established. During the
command itself (about 5–15 s) the two apps still compete for the channel;
that window is inherent to a second session on the same tracker channel.

### Burst merging (dev.6)

Each relay command still competes with Google Health while it runs. The relay
service therefore merges bursts: the first alert dispatches immediately;
alerts arriving while a command runs, or within 20 s after it finishes, are
recorded as `merged` and represented by one follow-up command sent when that
cooldown ends. Five messages in quick succession produce two vibrations, not
five. The follow-up's latency is measured from its earliest merged alert and
it gets a fresh 30 s expiry. Stopping the relay cancels a waiting follow-up
(`cancelled`). The wake lock and the per-command watchdog are held while a
follow-up waits; the watchdog is re-armed on each dispatch so a long chat
does not trip it. The decision logic is the Android-free `RelayCoalescer`,
covered by unit tests. On a Pixel 7 Pro, two test vibrations 1.5 s apart ran
as one immediate session and one follow-up 20 s later, each with
`channelHandoff: reset_observed`.

### Measured cooldown, link speed and handshake races (dev.7)

Manual Google Health syncs pressed relative to the handoff, on a Pixel 7 Pro
(spaced 2.5 min apart so Google Health would not throttle them):

| Sync pressed | Result |
|---|---|
| No vibration | Completed in ~10 s |
| 4.5 s / 3.9 s before handoff (during the command) | Failed once; once completed after 17.5 s |
| 4.1 s after handoff | Completed in 8.4 s |
| 10.5–17 s after handoff | Completed in 5–11 s |

Google Health needs no recovery time after the handoff. The cooldown protects
a sync that has started from being interrupted by the next session; 15 s
covers the longest measured sync. A follow-up therefore starts at most about
20 s after its oldest merged alert in normal operation, and keeps a fresh 30 s
expiry. In the worst case (a hung command plus the 10 s handoff deadline) a
follow-up can run up to about 100 s after the oldest alert, or not at all.

Commands now request high connection priority for their own session and
restore low power afterwards (the Air or Google Health later choose their own
parameters). Ten consecutive commands took 4.0–4.8 s, down from 8.7 s, with
`channelHandoff: reset_observed` and no Google Health ack timeouts.

About one command in 15 lost a handshake race: after the Air resets its link,
Google Health and the SDK both answer the handshake and both stall. Before
dev.7 this produced no vibration and left Google Health stuck until the 45 s
timeout. A handshake missing after 6 s now gets one fresh attempt before
failing with `HANDSHAKE_TIMEOUT`. A test build that abandoned every first
attempt recovered in 4 of 4 runs without Google Health ack timeouts.
