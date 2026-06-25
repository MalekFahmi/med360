import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/models.dart';
import 'dose_generator.dart';
import 'firebase_backend_service.dart';
import 'local_db_service.dart';
import 'notification_service.dart';

const String escalationPeriodicTask = 'med360.escalation.periodic';
const String escalationOneOffTask = 'med360.escalation.one_off';

@pragma('vm:entry-point')
void escalationCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService().init();
    await FirebaseBackendService().init();
    await EscalationService().runBackgroundCheck();
    return true;
  });
}

class EscalationService {
  static final EscalationService _instance = EscalationService._internal();
  factory EscalationService() => _instance;
  EscalationService._internal();

  static const secondReminderDelay = Duration(minutes: 5);
  static const autoMissDelay = Duration(minutes: 10);
  static const _periodicTaskName = 'med360-escalation-periodic';
  static const _oneOffPrefix = 'med360-escalation-dose';

  bool _workmanagerInitialized = false;

  Future<void> initWorkmanager() async {
    if (kIsWeb || _workmanagerInitialized) return;
    try {
      await Workmanager().initialize(
        escalationCallbackDispatcher,
      );
      await Workmanager().registerPeriodicTask(
        _periodicTaskName,
        escalationPeriodicTask,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      _workmanagerInitialized = true;
    } catch (e) {
      debugPrint('Workmanager escalation setup skipped: $e');
    }
  }

  Future<void> scheduleDoseAutoMiss(DoseConfirmation dose) async {
    if (kIsWeb || !dose.isPending) return;
    final runAt = scheduledDateTime(dose).add(autoMissDelay);
    final delay = runAt.difference(DateTime.now());
    if (delay.isNegative) return;
    try {
      await Workmanager().registerOneOffTask(
        _oneOffName(dose.id),
        escalationOneOffTask,
        initialDelay: delay,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        inputData: {'doseId': dose.id},
      );
    } catch (e) {
      debugPrint('Dose auto-miss work scheduling skipped: $e');
    }
  }

  Future<void> cancelDoseAutoMiss(DoseConfirmation dose) async {
    if (kIsWeb) return;
    try {
      await Workmanager().cancelByUniqueName(_oneOffName(dose.id));
    } catch (e) {
      debugPrint('Dose auto-miss work cancel skipped: $e');
    }
  }

  Future<List<DoseConfirmation>> runBackgroundCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString('loggedInPatientId');
    if (patientId == null) return const [];

    final db = LocalDbService();
    final patient = await db.getPatientById(patientId);
    if (patient == null) return const [];

    final allDoses = await _loadAndGenerateTodayDoses(
      db: db,
      patient: patient,
    );
    final now = DateTime.now();
    final missed = <DoseConfirmation>[];

    for (final dose in allDoses.where((d) => d.isPending)) {
      final scheduledAt = scheduledDateTime(dose);
      var updated = dose;

      if (!updated.secondReminderSent &&
          now.isAfter(scheduledAt.add(secondReminderDelay))) {
        updated = updated.copyWith(secondReminderSent: true);
        await db.updateDose(patientId, updated);
        await FirebaseBackendService().updateDoseStatus(
          patientId: patientId,
          dose: updated,
        );
      }

      if (now.isAfter(scheduledAt.add(autoMissDelay))) {
        final alertableCaregivers = _alertableCaregivers(patient.caregivers);
        final notifyCaregivers = patient.caregiverAlertsEnabled &&
            alertableCaregivers.isNotEmpty &&
            !updated.caregiverNotified;
        updated = updated.copyWith(
          status: DoseStatus.missed,
          confirmedAt: now,
          caregiverNotified: notifyCaregivers,
          secondReminderSent: true,
        );
        await db.updateDose(patientId, updated);
        await NotificationService().cancelDoseEscalation(updated);
        await cancelDoseAutoMiss(updated);
        await FirebaseBackendService().updateDoseStatus(
          patientId: patientId,
          dose: updated,
        );
        if (notifyCaregivers) {
          await _notifyCaregivers(
            db: db,
            patient: patient,
            dose: updated,
            caregivers: alertableCaregivers,
          );
        }
        missed.add(updated);
      }
    }

    return missed;
  }

  Future<List<DoseConfirmation>> _loadAndGenerateTodayDoses({
    required LocalDbService db,
    required PatientUser patient,
  }) async {
    final existingDoses = await db.getDoseHistory(patient.id);
    final medications = await db.getMedications(patient.id);
    final newDoses = DoseGenerator.generateForDate(
      medications: medications,
      existingDoses: existingDoses,
      date: DateTime.now(),
    );

    for (final dose in newDoses) {
      await db.insertDose(patient.id, dose);
      await NotificationService().scheduleDoseEscalation(
        dose,
        patientId: patient.id,
        isArabic: patient.arabicMode,
      );
      await scheduleDoseAutoMiss(dose);
      await FirebaseBackendService().upsertDose(
        patientId: patient.id,
        patientName: patient.name,
        dose: dose,
        caregivers: patient.caregivers,
        caregiverAlertsEnabled: patient.caregiverAlertsEnabled,
        isArabic: patient.arabicMode,
      );
    }

    return [...existingDoses, ...newDoses];
  }

  DateTime scheduledDateTime(DoseConfirmation dose) {
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

  List<Caregiver> _alertableCaregivers(List<Caregiver> caregivers) => caregivers
      .where((c) =>
          c.permission == NotificationPermission.missedDoseOnly ||
          c.permission == NotificationPermission.all)
      .toList();

  Future<void> _notifyCaregivers({
    required LocalDbService db,
    required PatientUser patient,
    required DoseConfirmation dose,
    required List<Caregiver> caregivers,
  }) async {
    for (final caregiver in caregivers) {
      final notification = CaregiverNotification(
        id: 'MISS-${dose.id}-${caregiver.id}',
        caregiverId: caregiver.id,
        caregiverName: caregiver.name,
        patientId: patient.id,
        patientName: patient.name,
        medicationId: dose.medicationId,
        medicationName: dose.medicationName,
        missedAt: dose.confirmedAt ?? DateTime.now(),
        sentAt: DateTime.now(),
        channel: NotificationChannel.both,
      );
      await db.insertCaregiverNotification(patient.id, notification);
      await FirebaseBackendService().sendMissedDoseAlert(
        patientId: patient.id,
        patientName: patient.name,
        caregiverId: caregiver.id,
        notification: notification,
        isArabic: patient.arabicMode,
      );
    }
  }

  String _oneOffName(String doseId) => '$_oneOffPrefix-$doseId';
}
