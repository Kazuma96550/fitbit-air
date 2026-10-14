import 'dart:async';

import 'package:fitbit_air/fitbit_air.dart';
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
      final result = await FitbitAir.vibrate();
      await resultChannel.invokeMethod('complete', {
        'success': result.restored && result.verified,
        'restored': result.restored,
        'verified': result.verified,
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
  final List<String> _eventLog = [];
  int _notificationCount = 0;

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

  @override
  void dispose() {
    _heartRateSubscription?.cancel();
    _deviceEventSubscription?.cancel();
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
            children: [
              const Icon(Icons.watch, size: 64),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 28),
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
