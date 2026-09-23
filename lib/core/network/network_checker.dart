import 'dart:async';
import 'dart:io';
import '../constants/supabase_constants.dart';

class NetworkChecker {
  static bool? _testOverride;
  static final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

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

  /// Lightweight reachability caching (TTL 4 seconds) to prevent redundant network requests.
  static const Duration cacheTtl = Duration(seconds: 4);
  static DateTime? _lastCheckTime;
  static bool _lastKnownState = true;
  static Timer? _pollTimer;

  /// Resets reachability cache (useful for testing or forced immediate re-evaluations).
  static void resetCache() {
    _lastCheckTime = null;
  }

  /// Starts polling for network connectivity changes in production.
  static void startMonitoring({
    Duration interval = const Duration(seconds: 5),
  }) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (_pollTimer != null) return;

    _pollTimer = Timer.periodic(interval, (_) async {
      await isConnected(forceRefresh: true);
    });
  }

  /// Stops polling timer when no longer needed.
  static void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Returns true if an active internet connection is available and reachable.
  ///
  /// Multi-tier reachability strategy:
  /// 1. If checked within [cacheTtl] and [forceRefresh] is false, returns cached result instantly.
  /// 2. Fast Tier 1: IP socket probe to public DNS (1.1.1.1:53 / 8.8.8.8:53). Zero DNS overhead, completes in <20ms.
  /// 3. Fallback Tier 2: DNS lookup on primary Supabase endpoint and google.com.
  static Future<bool> isConnected({bool forceRefresh = false}) async {
    if (_testOverride != null) return _testOverride!;
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }

    final now = DateTime.now();
    if (!forceRefresh &&
        _lastCheckTime != null &&
        now.difference(_lastCheckTime!) < cacheTtl) {
      return _lastKnownState;
    }

    bool isReachable = false;

    // Fast Tier 1: IP-level socket probe (bypasses Android emulator DNS latency/failure)
    try {
      final socket = await Socket.connect(
        '1.1.1.1',
        53,
        timeout: const Duration(milliseconds: 1500),
      );
      socket.destroy();
      isReachable = true;
    } catch (_) {
      try {
        final socket = await Socket.connect(
          '8.8.8.8',
          53,
          timeout: const Duration(milliseconds: 1500),
        );
        socket.destroy();
        isReachable = true;
      } catch (_) {
        isReachable = false;
      }
    }

    // Fallback Tier 2: Hostname DNS lookup on app's backend host and fallback domain
    if (!isReachable) {
      try {
        final supabaseHost =
            Uri.tryParse(SupabaseConstants.supabaseUrl)?.host ?? 'supabase.co';
        final result = await InternetAddress.lookup(
          supabaseHost,
        ).timeout(const Duration(milliseconds: 2500));
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          isReachable = true;
        }
      } catch (_) {
        try {
          final result = await InternetAddress.lookup(
            'google.com',
          ).timeout(const Duration(milliseconds: 2500));
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            isReachable = true;
          }
        } catch (_) {
          isReachable = false;
        }
      }
    }

    _lastCheckTime = DateTime.now();
    if (_lastKnownState != isReachable) {
      _lastKnownState = isReachable;
      _controller.add(isReachable);
    }

    return isReachable;
  }
}
