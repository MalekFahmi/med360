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
    await _createAndroidChannels();
    _initialized = true;
  }

  Future<void> _createAndroidChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'med360_reminders',
      'Medication Reminders',
      description: 'Notifications for medication schedules',
      importance: Importance.max,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'med360_alarms',
      'Medication Alarms',
      description: 'Alarm-style reminders for medication schedules',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'med360_caregiver_alerts',
      'Caregiver Alerts',
      description: 'Alerts sent when a patient misses a dose',
      importance: Importance.max,
    ));
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
      final id = _notificationId(med.id, time, 'initial');
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

  Future<void> scheduleDoseEscalation(
    DoseConfirmation dose, {
    required bool isArabic,
  }) async {
    if (kIsWeb || !dose.isPending) return;

    final secondReminderAt =
        _scheduledDateTime(dose).add(const Duration(minutes: 5));
    if (!secondReminderAt.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id: _doseNotificationId(dose.id, 'second'),
      title: isArabic ? 'تذكير ثان' : 'Second Medication Reminder',
      body: isArabic
          ? 'لم يتم تأكيد جرعة ${dose.medicationName} بعد.'
          : '${dose.medicationName} has not been marked as taken yet.',
      scheduledDate: tz.TZDateTime.from(secondReminderAt, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'med360_reminders',
          'Medication Reminders',
          channelDescription: 'Notifications for medication schedules',
          category: AndroidNotificationCategory.reminder,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: '${dose.id}:second',
    );
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
      await _plugin.cancel(id: _notificationId(med.id, time, 'initial'));
    }
  }

  Future<void> cancelDoseEscalation(DoseConfirmation dose) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _doseNotificationId(dose.id, 'second'));
  }

  int _notificationId(String medicationId, ReminderTime time, String stage) =>
      '$medicationId-${time.hour}-${time.minute}-$stage'.hashCode.abs();

  int _doseNotificationId(String doseId, String stage) =>
      '$doseId-$stage'.hashCode.abs();

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

  DateTime _scheduledDateTime(DoseConfirmation dose) {
    final parts = dose.scheduledTime.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(
      dose.scheduledDate.year,
      dose.scheduledDate.month,
      dose.scheduledDate.day,
      hour,
      minute,
    );
  }
}
