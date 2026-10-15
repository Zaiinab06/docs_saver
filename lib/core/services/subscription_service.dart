import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._internal();

  SubscriptionService._internal();

  static const String entitlementPro = 'pro';
  static const String entitlementPremium = 'premium';
  static const String _prefMockProKey = 'mock_pro_entitlement';

  final ValueNotifier<bool> isPremiumNotifier = ValueNotifier<bool>(false);
  bool _isConfigured = false;

  bool get isPremium => isPremiumNotifier.value;

  Future<void> init() async {
    // 1. By default, start as non-premium so the Pro banner and upgrade paywall
    // are visible to all free users by default.
    isPremiumNotifier.value = false;

    // Clear legacy mock persistence to prevent aggressive local caching from
    // hiding the banner permanently across app sessions.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefMockProKey)) {
        await prefs.remove(_prefMockProKey);
      }
    } catch (_) {}

    // 2. Configure RevenueCat if supported on platform
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) {
      return;
    }

    try {
      // Look for RevenueCat key in environment
      const apiKey = String.fromEnvironment('REVENUECAT_API_KEY');
      if (apiKey.isNotEmpty) {
        await Purchases.configure(PurchasesConfiguration(apiKey));
        _isConfigured = true;

        Purchases.addCustomerInfoUpdateListener((customerInfo) {
          _updateEntitlements(customerInfo);
        });

        final customerInfo = await Purchases.getCustomerInfo();
        _updateEntitlements(customerInfo);
      }
    } catch (e) {
      debugPrint('[SubscriptionService] RevenueCat init warning: $e');
    }
  }

  void _updateEntitlements(CustomerInfo customerInfo) {
    final hasPro = customerInfo.entitlements.active.containsKey(entitlementPro) ||
        customerInfo.entitlements.active.containsKey(entitlementPremium);
    isPremiumNotifier.value = hasPro;
    debugPrint('[SubscriptionService] Entitlement active: $hasPro');
  }

  Future<bool> checkPremiumStatus() async {
    if (_isConfigured) {
      try {
        final customerInfo = await Purchases.getCustomerInfo();
        _updateEntitlements(customerInfo);
        return isPremiumNotifier.value;
      } catch (e) {
        debugPrint('[SubscriptionService] Error checking customer info: $e');
      }
    }
    return isPremiumNotifier.value;
  }

  /// Toggle mock pro entitlement for testing or paywall simulation
  Future<void> setMockPremium(bool value) async {
    isPremiumNotifier.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefMockProKey, value);
    } catch (_) {}
  }

  Future<bool> restorePurchases() async {
    if (!_isConfigured) {
      // In mock / demo mode, pretend restore found existing purchase if toggled
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getBool(_prefMockProKey) ?? false;
      isPremiumNotifier.value = local;
      return local;
    }
    try {
      final customerInfo = await Purchases.restorePurchases();
      _updateEntitlements(customerInfo);
      return isPremiumNotifier.value;
    } catch (e) {
      debugPrint('[SubscriptionService] Error restoring purchases: $e');
      return false;
    }
  }
}
