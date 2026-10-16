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
APK builds and device integration tests run on a development machine or CI,
never on the shared VPS. Follow [resource limits](../AGENTS.md).

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

This example feature is independent of the published 0.1.2 plugin. The demo
version is `0.1.3-dev.1`. It supports WhatsApp and WhatsApp Business only;
other app selections retain their existing behavior.

1. Stop the relay and keep notification access connected.
2. Select WhatsApp (or WhatsApp Business) in **Choose notification apps**.
3. Expand **WhatsApp conversations** and enable **Only selected WhatsApp chats**.
   An empty list allows no WhatsApp notifications; it never means “allow all”.
4. Tap **Capture chats for 60 seconds**. Close the WhatsApp chat and have the
   chosen person send a fresh notification. Capture works while the demo is in
   the background and does not start the relay or vibrate.
5. Return before capture expires and select the observed chat. The name is only
   a label; the short ID suffix helps distinguish identically named chats.
6. Start the relay and test a fresh message with the phone locked. Have another
   person send a message too: that unselected chat should not vibrate.

Selecting a direct chat provides person-level filtering. Selecting a group
allows **all senders in that group**, not one member. Sender matching inside a
group is not implemented. Calls/other notifications without a selected chat ID
are skipped in restricted mode. This is an experimental notification relay,
not a delivery guarantee; WhatsApp must actually post a usable notification.

Matching uses the notification's Android shortcut/conversation ID, namespaced
by app and stored as SHA-256. It never falls back to contact names, phone
numbers, notification keys or old messages in notification history. Missing
IDs fail closed, with an unsupported-metadata hint during capture. If WhatsApp
changes an ID, remove the old selection and capture again. Android 8+ can expose
shortcut IDs; availability on a particular WhatsApp/version/privacy setting
requires physical testing. Existing freshness, summary/ongoing suppression,
startup baseline and duplicate checks still run before chat matching.

Capture is explicit, bounded to 32 observed chats and 60 seconds using a monotonic
clock. Unsaved candidates are discarded at expiry, capture stop, listener
disconnection or relay start; they do not survive process death. Up to 64 selected
names and hashed IDs persist in app-private preferences until removed or app data
is cleared. Message bodies and sender-message history are not read by capture.
Conversation preferences are excluded from cloud backup and device transfer on
supported Android versions. The restriction toggle is stored separately, so a
restored restricted setup with no chats remains restricted. Clearing chats does
not turn off the restriction. Existing relay selections and notification access
are retained on upgrade.

Reports include only restriction state and selected-chat count, never the names,
raw/hashed IDs or candidate list. Existing relay metadata history remains
unchanged. Trial/operation errors must not embed conversation metadata.

For agent-driven local setup, use `DemoController.configureConversations` with
`captureConversations` (`enabled`), `restrictConversations` (`enabled`),
`selectConversation` (`id`, `enabled`), or `clearConversations`. The native bridge
and controller reject mutations while the relay is running. Stable UI keys are
`conversation-picker`, `restrict-conversations`, `capture-conversations`,
`conversation-list`, `conversation-<id>` and `clear-conversations`. Capture data
is available only in local controller state, not sanitized reports. Do not copy
private labels/IDs into test logs or PRs.

Physical acceptance for this feature remains pending: test allowed versus
unselected direct chats, repeated messages in one chat, a selected group versus
an unselected group, Business/app separation if installed, and missing metadata
with private notifications. Also test capture expiry/stop, process restart,
selection removal/clear, all-chat mode, and unchanged Calendar behavior. Confirm
reports omit real chat identities. Local policy/widget tests cannot establish
which conversation metadata WhatsApp supplies on a paired phone.
