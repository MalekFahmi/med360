import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Tripoli'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> scheduleMedicationReminders(
    Medication med, {
    required bool isArabic,
  }) async {
    if (kIsWeb || med.status != MedicationStatus.active) return;

    await cancelMedicationReminders(med);

    for (final time in med.reminderTimes) {
      final id = _notificationId(med.id, time);
      final isAlarm = med.reminderType == ReminderType.alarm;

      await _plugin.zonedSchedule(
        id: id,
        title: isArabic ? 'تذكير بالدواء' : 'Medication Reminder',
        body: isArabic
            ? 'حان وقت تناول ${med.nameAr} (${med.dosage})'
            : 'Time to take ${med.name} (${med.dosage})',
        scheduledDate: _nextInstanceOfTime(time.hour, time.minute),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            isAlarm ? 'med360_alarms' : 'med360_reminders',
            isAlarm ? 'Medication Alarms' : 'Medication Reminders',
            channelDescription: isAlarm
                ? 'Alarm-style reminders for medication schedules'
                : 'Notifications for medication schedules',
            category: AndroidNotificationCategory.alarm,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: isAlarm,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        androidScheduleMode: isAlarm
            ? AndroidScheduleMode.alarmClock
            : AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: med.id,
      );
    }
  }

  Future<void> showCaregiverAlert({
    required String medicationName,
    required String patientName,
    required bool isArabic,
  }) async {
    if (kIsWeb) return;

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: isArabic ? 'تنبيه جرعة فائتة' : 'Missed dose alert',
      body: isArabic
          ? 'فاتت جرعة $medicationName للمريض $patientName'
          : '$patientName missed $medicationName',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'med360_caregiver_alerts',
          'Caregiver Alerts',
          channelDescription: 'Alerts sent when a patient misses a dose',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
    );
  }

  Future<void> cancelMedicationReminders(Medication med) async {
    if (kIsWeb) return;

    for (final time in med.reminderTimes) {
      await _plugin.cancel(id: _notificationId(med.id, time));
    }
  }

  int _notificationId(String medicationId, ReminderTime time) =>
      '$medicationId-${time.hour}-${time.minute}'.hashCode.abs();

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
