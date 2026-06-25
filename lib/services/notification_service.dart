import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import 'escalation_service.dart';
import 'firebase_backend_service.dart';
import 'local_db_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  static const actionTakeMedication = 'take_medication';
  static const actionSnoozeMedication = 'snooze_medication';
  static const actionRescheduleMedication = 'reschedule_medication_30';

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

  Future<void> handleBackgroundResponse(NotificationResponse response) async {
    final parsed = _ParsedMedicationPayload.tryParse(response.payload);
    if (parsed == null || parsed.patientId == null) return;

    await init();
    try {
      await FirebaseBackendService().init();
    } catch (e) {
      debugPrint('Notification action Firebase init skipped: $e');
    }
    final db = LocalDbService();
    final doses = await db.getDoseHistory(parsed.patientId!);
    final meds = await db.getMedications(parsed.patientId!);
    final dose = await _findOrCreatePayloadDose(
      db: db,
      patientId: parsed.patientId!,
      doses: doses,
      medications: meds,
      payload: parsed,
    );
    if (dose == null) return;

    final actionId = response.actionId;
    if (actionId == actionTakeMedication) {
      if (!_canConfirmDoseNow(dose)) return;
      final updated = dose.copyWith(
        status: DoseStatus.taken,
        confirmedAt: DateTime.now(),
      );
      await db.updateDose(parsed.patientId!, updated);
      await cancelDoseEscalation(updated);
      await EscalationService().cancelDoseAutoMiss(updated);
      final matches = meds.where((med) => med.id == dose.medicationId);
      if (matches.isNotEmpty) {
        final med = matches.first;
        if (med.quantityRemaining > 0) {
          await db.updateMedication(
            parsed.patientId!,
            med.copyWith(quantityRemaining: med.quantityRemaining - 1),
          );
        }
      }
      await db.logAdherenceEvent(
        patientId: parsed.patientId!,
        medicationId: updated.medicationId,
        eventType: 'taken',
        source: 'notificationAction',
        details: updated.id,
      );
      try {
        await FirebaseBackendService().updateDoseStatus(
          patientId: parsed.patientId!,
          dose: updated,
        );
        await FirebaseBackendService().logAdherenceEvent(
          patientId: parsed.patientId!,
          medicationId: updated.medicationId,
          eventType: 'taken',
          source: 'notificationAction',
          details: {'doseId': updated.id},
        );
      } catch (e) {
        debugPrint('Notification taken cloud sync skipped: $e');
      }
      return;
    }

    if (actionId == actionSnoozeMedication ||
        actionId == actionRescheduleMedication) {
      final delay = actionId == actionSnoozeMedication
          ? const Duration(minutes: 5)
          : const Duration(minutes: 30);
      final scheduledFor = DateTime.now().add(delay);
      final followUpDose = dose.copyWith(
        scheduledDate: DateTime(
          scheduledFor.year,
          scheduledFor.month,
          scheduledFor.day,
        ),
        scheduledTime: _formatTime(scheduledFor),
      );

      if (actionId == actionRescheduleMedication) {
        await db.updateDose(parsed.patientId!, followUpDose);
        await cancelDoseEscalation(dose);
        await EscalationService().cancelDoseAutoMiss(dose);
        await db.logAdherenceEvent(
          patientId: parsed.patientId!,
          medicationId: followUpDose.medicationId,
          eventType: 'doseRescheduled',
          source: 'notificationAction',
          details: followUpDose.id,
        );
        try {
          await FirebaseBackendService().updateDoseStatus(
            patientId: parsed.patientId!,
            dose: followUpDose,
          );
          await FirebaseBackendService().logAdherenceEvent(
            patientId: parsed.patientId!,
            medicationId: followUpDose.medicationId,
            eventType: 'doseRescheduled',
            source: 'notificationAction',
            details: {
              'doseId': followUpDose.id,
              'scheduledTime': followUpDose.scheduledTime,
            },
          );
        } catch (e) {
          debugPrint('Notification reschedule cloud sync skipped: $e');
        }
      }
      final medicationMatches =
          meds.where((med) => med.id == followUpDose.medicationId);
      await scheduleOneOffDoseReminder(
        dose: followUpDose,
        patientId: parsed.patientId!,
        medication: medicationMatches.isEmpty ? null : medicationMatches.first,
        isArabic: true,
        stage: actionId == actionSnoozeMedication ? 'snooze' : 'rescheduled',
      );
      if (actionId == actionRescheduleMedication) {
        await scheduleDoseEscalation(
          followUpDose,
          patientId: parsed.patientId!,
          isArabic: true,
        );
        await EscalationService().scheduleDoseAutoMiss(followUpDose);
      }
    }
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
    await androidPlugin?.requestFullScreenIntentPermission();

    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    final macPlugin = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macPlugin?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> scheduleMedicationReminders(
    Medication med, {
    required String patientId,
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
        notificationDetails: _medicationDetails(
          isAlarm: isAlarm,
          isArabic: isArabic,
        ),
        androidScheduleMode: isAlarm
            ? AndroidScheduleMode.alarmClock
            : AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: _medicationPayload(
          medicationId: med.id,
          scheduledTime: time.display,
          patientId: patientId,
        ),
      );
    }
  }

  Future<void> scheduleDoseEscalation(
    DoseConfirmation dose, {
    required String patientId,
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
      notificationDetails: _doseReminderDetails(isArabic: isArabic),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: _dosePayload(dose, patientId: patientId),
    );
  }

  Future<void> snoozeAlarm({
    required Medication med,
    required String patientId,
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
      notificationDetails: _medicationDetails(
        isAlarm: true,
        isArabic: isArabic,
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: _medicationPayload(
        medicationId: med.id,
        scheduledTime: time.display,
        patientId: patientId,
      ),
    );
  }

  Future<void> scheduleOneOffDoseReminder({
    required DoseConfirmation dose,
    required String patientId,
    Medication? medication,
    required bool isArabic,
    required String stage,
  }) async {
    if (kIsWeb || !dose.isPending) return;

    final scheduled = tz.TZDateTime.from(_scheduledDateTime(dose), tz.local);
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;

    final isAlarm = medication?.reminderType == ReminderType.alarm;
    await _plugin.zonedSchedule(
      id: _doseNotificationId(dose.id, stage),
      title: isAlarm ? 'Medication Alarm' : 'Medication Reminder',
      body: medication == null
          ? _doseBody(dose, isArabic: isArabic)
          : _medicationBody(medication, isArabic: isArabic),
      scheduledDate: scheduled,
      notificationDetails: _medicationDetails(
        isAlarm: isAlarm,
        isArabic: isArabic,
      ),
      androidScheduleMode: isAlarm
          ? AndroidScheduleMode.alarmClock
          : AndroidScheduleMode.exactAllowWhileIdle,
      payload: _dosePayload(dose, patientId: patientId),
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
      title: isArabic ? 'تذكير تعبئة الدواء' : 'Refill reminder',
      body: isArabic
          ? '${medication.displayNameAr} يكفي ${medication.estimatedDaysRemaining.ceil()} يوم فقط.'
          : '${medication.displayName} has ${medication.estimatedDaysRemaining.ceil()} days remaining.',
      notificationDetails: _basicReminderDetails(),
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
      notificationDetails: _basicReminderDetails(),
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
    await _plugin.cancel(id: _doseNotificationId(dose.id, 'snooze'));
    await _plugin.cancel(id: _doseNotificationId(dose.id, 'rescheduled'));
  }

  NotificationDetails _medicationDetails({
    required bool isAlarm,
    required bool isArabic,
  }) {
    if (!isAlarm) return _doseReminderDetails(isArabic: isArabic);

    return NotificationDetails(
      android: AndroidNotificationDetails(
        _alarmChannelId,
        'Medication alarms',
        channelDescription: 'Full-screen medication alarms',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        ongoing: false,
        autoCancel: true,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        additionalFlags: Int32List.fromList(const <int>[4]),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            actionTakeMedication,
            isArabic ? 'تم أخذها' : 'Taken',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            actionSnoozeMedication,
            isArabic ? 'غفوة 5 دقائق' : 'Snooze 5 min',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            actionRescheduleMedication,
            isArabic ? 'بعد 30 دقيقة' : 'In 30 min',
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

  NotificationDetails _doseReminderDetails({required bool isArabic}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId,
        'Medication reminders',
        channelDescription: 'Medication reminder notifications',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            actionTakeMedication,
            isArabic ? 'تم أخذها' : 'Taken',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            actionSnoozeMedication,
            isArabic ? 'غفوة 5 دقائق' : 'Snooze 5 min',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            actionRescheduleMedication,
            isArabic ? 'بعد 30 دقيقة' : 'In 30 min',
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

  NotificationDetails _basicReminderDetails() {
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

  String _doseBody(DoseConfirmation dose, {required bool isArabic}) {
    return isArabic
        ? 'حان وقت تناول ${dose.medicationName}.'
        : 'Time to take ${dose.medicationName}.';
  }

  int _notificationId(String medicationId, ReminderTime time, String stage) =>
      '$medicationId-${time.hour}-${time.minute}-$stage'.hashCode.abs();

  int _doseNotificationId(String doseId, String stage) =>
      '$doseId-$stage'.hashCode.abs();

  String _medicationPayload({
    required String medicationId,
    required String scheduledTime,
    required String patientId,
  }) =>
      'med|$medicationId|$scheduledTime||$patientId';

  String _dosePayload(DoseConfirmation dose, {required String patientId}) =>
      'med|${dose.medicationId}|${dose.scheduledTime}|${dose.id}|$patientId';

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

  bool _canConfirmDoseNow(DoseConfirmation dose) {
    final earliest =
        _scheduledDateTime(dose).subtract(const Duration(minutes: 30));
    return !DateTime.now().isBefore(earliest);
  }

  DoseConfirmation? _findPayloadDose(
    List<DoseConfirmation> doses,
    _ParsedMedicationPayload payload,
  ) {
    final pending = doses.where((dose) => dose.isPending);
    if (payload.doseId != null && payload.doseId!.isNotEmpty) {
      final matches = pending.where((dose) => dose.id == payload.doseId);
      if (matches.isNotEmpty) return matches.first;
    }
    final matches = pending.where(
      (dose) =>
          dose.medicationId == payload.medicationId &&
          dose.scheduledTime == payload.scheduledTime,
    );
    return matches.isEmpty ? null : matches.first;
  }

  Future<DoseConfirmation?> _findOrCreatePayloadDose({
    required LocalDbService db,
    required String patientId,
    required List<DoseConfirmation> doses,
    required List<Medication> medications,
    required _ParsedMedicationPayload payload,
  }) async {
    final existing = _findPayloadDose(doses, payload);
    if (existing != null) return existing;

    final medicationMatches = medications
        .where((medication) => medication.id == payload.medicationId);
    if (medicationMatches.isEmpty) return null;

    final medication = medicationMatches.first;
    final now = DateTime.now();
    final doseDate = DateTime(now.year, now.month, now.day);
    final dose = DoseConfirmation(
      id: '${medication.id}-${_dateKey(doseDate)}-${payload.scheduledTime}',
      medicationId: medication.id,
      medicationName: medication.displayName,
      scheduledTime: payload.scheduledTime,
      scheduledDate: doseDate,
      status: DoseStatus.pending,
    );
    await db.insertDose(patientId, dose);
    return dose;
  }

  String _formatTime(DateTime dateTime) =>
      '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

  String _dateKey(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
}

class _ParsedMedicationPayload {
  final String medicationId;
  final String scheduledTime;
  final String? doseId;
  final String? patientId;

  const _ParsedMedicationPayload({
    required this.medicationId,
    required this.scheduledTime,
    this.doseId,
    this.patientId,
  });

  static _ParsedMedicationPayload? tryParse(String? payload) {
    if (payload == null || !payload.startsWith('med|')) return null;
    final parts = payload.split('|');
    if (parts.length < 3) return null;
    return _ParsedMedicationPayload(
      medicationId: parts[1],
      scheduledTime: parts[2],
      doseId: parts.length >= 4 && parts[3].isNotEmpty ? parts[3] : null,
      patientId: parts.length >= 5 && parts[4].isNotEmpty ? parts[4] : null,
    );
  }
}

@pragma('vm:entry-point')
Future<void> _backgroundResponseHandler(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationService().handleBackgroundResponse(response);
}
