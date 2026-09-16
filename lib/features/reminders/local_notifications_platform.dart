import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_scheduler.dart';

const notificationIconResourceName = 'ic_notification';

class LocalNotificationsPlatform implements ReminderPlatform {
  LocalNotificationsPlatform([
    FlutterLocalNotificationsPlugin? plugin,
    Future<String> Function()? timezoneLookup,
  ]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _timezoneLookup =
           timezoneLookup ??
           (() async => (await FlutterTimezone.getLocalTimezone()).identifier);

  final FlutterLocalNotificationsPlugin _plugin;
  final Future<String> Function() _timezoneLookup;

  @override
  Future<String?> initialize(ReminderTapCallback onTap) async {
    tz_data.initializeTimeZones();
    await refreshTimezone();
    const android = AndroidInitializationSettings(notificationIconResourceName);
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    if (initialized != true) {
      throw StateError('Local notification initialization failed.');
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true
        ? launch?.notificationResponse?.payload
        : null;
  }

  @override
  Future<bool> checkPermission() async {
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }
    if (Platform.isIOS) {
      return (await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions())
              ?.isEnabled ??
          false;
    }
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<void> refreshTimezone() async {
    final identifier = await _timezoneLookup();
    tz.setLocalLocation(tz.getLocation(identifier));
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> schedule(ScheduledReminder reminder) {
    final local = reminder.localDateTime;
    return _plugin.zonedSchedule(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: tz.TZDateTime(
        tz.local,
        local.year,
        local.month,
        local.day,
        local.hour,
      ),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'coverage_expiry_reminders',
          'Coverage expiry reminders',
          channelDescription: 'Reminders before recorded coverage ends',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.payload,
    );
  }
}
