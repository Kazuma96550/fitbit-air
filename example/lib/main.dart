import 'dart:async';

import 'package:fitbit_air/fitbit_air.dart';
import 'package:fitbit_air/fitbit_air_commands.dart';
import 'package:fitbit_air/fitbit_air_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const DemoApp());

/// Runs in a separate service-owned engine without any Flutter screen.
@pragma('vm:entry-point')
Future<void> airHeadlessTest() async {
  WidgetsFlutterBinding.ensureInitialized();
  const resultChannel = MethodChannel('fitbit_air_example/headless_result');
  try {
    final operation = await resultChannel.invokeMethod<String>('getOperation');
    await Future<void>.delayed(const Duration(seconds: 15));
    if (operation == 'readDeviceInfo') {
      final info = await FitbitAir.readDeviceInfo();
      await resultChannel.invokeMethod('complete', {
        'success': info.model != null,
        'operation': operation,
        'hasModelNumber': info.model != null,
      });
    } else {
      final dispatcher = AirHapticDispatcher();
      final command = AirHapticCommand(
        id: 'headless-${DateTime.now().microsecondsSinceEpoch}',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );
      final delivery = dispatcher.submit(command);
      // Simulate the same notification being delivered twice. Only one may run.
      final duplicate = await dispatcher.submit(command);
      final result = await delivery;
      dispatcher.close();
      await resultChannel.invokeMethod('complete', {
        'success': result.status == AirHapticDispatchStatus.completed,
        'status': result.status.name,
        'errorCode': result.error?.code,
        'error': result.error?.toString(),
        'duplicateDropped':
            duplicate.status == AirHapticDispatchStatus.duplicate,
      });
    }
  } catch (error) {
    await resultChannel.invokeMethod('complete', {
      'success': false,
      'error': error.toString(),
    });
  }
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fitbit Air demo',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff405e91),
      useMaterial3: true,
    ),
    home: const DemoPage(),
  );
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  bool _busy = false;
  bool? _paired;
  AirDeviceInfo? _deviceInfo;
  List<AirHeartRateDevice> _heartRateDevices = [];
  StreamSubscription<AirHeartRate>? _heartRateSubscription;
  StreamSubscription<AirDeviceEvent>? _deviceEventSubscription;
  StreamSubscription<AirSecureEvent>? _secureEventSubscription;
  final List<String> _eventLog = [];
  int _notificationCount = 0;
  final _scrollController = ScrollController();
  final _captureClock = Stopwatch();
  Timer? _captureTimer;
  int _captureSeconds = 0;
  int _captureDuration = 30;
  int _ledMarkers = 0;
  bool _captureReady = false;
  bool _wristPresenceTrial = false;
  bool _alarmTrial = false;
  String? _captureInterruption;

  void _stopCaptureClock() {
    _captureTimer?.cancel();
    _captureClock.stop();
    _captureReady = false;
  }

  void _markObservation(String observation) {
    if (!_captureReady ||
        _captureClock.elapsedMilliseconds >= _captureDuration * 1000) {
      return;
    }
    setState(() {
      _ledMarkers++;
      _eventLog.insert(
        0,
        '${DateTime.now()} · USER $observation '
        'at +${_captureClock.elapsedMilliseconds}ms (manual marker, not BLE detection)',
      );
      if (_eventLog.length > 20) _eventLog.removeLast();
    });
  }

  void _watchSecureEvents({bool wristPresence = false, bool alarm = false}) {
    _stopCaptureClock();
    setState(() {
      _busy = true;
      _eventLog.clear();
      _ledMarkers = 0;
      _captureSeconds = 0;
      _wristPresenceTrial = wristPresence;
      _alarmTrial = alarm;
      _captureDuration = alarm ? 90 : 30;
      _captureInterruption = null;
      _status = 'Opening secure event capture. Keep the Air on until READY.';
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    _secureEventSubscription =
        FitbitAirDiagnostics.watchSecureEvents(
          durationSeconds: _captureDuration,
        ).listen(
          (event) {
            if (!mounted) return;
            setState(() {
              _eventLog.insert(
                0,
                '${event.receivedAt.toLocal()} · CoAP ${event.kind} '
                '${event.path ?? ""} ${event.method ?? ""} '
                '${event.bodyLength == null ? "" : "${event.bodyLength} bytes "}'
                '${event.eventNames} ${event.eventIds}'
                '${event.observationMillis == null ? "" : " · observed ${event.observationMillis}ms"}',
              );
              if (_eventLog.length > 20) _eventLog.removeLast();
              if (event.kind == 'ready') {
                _captureReady = true;
                _captureClock.reset();
                _captureClock.start();
                _captureTimer = Timer.periodic(
                  const Duration(milliseconds: 250),
                  (_) {
                    if (!mounted) return;
                    setState(() {
                      _captureSeconds = _captureClock.elapsed.inSeconds;
                      if (_captureSeconds >= _captureDuration) {
                        _stopCaptureClock();
                      }
                    });
                  },
                );
                _status =
                    'Secure event monitor READY. Follow the timed instructions below. '
                    'Event acknowledgment: ${event.eventResponseCode ?? "unknown"}. No vibration commands.';
              } else if (event.kind == 'complete') {
                _stopCaptureClock();
                _status =
                    'Secure observation complete: ${event.receivedPosts} incoming POSTs, '
                    '${event.otherRequests ?? 0} other requests; '
                    '${event.droppedPosts} over diagnostic limit; '
                    '$_ledMarkers manual markers. Gesture detection remains unconfirmed.';
              } else if (event.kind == 'interrupted') {
                _stopCaptureClock();
                _captureInterruption =
                    'Incomplete trial: ${event.observationMillis ?? 0}ms observed, '
                    '${event.receivedPosts ?? 0} event POSTs, '
                    '${event.otherRequests ?? 0} other requests. '
                    'This is not a negative gesture result.';
              }
            });
          },
          onError: (Object error) {
            _stopCaptureClock();
            if (mounted) {
              setState(() => _status = '$error\n${_captureInterruption ?? ""}');
            }
          },
          onDone: () {
            _stopCaptureClock();
            _secureEventSubscription = null;
            if (mounted) setState(() => _busy = false);
          },
        );
  }

  Future<void> _probeResources() =>
      _run('Checking four read-only resources in one session…', () async {
        final results = await FitbitAirDiagnostics.probeReadOnlyResources();
        return results
            .map(
              (r) =>
                  '${r.path}: ${r.responseCode ?? r.errorCode} '
                  '(${r.bodyLength ?? 0} bytes)',
            )
            .join('\n');
      });

  Future<void> _headlessTest({bool readOnly = false}) async {
    setState(() => _busy = true);
    try {
      // Obtain runtime permission with the screen present, before service use.
      if (!await FitbitAir.isAirPaired()) {
        if (mounted) {
          setState(() => _status = 'Pair an Air in Google Health first.');
        }
        return;
      }
      await const MethodChannel(
        'fitbit_air_example/background',
      ).invokeMethod<void>('startTest', {
        'operation': readOnly ? 'readDeviceInfo' : 'vibrate',
      });
      if (mounted) {
        setState(
          () => _status =
              'Headless test scheduled. Press Home or lock the '
              'phone now. Operation starts in 15 seconds. Avoid other SDK operations '
              'until the test notification disappears.',
        );
      }
      for (var second = 0; second < 67; second++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        final outcome = await const MethodChannel(
          'fitbit_air_example/background',
        ).invokeMethod<String>('getLastResult');
        if (outcome != null) {
          setState(() => _status = outcome);
          break;
        }
      }
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void>
  _probeBattery() => _run('Probing read-only battery resource access…', () async {
    final result = await FitbitAirDiagnostics.probeBatteryAccess();
    return 'Battery access: CoAP ${result.responseCode}, ${result.bodyLength} response bytes.\n'
        '${result.granted ? "Raw level: ${result.rawBatteryLevel}; raw voltage: ${result.rawVoltage}; raw charger: ${result.rawOnCharger}. Units/scale unverified." : "Not accessible through this session."}'
        '${result.decodeError == null ? "" : "\n${result.decodeError}"}';
  });

  @override
  void dispose() {
    _stopCaptureClock();
    _scrollController.dispose();
    _heartRateSubscription?.cancel();
    _deviceEventSubscription?.cancel();
    _secureEventSubscription?.cancel();
    super.dispose();
  }

  void _watchDeviceEvents() {
    setState(() {
      _busy = true;
      _eventLog.clear();
      _notificationCount = 0;
      _status = 'Subscribing to diagnostic events…';
    });
    _deviceEventSubscription = FitbitAirDiagnostics.watchDeviceEvents().listen(
      (event) {
        if (!mounted) return;
        setState(() {
          if (event.isNotification) _notificationCount++;
          _eventLog.insert(
            0,
            '${event.receivedAt.toLocal()} · ${event.kind} '
            '${event.characteristicUuid ?? ""} '
            '${event.isNotification ? "${event.payload.length} bytes" : "status=${event.status ?? event.subscribedCount}"}',
          );
          if (_eventLog.length > 20) _eventLog.removeLast();
          if (event.kind == 'ready' || event.isNotification) {
            _status =
                'Monitoring device events. $_notificationCount notifications received. '
                'These events are not confirmed wrist taps.';
          }
        });
      },
      onError: (Object error) {
        if (mounted) setState(() => _status = error.toString());
      },
      onDone: () {
        _deviceEventSubscription = null;
        if (mounted) setState(() => _busy = false);
      },
    );
  }

  void _watchHeartRate([AirHeartRateDevice? device]) {
    setState(() {
      _busy = true;
      _status = 'Connecting to ${device?.name ?? "paired Air"}…';
    });
    _heartRateSubscription =
        FitbitAir.watchHeartRate(deviceId: device?.deviceId).listen(
          (heart) {
            if (mounted) {
              setState(
                () => _status =
                    '${heart.beatsPerMinute} bpm\n'
                    'Updated: ${heart.receivedAt.toLocal()}\n'
                    'Skin contact: ${heart.contactDetected ?? "Not reported"}',
              );
            }
          },
          onError: (Object error) {
            if (mounted) setState(() => _status = error.toString());
          },
          onDone: () {
            _heartRateSubscription = null;
            if (mounted) setState(() => _busy = false);
          },
        );
  }

  String _status = 'Check for an Air paired to this phone.';

  Future<void> _run(String pending, Future<String> Function() operation) async {
    setState(() {
      _busy = true;
      _status = pending;
    });
    try {
      final status = await operation();
      if (mounted) setState(() => _status = status);
    } on FitbitAirException catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _status = 'Checking Android paired devices…';
    });
    try {
      final paired = await FitbitAir.isAirPaired();
      if (!mounted) return;
      setState(() {
        _paired = paired;
        _status = paired
            ? 'Fitbit Air is paired to this phone.'
            : 'No paired Fitbit Air found. Pair it in Google Health first.';
      });
    } on FitbitAirException catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _vibrate() async {
    await _run('Sending a restore-safe two-pulse preview…', () async {
      final result = await FitbitAir.vibrate();
      return 'Two-pulse preview complete. Prior intensity '
          '${result.originalIntensity}; restored and verified: '
          '${result.restored && result.verified}.';
    });
  }

  Future<void> _pulse() async {
    await _run('Sending one haptic pulse…', () async {
      final result = await FitbitAir.pulse();
      return 'One pulse sent: ${result.previousIntensity.name} → '
          '${result.currentIntensity.name}; verified: ${result.verified}.';
    });
  }

  Future<void> _readDeviceInfo() async {
    await _run('Reading device information…', () async {
      final info = await FitbitAir.readDeviceInfo();
      if (mounted) setState(() => _deviceInfo = info);
      return '${info.name}\n'
          'Battery: ${info.batteryPercent == null ? "Not exposed" : "${info.batteryPercent}%"}\n'
          'Model: ${info.model ?? "Not exposed"}\n'
          'Firmware: ${info.firmware ?? "Not exposed"}\n'
          'Manufacturer: ${info.manufacturer ?? "Not exposed"}\n'
          'Link encrypted: ${info.connectionStatus?.encrypted ?? "Not reported"}\n'
          'MTU: ${info.connectionConfiguration?.mtu ?? "Not reported"}\n'
          'Interval: ${info.connectionConfiguration?.intervalMillis ?? "Not reported"} ms\n'
          '${info.services.length} BLE services discovered\n'
          '${info.readErrors.entries.map((e) => "${e.key}: ${e.value}").join("\n")}';
    });
  }

  Future<void> _scanHeartRate() async {
    await _run('Scanning for heart-rate sensors…', () async {
      final devices = await FitbitAir.scanHeartRateDevices();
      if (mounted) setState(() => _heartRateDevices = devices);
      return devices.isEmpty
          ? 'No heart-rate advertisements found. Open Share heart rate in Google Health, then scan again.'
          : 'Select your Air below to receive heart rate.';
    });
  }

  Future<void> _readHeartRate({required String deviceId}) async {
    await _run('Waiting for heart rate… Wear the Air on your wrist.', () async {
      final heart = await FitbitAir.readHeartRate(deviceId: deviceId);
      return '${heart.beatsPerMinute} bpm\n'
          'Skin contact: ${heart.contactDetected ?? "Not reported"}\n'
          'Received: ${heart.receivedAt.toLocal()}\n'
          'RR intervals: ${heart.rrIntervalsMillis.join(", ")} ms';
    });
  }

  Future<void> _setIntensity(HapticIntensity intensity) async {
    await _run('Setting ${intensity.name} vibration strength…', () async {
      final result = await FitbitAir.setHapticIntensity(intensity);
      return result.changed
          ? 'Intensity changed to ${intensity.name} with one pulse and verified.'
          : 'Intensity was already ${intensity.name}; no pulse was sent.';
    });
  }

  Widget _button({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fitbit Air · direct BLE demo')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: _scrollController,
            children: [
              const Icon(Icons.watch, size: 64),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 28),
              if (_captureReady) ...[
                Text(
                  _alarmTrial
                      ? 'Wait for the alarm, mark its start, then double-tap to dismiss. '
                            'Mark the attempt and whether vibration stopped. Then stay still until capture ends. ${_captureDuration - _captureSeconds}s left.'
                      : _captureSeconds < 5
                      ? 'Baseline: keep the Air still (${5 - _captureSeconds}s).'
                      : _wristPresenceTrial
                      ? (_captureSeconds < 15
                            ? 'Remove the Air now and mark it below. Keep it off until the next prompt.'
                            : 'Put the Air back on and mark it below. ${30 - _captureSeconds}s left.')
                      : _captureSeconds < 25
                      ? 'Double-tap, then mark the attempt below. Mark the LED separately if it flashes. '
                            'Space attempts at least 5 seconds apart. ${30 - _captureSeconds}s left.'
                      : 'Keep the Air still for the final ${30 - _captureSeconds}s.',
                  textAlign: TextAlign.center,
                ),
                if (_alarmTrial) ...[
                  _button(
                    onPressed: () =>
                        _markObservation('alarm vibration started'),
                    icon: Icons.alarm,
                    label: 'Mark: alarm started',
                  ),
                  _button(
                    onPressed: () => _markObservation(
                      'attempted alarm-dismissal double-tap',
                    ),
                    icon: Icons.touch_app,
                    label: 'Mark: dismissal double-tap attempted',
                  ),
                  _button(
                    onPressed: () =>
                        _markObservation('alarm vibration stopped after tap'),
                    icon: Icons.alarm_off,
                    label: 'Mark: alarm stopped after tap',
                  ),
                ] else if (_wristPresenceTrial) ...[
                  _button(
                    onPressed: _captureSeconds >= 5
                        ? () => _markObservation('removed Air from wrist')
                        : null,
                    icon: Icons.watch_off,
                    label: 'Mark: Air is off my wrist',
                  ),
                  _button(
                    onPressed: _captureSeconds >= 5
                        ? () => _markObservation('put Air back on wrist')
                        : null,
                    icon: Icons.watch,
                    label: 'Mark: Air is back on my wrist',
                  ),
                ] else ...[
                  _button(
                    onPressed: _captureSeconds >= 5 && _captureSeconds < 25
                        ? () => _markObservation('attempted double-tap')
                        : null,
                    icon: Icons.touch_app,
                    label: 'Mark: double-tap attempted',
                  ),
                  _button(
                    onPressed: _captureSeconds >= 5 && _captureSeconds < 25
                        ? () => _markObservation('observed LED flash')
                        : null,
                    icon: Icons.lightbulb_outline,
                    label: 'LED flashed — mark observed double-tap',
                  ),
                ],
                Text(
                  '$_ledMarkers manual markers; these are not detected gestures.',
                ),
              ],
              if (_busy)
                TextButton(
                  onPressed: () async {
                    try {
                      if (_heartRateSubscription != null) {
                        await _heartRateSubscription!.cancel();
                        _heartRateSubscription = null;
                        if (mounted) {
                          setState(() {
                            _busy = false;
                            _status = 'Heart-rate stream stopped.';
                          });
                        }
                      } else if (_secureEventSubscription != null) {
                        _stopCaptureClock();
                        await _secureEventSubscription!.cancel();
                        _secureEventSubscription = null;
                        if (mounted) {
                          setState(() {
                            _busy = false;
                            _status = 'Secure event capture stopped.';
                          });
                        }
                      } else if (_deviceEventSubscription != null) {
                        await _deviceEventSubscription!.cancel();
                        _deviceEventSubscription = null;
                        if (mounted) {
                          setState(() {
                            _busy = false;
                            _status =
                                'Device event monitor stopped. $_notificationCount notifications received.';
                          });
                        }
                      } else {
                        await FitbitAir.cancelOperation();
                      }
                    } on FitbitAirException catch (error) {
                      if (mounted) {
                        setState(() => _status = error.message);
                      }
                    }
                  },
                  child: const Text('Cancel operation'),
                ),
              if (_deviceInfo != null)
                ExpansionTile(
                  title: const Text('Bluetooth service details'),
                  children: [
                    for (final service in _deviceInfo!.services)
                      ListTile(
                        title: Text(
                          service.uuid,
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          service.characteristics
                              .map(
                                (c) =>
                                    '${c.uuid}\nread=${c.canRead}, notify=${c.canNotify}',
                              )
                              .join('\n'),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              if (_eventLog.isNotEmpty)
                ExpansionTile(
                  initiallyExpanded: true,
                  title: const Text('Diagnostic event log (local only)'),
                  children: [
                    for (final event in _eventLog)
                      ListTile(
                        title: Text(
                          event,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              _button(
                onPressed: _busy ? null : _check,
                icon: Icons.bluetooth_searching,
                label: _paired == true ? 'Check again' : 'Check paired Air',
              ),
              _button(
                onPressed: _busy ? null : () => _headlessTest(),
                icon: Icons.notifications_active,
                label: 'Headless test (two pulses after 15s)',
              ),
              _button(
                onPressed: _busy ? null : () => _headlessTest(readOnly: true),
                icon: Icons.info_outline,
                label: 'Headless read-only test (after 15s)',
              ),
              _button(
                onPressed: _busy ? null : _readDeviceInfo,
                icon: Icons.info_outline,
                label: 'Read device info + services',
              ),
              _button(
                onPressed: _busy ? null : _scanHeartRate,
                icon: Icons.radar,
                label: 'Scan heart-rate sensors',
              ),
              _button(
                onPressed: _busy ? null : () => _watchHeartRate(),
                icon: Icons.monitor_heart,
                label: 'Live heart rate (paired Air)',
              ),
              _button(
                onPressed: _busy ? null : _watchDeviceEvents,
                icon: Icons.sensors,
                label: 'Diagnostic device-event monitor',
              ),
              _button(
                onPressed: _busy ? null : _watchSecureEvents,
                icon: Icons.hub_outlined,
                label: 'Research: secure events (30s)',
              ),
              _button(
                onPressed: _busy ? null : () => _watchSecureEvents(alarm: true),
                icon: Icons.alarm,
                label: 'Research: alarm dismissal (90s)',
              ),
              _button(
                onPressed: _busy
                    ? null
                    : () => _watchSecureEvents(wristPresence: true),
                icon: Icons.watch_outlined,
                label: 'Research: wrist-presence trial (30s)',
              ),
              _button(
                onPressed: _busy ? null : _probeBattery,
                icon: Icons.battery_unknown,
                label: 'Research: battery access (secure session)',
              ),
              _button(
                onPressed: _busy ? null : _probeResources,
                icon: Icons.science_outlined,
                label: 'Research: read-only resource access',
              ),
              for (final device in _heartRateDevices)
                _button(
                  onPressed: _busy
                      ? null
                      : () => _readHeartRate(deviceId: device.deviceId),
                  icon: Icons.favorite,
                  label: '${device.name} (${device.rssi} dBm) · read once',
                ),
              for (final device in _heartRateDevices)
                _button(
                  onPressed: _busy ? null : () => _watchHeartRate(device),
                  icon: Icons.monitor_heart,
                  label: '${device.name} · live stream',
                ),
              _button(
                onPressed: _busy ? null : _pulse,
                icon: Icons.touch_app,
                label: 'Single pulse (alternates strength)',
              ),
              Row(
                children: [
                  Expanded(
                    child: _button(
                      onPressed: _busy
                          ? null
                          : () => _setIntensity(HapticIntensity.low),
                      icon: Icons.volume_down,
                      label: 'Set low',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _button(
                      onPressed: _busy
                          ? null
                          : () => _setIntensity(HapticIntensity.high),
                      icon: Icons.volume_up,
                      label: 'Set high',
                    ),
                  ),
                ],
              ),
              _button(
                onPressed: _busy ? null : _vibrate,
                icon: Icons.settings_backup_restore,
                label: 'Two-pulse preview + restore',
              ),
              const SizedBox(height: 12),
              const Text(
                'The single pulse works by changing and retaining the vibration strength. The restore-safe preview changes it and changes it back, so it produces two pulses. Wrist-tap detection is not implemented.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
