import 'dart:async';
import 'dart:convert';

import 'package:fitbit_air/fitbit_air.dart';
import 'package:fitbit_air/fitbit_air_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DemoAction {
  const DemoAction(this.run, {this.streaming = false, this.parameters});
  final FutureOr<void> Function() run;
  final bool streaming;
  final Map<String, Object?> Function()? parameters;
}

/// Shared by UI and tests. Conversation labels stay local and out of reports.
class DemoController extends ChangeNotifier {
  static const channel = MethodChannel('fitbit_air_example/calendar');
  final actions = <String, DemoAction>{};
  Future<void> Function()? cancelCurrent;
  Map<String, Object?> transportDiagnostics = {};
  bool initialized = false;
  bool relayRunning = false;
  bool relayReady = false;
  bool relayStopping = false;
  bool changingRelay = false;
  bool access = false;
  bool listenerConnected = false;
  bool? bluetoothEnabled;
  bool bluetoothPermission = false;
  bool? paired;
  String relayOutcome = 'Relay is off.';
  String? setupError;
  String appSearch = '';
  Set<String> selectedApps = {'com.google.android.calendar'};
  List<Map<String, Object?>> apps = [];
  List<Map<String, Object?>> history = [];
  bool restrictedConversations = false;
  int captureRemainingMillis = 0;
  int unsupportedConversations = 0;
  Map<String, int> captureDiagnostics = {};
  List<Map<String, Object?>> allowedConversations = [];
  List<Map<String, Object?>> conversationCandidates = [];
  int secureDurationSeconds = 30;
  Timer? _poll;
  bool _disposed = false;
  Future<void>? _refreshInFlight;
  bool _loadingApps = false;
  int _sequence = 0;
  final List<Map<String, Object?>> _trials = [];
  Map<String, Object?>? _activeTrial;
  final List<Map<String, Object?>> _observations = [];

