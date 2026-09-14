import 'dart:async';
import 'dart:io';

class NetworkChecker {
  static bool? _testOverride;
  static final StreamController<bool> _controller = StreamController<bool>.broadcast();

  /// Stream of network connectivity state transitions (true = online, false = offline).
  static Stream<bool> get onConnectivityChanged => _controller.stream;

  static bool? get testOverride => _testOverride;
  static set testOverride(bool? value) {
    _testOverride = value;
    if (value != null) {
      _controller.add(value);
    }
  }

  static void setTestOverride(bool? value) {
    testOverride = value;
  }

  static Timer? _pollTimer;
  static bool _lastKnownState = true;

  /// Starts polling for network connectivity changes in production.
  static void startMonitoring({Duration interval = const Duration(seconds: 2)}) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (_pollTimer != null) return;

    _pollTimer = Timer.periodic(interval, (_) async {
      final connected = await isConnected();
      if (connected != _lastKnownState) {
        _lastKnownState = connected;
        _controller.add(connected);
      }
    });
  }

  /// Stops polling timer when no longer needed.
  static void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Returns true if an active internet connection is available.
  static Future<bool> isConnected() async {
    if (_testOverride != null) return _testOverride!;
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      final connected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _lastKnownState = connected;
      return connected;
    } catch (_) {
      _lastKnownState = false;
      return false;
    }
  }
}
