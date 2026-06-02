import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  static const actionTakeMedication = 'take_medication';
  static const actionSnoozeMedication = 'snooze_medication';
  static const actionDismissMedication = 'dismiss_medication';

  static const _reminderChannelId = 'med360_reminders';
  static const _alarmChannelId = 'med360_alarms_v2';
  static const _caregiverChannelId = 'med360_caregiver_alerts';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  ValueChanged<NotificationResponse>? _responseHandler;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Africa/Tripoli'));
    } catch (_) {
      // Keep the package default if the bundled timezone database is unavailable.
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _backgroundResponseHandler,
    );
    await _createAndroidChannels();
    _initialized = true;
  }

  void setResponseHandler(ValueChanged<NotificationResponse>? handler) {
    _responseHandler = handler;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    _responseHandler?.call(response);
  }

  Future<void> _createAndroidChannels() async {
    if (kIsWeb) return;

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _reminderChannelId,
        'Medication reminders',
        description: 'Medication reminder notifications',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _alarmChannelId,
        'Medication alarms',
        description: 'Full-screen medication alarms',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _caregiverChannelId,
        'Caregiver alerts',
        description: 'Alerts for caregivers when patient doses are missed',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    final macPlugin = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macPlugin?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> scheduleMedicationReminders(
    Medication med, {
    required bool isArabic,
  }) async {
    if (kIsWeb || med.status != MedicationStatus.active) return;

    await cancelMedicationReminders(med);

    final isAlarm = med.reminderType == ReminderType.alarm;
    for (final time in med.reminderTimes) {
      final scheduled = _nextInstanceOfTime(time.hour, time.minute);
      await _plugin.zonedSchedule(
        id: _notificationId(med.id, time, 'initial'),
        title: isAlarm ? 'Medication Alarm' : 'Medication Reminder',
        body: _medicationBody(med, isArabic: isArabic),
        scheduledDate: scheduled,
        notificationDetails: _medicationDetails(isAlarm: isAlarm),
        androidScheduleMode: isAlarm
            ? AndroidScheduleMode.alarmClock
            : AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: _medicationPayload(med.id, time),
      );
    }
  }

  Future<void> scheduleDoseEscalation(
    DoseConfirmation dose, {
    required bool isArabic,
  }) async {
    if (kIsWeb || !dose.isPending) return;

    final scheduled = tz.TZDateTime.from(
      _scheduledDateTime(dose).add(const Duration(minutes: 5)),
      tz.local,
    );
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id: _doseNotificationId(dose.id, 'second'),
      title: isArabic ? 'تذكير ثان' : 'Second Reminder',
      body: isArabic
          ? 'ما زال وقت تناول ${dose.medicationName} متاحا.'
          : 'Still time to take ${dose.medicationName}.',
      scheduledDate: scheduled,
      notificationDetails: _reminderDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: '${dose.id}:second',
    );
  }

  Future<void> snoozeAlarm({
    required Medication med,
    required ReminderTime time,
    required bool isArabic,
  }) async {
    if (kIsWeb) return;

    final scheduled = tz.TZDateTime.now(
      tz.local,
    ).add(const Duration(minutes: 5));
    await _plugin.zonedSchedule(
      id: _notificationId(med.id, time, 'snooze'),
      title: 'Medication Alarm',
      body: _medicationBody(med, isArabic: isArabic),
      scheduledDate: scheduled,
      notificationDetails: _medicationDetails(isAlarm: true),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: _medicationPayload(med.id, time),
    );
  }

  Future<void> showCaregiverAlert({
    required String medicationName,
    required String patientName,
    required bool isArabic,
  }) async {
    if (kIsWeb) return;

    await _plugin.show(
      id: '$patientName-$medicationName-caregiver'.hashCode.abs(),
      title: isArabic ? 'تنبيه جرعة فائتة' : 'Missed dose alert',
      body: isArabic
          ? '$patientName فاتته جرعة $medicationName.'
          : '$patientName missed $medicationName.',
      notificationDetails: _caregiverDetails(),
    );
  }

  Future<void> showRefillAlert({
    required Medication medication,
    required bool isArabic,
  }) async {
    if (kIsWeb) return;

    await _plugin.show(
      id: _notificationId(
        medication.id,
        const ReminderTime(hour: 0, minute: 0),
        'refill',
      ),
      title: isArabic ? 'تذكير إعادة التعبئة' : 'Refill reminder',
      body: isArabic
          ? '${medication.displayNameAr} متبق له ${medication.estimatedDaysRemaining.ceil()} يوم.'
          : '${medication.displayName} has ${medication.estimatedDaysRemaining.ceil()} days remaining.',
      notificationDetails: _reminderDetails(),
    );
  }

  Future<void> showMedicationChangeAlert({
    required String medicationName,
    required String actorRole,
    required bool isArabic,
  }) async {
    if (kIsWeb) return;
    final fromDoctor = actorRole == 'doctor';
    await _plugin.show(
      id: '$medicationName-$actorRole-change'.hashCode.abs(),
      title: isArabic
          ? fromDoctor
              ? 'تم تحديث الدواء من الطبيب'
              : 'تم تحديث الدواء من مقدم الرعاية'
          : fromDoctor
              ? 'Medication updated by doctor'
              : 'Medication updated by caregiver',
      body: isArabic
          ? 'تمت إضافة أو تحديث $medicationName.'
          : '$medicationName was added or updated.',
      notificationDetails: _reminderDetails(),
    );
  }

  Future<void> cancelMedicationReminders(Medication med) async {
    if (kIsWeb) return;
    for (final time in med.reminderTimes) {
      await _plugin.cancel(id: _notificationId(med.id, time, 'initial'));
      await _plugin.cancel(id: _notificationId(med.id, time, 'snooze'));
    }
  }

  Future<void> cancelDoseEscalation(DoseConfirmation dose) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _doseNotificationId(dose.id, 'second'));
  }

  NotificationDetails _medicationDetails({required bool isAlarm}) {
    if (!isAlarm) return _reminderDetails();

    return NotificationDetails(
      android: AndroidNotificationDetails(
        _alarmChannelId,
        'Medication alarms',
        channelDescription: 'Full-screen medication alarms',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        additionalFlags: Int32List.fromList(const <int>[4]),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            actionTakeMedication,
            'Taken',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            actionSnoozeMedication,
            'Snooze 5 min',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            actionDismissMedication,
            'Dismiss',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  NotificationDetails _reminderDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId,
        'Medication reminders',
        channelDescription: 'Medication reminder notifications',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  NotificationDetails _caregiverDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _caregiverChannelId,
        'Caregiver alerts',
        channelDescription:
            'Alerts for caregivers when patient doses are missed',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.message,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  String _medicationBody(Medication med, {required bool isArabic}) {
    final name =
        isArabic && med.nameAr.trim().isNotEmpty ? med.nameAr : med.name;
    return isArabic
        ? 'حان وقت تناول $name (${med.dosage}).'
        : 'Time to take $name (${med.dosage}).';
  }

  int _notificationId(String medicationId, ReminderTime time, String stage) =>
      '$medicationId-${time.hour}-${time.minute}-$stage'.hashCode.abs();

  int _doseNotificationId(String doseId, String stage) =>
      '$doseId-$stage'.hashCode.abs();

  String _medicationPayload(String medicationId, ReminderTime time) =>
      'med|$medicationId|${time.display}';

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
    final time = ReminderTime.fromString(dose.scheduledTime);
    return DateTime(
      dose.scheduledDate.year,
      dose.scheduledDate.month,
      dose.scheduledDate.day,
      time.hour,
      time.minute,
    );
  }
}

@pragma('vm:entry-point')
void _backgroundResponseHandler(NotificationResponse response) {}