  bool get busy => _activeTrial != null;
  String? get operationId => _activeTrial?['operation'] as String?;
  bool get controlsBlocked => busy || relayRunning || changingRelay;
  List<Map<String, Object?>> get trials => List.unmodifiable(_trials);
  List<String> get actionIds => actions.keys.toList()..sort();

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    await refresh();
    await loadApps();
    try {
      final settings = await channel.invokeMapMethod<String, Object?>(
        'labSettings',
      );
      final duration = settings?['secureDurationSeconds'];
      if (duration is int && [30, 60, 90].contains(duration)) {
        secureDurationSeconds = duration;
      }
    } on PlatformException catch (error) {
      setupError = recoveryHint(error.code);
    } on MissingPluginException {
      // The status explains that this app needs Android.
    }
    initialized = true;
    _changed();
  }

  /// Only poll while a screen is visible. The native service owns background work.
  void setVisible(bool visible) {
    _poll?.cancel();
    _poll = null;
    if (visible) {
      unawaited(refresh());
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> refresh({bool force = false}) async {
    if (_disposed) return;
    final previous = _refreshInFlight;
    if (previous != null) {
      await previous;
      if (!force || _disposed) return;
    }
    final task = _readStatus();
    _refreshInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_refreshInFlight, task)) _refreshInFlight = null;
    }
  }

  Future<void> _readStatus() async {
    try {
      transportDiagnostics =
          await FitbitAirDiagnostics.readTransportDiagnostics();
    } on PlatformException {
      transportDiagnostics = {'available': false};
    } on MissingPluginException {
      transportDiagnostics = {'available': false};
    }
    try {
      final state = await channel.invokeMapMethod<String, Object?>('status');
      if (state == null || _disposed) return;
      relayRunning = state['running'] == true;
      relayReady = state['ready'] == true;
      relayStopping = state['stopping'] == true;
      access = state['access'] == true;
      listenerConnected = state['connected'] == true;
      bluetoothEnabled = state['bluetoothEnabled'] as bool?;
      bluetoothPermission = state['bluetoothPermission'] == true;
      relayOutcome = state['outcome'] as String? ?? 'Relay is off.';
      final selected = state['selectedApps'] as List?;
      if (selected != null) selectedApps = selected.cast<String>().toSet();
      final conversations = Map<String, Object?>.from(
        state['conversations'] as Map? ?? const {},
      );
      restrictedConversations = conversations['restricted'] == true;
      captureRemainingMillis =
          conversations['captureRemainingMillis'] as int? ?? 0;
      unsupportedConversations = conversations['unsupported'] as int? ?? 0;
      const diagnosticKeys = {
        'seen',
        'existing',
        'ongoing',
        'summary',
        'missingId',
        'unusable',
        'nameOnly',
        'identified',
        'errors',
      };
      captureDiagnostics =
          Map<String, Object?>.from(
              conversations['diagnostics'] as Map? ?? const {},
            ).map((key, value) => MapEntry(key, value is int ? value : 0))
            ..removeWhere((key, value) => !diagnosticKeys.contains(key));
      allowedConversations = (conversations['allowed'] as List? ?? [])
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList();
      conversationCandidates = (conversations['candidates'] as List? ?? [])
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList();
      history = (state['history'] as List? ?? [])
          .map((entry) => Map<String, Object?>.from(entry as Map))
          .toList();
    } on PlatformException catch (error) {
      setupError = recoveryHint(error.code);
    } on MissingPluginException {
      setupError = 'This demo requires an Android phone.';
    } finally {
      _changed();
    }
  }

  Future<void> loadApps() async {
    if (_loadingApps || _disposed) return;
    _loadingApps = true;
    try {
      final result = await channel.invokeListMethod<Object?>('apps');
      if (!_disposed) {
        apps = (result ?? [])
            .map((app) => Map<String, Object?>.from(app! as Map))
            .toList();
      }
    } on PlatformException catch (error) {
      setupError = recoveryHint(error.code);
    } on MissingPluginException {
      // Android support is explained by refresh().
    } finally {
      _loadingApps = false;
      _changed();
    }
  }

  List<Map<String, Object?>> get filteredApps {
    final query = appSearch.trim().toLowerCase();
    final result = apps
        .where(
          (app) => '${app['label']} ${app['packageName']}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    result.sort((a, b) {
      final selected =
          (selectedApps.contains(b['packageName']) ? 1 : 0) -
          (selectedApps.contains(a['packageName']) ? 1 : 0);
      return selected != 0
          ? selected
          : (a['label'] as String).toLowerCase().compareTo(
              (b['label'] as String).toLowerCase(),
            );
    });
    return result;
  }

  void searchApps(String query) {
    appSearch = query;
    _changed();
  }

  Future<void> selectApp(String packageName, bool selected) async {
    if (relayRunning || changingRelay) {
      throw StateError('Stop the relay before changing apps.');
    }
    final packages = {...selectedApps};
    selected ? packages.add(packageName) : packages.remove(packageName);
    await _relayCall('selectApps', {'packages': packages.toList()});
  }

  Future<void> configureConversations(String method, [Object? arguments]) {
    if (!const {
      'captureConversations',
      'restrictConversations',
      'selectConversation',
      'clearConversations',
    }.contains(method)) {
      throw ArgumentError.value(method);
    }
    if (relayRunning || changingRelay) {
      throw StateError('Stop the relay before changing conversation rules.');
    }
    return _relayCall(method, arguments);
  }

  Future<void> _relayCall(String method, [Object? arguments]) async {
    changingRelay = true;
    setupError = null;
    _changed();
    try {
      await channel.invokeMethod<void>(method, arguments);
      await refresh(force: true);
    } on PlatformException catch (error) {
      setupError = recoveryHint(error.code);
      rethrow;
    } finally {
      changingRelay = false;
      _changed();
    }
  }

  Future<void> checkPaired() async {
    paired = await FitbitAir.isAirPaired();
    await refresh();
    _changed();
  }

  Future<void> startRelay() async {
    if (busy || changingRelay) {
      throw StateError('Wait for the current operation.');
    }
    if (selectedApps.isEmpty) throw StateError('Select at least one app.');
    changingRelay = true;
    setupError = null;
    _changed();
    try {
      await checkPaired();
      if (paired != true) {
        setupError = 'Pair the Air in Google Health, then check again.';
        return;
      }
      await channel.invokeMethod<void>('start');
      await refresh(force: true);
    } on PlatformException catch (error) {
      setupError = recoveryHint(error.code);
    } on FitbitAirException catch (error) {
      setupError = recoveryHint(error.code);
    } finally {
      changingRelay = false;
      _changed();
    }
  }

  Future<void> stopRelay() => _relayCall('stop');

  Future<void> stopRelayAndWait() async {
    await stopRelay();
    final deadline = DateTime.now().add(const Duration(seconds: 55));
    while (relayRunning) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'The relay is still finishing a command. Wait for it to stop.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await refresh();
    }
  }

  Future<void> testRelay() {
    if (!relayRunning || !relayReady) {
      throw StateError('Wait until the relay is listening.');
    }
    return _relayCall('testPulse');
  }

  Future<void> openAccessSettings() => channel.invokeMethod<void>('settings');
  Future<void> openBluetoothSettings() =>
      channel.invokeMethod<void>('bluetoothSettings');
  Future<void> clearHistory() => _relayCall('clearHistory');

  Future<void> saveDuration(int seconds) async {
    if (busy) throw StateError('Finish the active trial first.');
    if (![30, 60, 90].contains(seconds)) throw ArgumentError.value(seconds);
    await channel.invokeMethod<void>('setLabSettings', {
      'secureDurationSeconds': seconds,
    });
    secureDurationSeconds = seconds;
    _changed();
  }

  /// Same named operations for buttons and device integration tests.
  Future<void> runAction(String id) async {
    if (busy || changingRelay) {
      throw StateError('An operation is already running.');
    }
    if (relayRunning) {
      throw StateError('Stop the relay before a device operation.');
    }
    final action = actions[id];
    if (action == null) {
      throw ArgumentError.value(id, 'id', 'Unknown operation');
    }
    final trial = <String, Object?>{
      'id': 'trial-${++_sequence}',
      'operation': id,
      'parameters': action.parameters?.call() ?? <String, Object?>{},
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'outcome': 'running',
      'observations': <Map<String, Object?>>[],
    };
    _activeTrial = trial;
    _trials.insert(0, trial);
    if (_trials.length > 20) _trials.removeLast();
    _changed();
    try {
      await action.run();
      if (!action.streaming && identical(_activeTrial, trial)) {
        finishOperation();
      }
    } catch (error) {
      failOperation(error);
      finishOperation();
      rethrow;
    }
  }

  void observe(String kind, [Map<String, Object?> metadata = const {}]) {
    const allowed = {
      'phase',
      'eventIds',
      'eventNames',
      'observationMillis',
      'receivedPosts',
      'payloadLength',
      'marker',
      'model',
      'firmware',
    };
    final event = <String, Object?>{
      'kind': kind,
      'receivedAt': DateTime.now().toUtc().toIso8601String(),
      ...Map.fromEntries(
        metadata.entries.where((entry) => allowed.contains(entry.key)),
      ),
    };
    final trial = _activeTrial;
    if (trial != null) {
      final observations = trial['observations']! as List<Map<String, Object?>>;
      observations.add(event);
      if (observations.length > 100) observations.removeAt(0);
    } else {
      _observations.add(event);
      if (_observations.length > 100) _observations.removeAt(0);
    }
    _changed();
  }

  void mark(String marker) {
    const markers = {
      'felt_vibration',
      'off_wrist',
      'on_wrist',
      'tap_attempt',
      'led_seen',
      'alarm_started',
      'alarm_dismiss_attempt',
      'alarm_stopped',
    };
    if (!markers.contains(marker)) throw ArgumentError.value(marker);
    observe('manual_marker', {'marker': marker});
  }

  void setOutcome(String outcome) {
    if (_activeTrial == null) return;
    _activeTrial!['outcome'] = outcome;
    _changed();
  }

  void failOperation(Object error) {
    if (_activeTrial == null) return;
    final code = error is FitbitAirException
        ? error.code
        : error is PlatformException
        ? error.code
        : 'DEMO_ERROR';
    if (code == 'CANCELLED') {
      _activeTrial!['outcome'] = 'cancelled';
    } else if (_activeTrial!['outcome'] != 'interrupted' &&
        _activeTrial!['outcome'] != 'cancelled') {
      _activeTrial!['outcome'] = 'failed';
    }
    _activeTrial!['errorCode'] = code;
    _changed();
  }

  void finishOperation([String? outcome]) {
    final trial = _activeTrial;
    if (trial == null) return;
    if (outcome != null) trial['outcome'] = outcome;
    if (trial['outcome'] == 'running') trial['outcome'] = 'completed';
    trial['durationMillis'] = DateTime.now()
        .toUtc()
        .difference(DateTime.parse(trial['startedAt']! as String))
        .inMilliseconds;
    trial['endedAt'] = DateTime.now().toUtc().toIso8601String();
    _activeTrial = null;
    _changed();
  }

  Map<String, Object?> report() => {
    'schemaVersion': 1,
    'demoVersion': '0.1.3-dev.4',
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'relay': {
      'running': relayRunning,
      'history': history,
      'restrictedConversations': restrictedConversations,
      'allowedConversationCount': allowedConversations.length,
      'captureDiagnostics': captureDiagnostics,
    },
    'transport': transportDiagnostics,
    'trials': _trials,
    'manualObservations': _observations,
  };
  String exportJson() => const JsonEncoder.withIndent('  ').convert(report());

  static String recoveryHint(String code) => switch (code) {
    'TIMEOUT' =>
      'The command timed out; delivery is uncertain. Check the Air and Google Health before testing again. No automatic retry.',
    'BUSY' =>
      'Another operation owns the device. Stop that operation and try again.',
    'NOTIFICATION_ACCESS' =>
      'Enable notification access and wait for the listener to connect.',
    'BLUETOOTH_DISABLED' ||
    'BLUETOOTH_OFF' => 'Turn on Bluetooth, then try again.',
    'AIR_NOT_FOUND' ||
    'PAIRING_REQUIRED' => 'Pair the Air in Google Health, then check again.',
    'CANNOT_CANCEL_WRITE' =>
      'This haptic must finish verification and restoration. Wait for completion.',
    'GATT_CONNECT' || 'GATT_DISCONNECTED' =>
      'Keep the Air near the phone and check Google Health. Delivery may be uncertain; no automatic retry.',
    'HEART_RATE_UNAVAILABLE' || 'HEART_RATE_TIMEOUT' =>
      'Enable Share heart rate in Google Health before reading or streaming.',
    'SERVICE_STOPPED' =>
      'The relay stopped before reporting a result. Delivery is uncertain; no automatic retry.',
    'PERMISSION_DENIED' || 'BLUETOOTH_PERMISSION' =>
      'Grant Nearby devices permission using Check paired Air.',
    _ =>
      'Operation failed ($code). Check permissions, Bluetooth and the paired Air. No automatic retry.',
  };

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}
