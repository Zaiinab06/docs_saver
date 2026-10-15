import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._internal();

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  static const String channelId = 'smart_reminders_channel_v2';
  static const String channelName = 'Smart Reminders';
  static const String channelDescription =
      'High priority smart alerts and reminders for bills, meetings, and expiry dates.';

  Future<void> init() async {
    if (_isInitialized) return;

    await _initTimezone();

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const linuxSettings =
          LinuxInitializationSettings(defaultActionName: 'Open');

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint(
            '🔔 [NotificationService] Notification clicked with payload: ${response.payload}',
          );
        },
      );

      // Create Android Notification Channel with Importance.max
      if (!kIsWeb && Platform.isAndroid) {
        final androidImplementation = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidImplementation != null) {
          const channel = AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
            showBadge: true,
          );
          await androidImplementation.createNotificationChannel(channel);
          debugPrint(
            '🔔 [NotificationService] Created Android channel "$channelId" (Importance.max, Sound & Vibration enabled)',
          );
        }
      }

      _isInitialized = true;
      debugPrint('🔔 [NotificationService] Initialized successfully.');
    } catch (e, stack) {
      debugPrint('❌ [NotificationService] Failed to initialize: $e\n$stack');
    }
  }

  Future<void> _initTimezone() async {
    try {
      tz.initializeTimeZones();
      final now = DateTime.now();
      final timeZoneName = now.timeZoneName;
      debugPrint(
        '🕒 [NotificationService] Device timeZoneName: "$timeZoneName", offset: ${now.timeZoneOffset}',
      );

      tz.Location? location;
      // 1. Try exact timeZoneName match
      if (tz.timeZoneDatabase.locations.containsKey(timeZoneName)) {
        location = tz.getLocation(timeZoneName);
      }

      // 2. If not found, match by abbreviation and offset
      if (location == null) {
        for (final loc in tz.timeZoneDatabase.locations.values) {
          if (loc.currentTimeZone.abbreviation.toLowerCase() ==
                  timeZoneName.toLowerCase() &&
              loc.currentTimeZone.offset == now.timeZoneOffset) {
            location = loc;
            break;
          }
        }
      }

      // 3. Fallback: match by UTC offset (Duration == Duration)
      if (location == null) {
        for (final loc in tz.timeZoneDatabase.locations.values) {
          if (loc.currentTimeZone.offset == now.timeZoneOffset) {
            location = loc;
            break;
          }
        }
      }

      if (location != null) {
        tz.setLocalLocation(location);
        debugPrint(
          '🕒 [NotificationService] Set local timezone to "${location.name}" (offset: ${location.currentTimeZone.offset})',
        );
      } else {
        tz.setLocalLocation(tz.UTC);
        debugPrint(
          '⚠️ [NotificationService] Timezone match not found, default to UTC',
        );
      }
    } catch (e, stack) {
      debugPrint('❌ [NotificationService] Timezone init warning: $e\n$stack');
    }
  }

  Future<bool> requestPermissions() async {
    try {
      if (kIsWeb) return false;

      if (Platform.isAndroid) {
        final androidImpl = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidImpl != null) {
          final granted =
              await androidImpl.requestNotificationsPermission() ?? false;
          debugPrint(
            '📱 [NotificationService] Android POST_NOTIFICATIONS permission granted: $granted',
          );
          try {
            await androidImpl.requestExactAlarmsPermission();
          } catch (_) {}
          return granted;
        }
      } else if (Platform.isIOS || Platform.isMacOS) {
        final iosImpl = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        if (iosImpl != null) {
          final granted = await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          debugPrint(
            '📱 [NotificationService] iOS notification permission granted: $granted',
          );
          return granted ?? false;
        }
      }
    } catch (e) {
      debugPrint('❌ [NotificationService] Request permission error: $e');
    }
    return true;
  }

  static int getNotificationId(String memoryId) {
    return memoryId.hashCode.abs() % 2147483647;
  }

  Future<bool> scheduleReminder({
    required String memoryId,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? reminderType,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    final now = DateTime.now();
    if (scheduledDate.isBefore(now)) {
      debugPrint(
        '❌ [NotificationService] Cannot schedule reminder in the past: scheduledDate=$scheduledDate, now=$now',
      );
      return false;
    }

    try {
      await requestPermissions();

      final notificationId = getNotificationId(memoryId);

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        ticker: 'Smart Reminder',
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(
          body.isNotEmpty ? body : 'Reminder for $title',
          contentTitle: title,
        ),
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      // Build TZDateTime from scheduledDate in tz.local
      // Using tz.TZDateTime.from ensures that scheduledDate's local epoch timestamp
      // is accurately converted to the target timezone instant.
      final tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);
      final tzNow = tz.TZDateTime.now(tz.local);
      debugPrint(
        '🔔 [NotificationService] Scheduling reminder:\n'
        '   - memoryId: $memoryId (notifId: #$notificationId)\n'
        '   - title: "$title"\n'
        '   - body: "$body"\n'
        '   - scheduledDate: $scheduledDate\n'
        '   - tzScheduled: $tzScheduled (tz.local: ${tz.local.name})\n'
        '   - tzNow: $tzNow\n'
        '   - in seconds: ${tzScheduled.difference(tzNow).inSeconds}s',
      );

      if (tzScheduled.isBefore(tzNow)) {
        debugPrint(
          '❌ [NotificationService] Cannot schedule reminder in the past: tzScheduled=$tzScheduled, tzNow=$tzNow',
        );
        return false;
      }

      try {
        await _notificationsPlugin.zonedSchedule(
          id: notificationId,
          title: title,
          body: body.isNotEmpty ? body : 'Smart Reminder alert for $title',
          scheduledDate: tzScheduled,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: memoryId,
        );
        debugPrint(
          '✅ [NotificationService] EXACT reminder #$notificationId successfully scheduled for $tzScheduled',
        );
        final pending =
            await _notificationsPlugin.pendingNotificationRequests();
        debugPrint(
          '📋 [NotificationService] Total pending notifications in queue: ${pending.length}',
        );
        return true;
      } catch (exactError) {
        debugPrint(
          '⚠️ [NotificationService] Exact alarm restricted ($exactError). Falling back to inexactAllowWhileIdle...',
        );
        await _notificationsPlugin.zonedSchedule(
          id: notificationId,
          title: title,
          body: body.isNotEmpty ? body : 'Smart Reminder alert for $title',
          scheduledDate: tzScheduled,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: memoryId,
        );
        debugPrint(
          '✅ [NotificationService] INEXACT reminder #$notificationId successfully scheduled for $tzScheduled',
        );
        final pending =
            await _notificationsPlugin.pendingNotificationRequests();
        debugPrint(
          '📋 [NotificationService] Total pending notifications in queue: ${pending.length}',
        );
        return true;
      }
    } catch (e, stack) {
      debugPrint(
        '❌ [NotificationService] Error scheduling reminder for $memoryId: $e\n$stack',
      );
      return false;
    }
  }

  Future<void> cancelReminder(String memoryId) async {
    try {
      final notificationId = getNotificationId(memoryId);
      await _notificationsPlugin.cancel(id: notificationId);
      debugPrint(
        '🗑️ [NotificationService] Cancelled reminder #$notificationId for memory $memoryId',
      );
    } catch (e) {
      debugPrint('❌ [NotificationService] Error cancelling reminder: $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint('🗑️ [NotificationService] Cancelled all reminders');
    } catch (e) {
      debugPrint('❌ [NotificationService] Error cancelling all: $e');
    }
  }
}
