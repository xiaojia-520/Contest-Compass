import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../api_client.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get supported =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);

  Future<void> initialize() async {
    if (!supported || _initialized) return;
    _initialized = true;
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: darwin,
      macOS: darwin,
      windows: WindowsInitializationSettings(
        appName: '赛智荐',
        appUserModelId: 'xiaojia.saizhijian.app',
        guid: '902D9F45-7A8C-4A86-A0E4-32E9916A72F6',
      ),
    );
    await _plugin.initialize(settings: settings);
  }

  Future<bool> requestPermission() async {
    if (!supported) return false;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notifications =
          await android?.requestNotificationsPermission() ?? true;
      await android?.requestExactAlarmsPermission();
      return notifications;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  Future<void> clear() async {
    if (!supported) return;
    await initialize();
    await _plugin.cancelAll();
  }

  Future<void> sync(ApiClient api, {bool requestPermission = false}) async {
    if (!supported) return;
    await initialize();
    if (requestPermission && !await this.requestPermission()) return;

    final data = await api.get('/reminders') as List<dynamic>;
    await _plugin.cancelAll();
    final pending = <_ReminderSchedule>[];
    for (final raw in data) {
      final item = Map<String, dynamic>.from(raw as Map);
      final deadlineSeconds = item['register_end_at'] as int?;
      if (deadlineSeconds == null) continue;
      final deadline = DateTime.fromMillisecondsSinceEpoch(
        deadlineSeconds * 1000,
        isUtc: true,
      ).toLocal();
      for (final days in const [7, 3, 1]) {
        final date = deadline.subtract(Duration(days: days));
        final scheduled = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          9,
        );
        if (scheduled.isAfter(tz.TZDateTime.now(tz.local))) {
          pending.add(_ReminderSchedule(item, days, scheduled));
        }
      }
    }
    pending.sort((a, b) => a.when.compareTo(b.when));
    for (final schedule in pending.take(60)) {
      final projectId = schedule.item['project_id'] as int? ?? 0;
      final contestId = schedule.item['contest_id'] as int? ?? 0;
      final id = Object.hash(projectId, contestId, schedule.days) & 0x7fffffff;
      await _plugin.zonedSchedule(
        id: id,
        title: '比赛报名截止提醒',
        body:
            '${schedule.item['contest_name'] ?? '比赛'}将在 ${schedule.days} 天后截止报名',
        scheduledDate: schedule.when,
        payload: 'project:$projectId;contest:$contestId',
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'competition_deadlines',
            '比赛截止提醒',
            channelDescription: '在比赛报名截止前 7 天、3 天和 1 天提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(threadIdentifier: 'deadlines'),
          macOS: DarwinNotificationDetails(threadIdentifier: 'deadlines'),
          windows: WindowsNotificationDetails(),
        ),
      );
    }
  }
}

class _ReminderSchedule {
  const _ReminderSchedule(this.item, this.days, this.when);
  final Map<String, dynamic> item;
  final int days;
  final tz.TZDateTime when;
}
