import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/models.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _n = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _n.initialize(settings: initSettings);
  }

  Future<void> scheduleMedicationReminders(Medication med) async {
    if (med.status != MedicationStatus.active) return;

    for (int i = 0; i < med.reminderTimes.length; i++) {
      final time = med.reminderTimes[i];
      final id = med.id.hashCode + i;

      await _n.zonedSchedule(
        id: id,
        title: 'Medication Reminder',
        body: 'Time to take your ${med.name} (${med.dosage})',
        scheduledDate: _nextInstanceOfTime(time.hour, time.minute),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'med_reminders',
            'Medication Reminders',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> cancelMedicationReminders(Medication med) async {
    for (int i = 0; i < med.reminderTimes.length; i++) {
      final id = med.id.hashCode + i;
      await _n.cancel(id: id);
    }
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
