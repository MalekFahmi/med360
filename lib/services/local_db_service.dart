// Full local SQLite database — no server needed.
// Stores patients, medications, dose history, and caregiver notifications.
// Uses sqflite package.

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart';
import '../models/models.dart';
import 'local_db_schema.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      return openDatabase(
        'med360.db',
        version: LocalDbSchema.version,
        onCreate: LocalDbSchema.onCreate,
        onUpgrade: LocalDbSchema.onUpgrade,
        onOpen: LocalDbSchema.ensureSchema,
      );
    }
    final path = join(await getDatabasesPath(), 'med360.db');
    return openDatabase(
      path,
      version: LocalDbSchema.version,
      onCreate: LocalDbSchema.onCreate,
      onUpgrade: LocalDbSchema.onUpgrade,
      onOpen: LocalDbSchema.ensureSchema,
    );
  }

  // ─── Patient ──────────────────────────────────────────────────────────────

  Future<void> insertPatient(PatientUser patient) async {
    final d = await db;
    await d.insert(
        'patients',
        {
          'id': patient.id,
          'name': patient.name,
          'phone': patient.phone,
          'passwordHash': patient.passwordHash,
          'dateOfBirth': patient.dateOfBirth?.toIso8601String(),
          'chronicCondition': patient.chronicCondition,
          'arabicMode': patient.arabicMode ? 1 : 0,
          'largeFonts': patient.largeFonts ? 1 : 0,
          'highContrast': patient.highContrast ? 1 : 0,
          'caregiverAlertsEnabled': patient.caregiverAlertsEnabled ? 1 : 0,
          'createdAt': patient.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    // Insert caregivers
    for (final cg in patient.caregivers) {
      await insertCaregiver(patient.id, cg);
    }
  }

  Future<PatientUser?> getPatientByPhone(String phone) async {
    final d = await db;
    final rows =
        await d.query('patients', where: 'phone = ?', whereArgs: [phone]);
    if (rows.isEmpty) return null;
    return _rowToPatient(
        rows.first, await _getCaregivers(rows.first['id'] as String, d));
  }

  Future<PatientUser?> getPatientById(String id) async {
    final d = await db;
    final rows = await d.query('patients', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _rowToPatient(rows.first, await _getCaregivers(id, d));
  }

  Future<void> updatePatient(PatientUser patient) async {
    final d = await db;
    await d.update(
        'patients',
        {
          'name': patient.name,
          'phone': patient.phone,
          'arabicMode': patient.arabicMode ? 1 : 0,
          'largeFonts': patient.largeFonts ? 1 : 0,
          'highContrast': patient.highContrast ? 1 : 0,
          'caregiverAlertsEnabled': patient.caregiverAlertsEnabled ? 1 : 0,
          'chronicCondition': patient.chronicCondition,
        },
        where: 'id = ?',
        whereArgs: [patient.id]);
  }

  PatientUser _rowToPatient(
          Map<String, dynamic> row, List<Caregiver> caregivers) =>
      PatientUser(
        id: row['id'],
        name: row['name'],
        phone: row['phone'],
        passwordHash: row['passwordHash'],
        dateOfBirth: row['dateOfBirth'] != null
            ? DateTime.parse(row['dateOfBirth'])
            : null,
        chronicCondition: row['chronicCondition'],
        caregivers: caregivers,
        arabicMode: row['arabicMode'] == null ? true : row['arabicMode'] == 1,
        largeFonts: row['largeFonts'] == 1,
        highContrast: row['highContrast'] == 1,
        caregiverAlertsEnabled: row['caregiverAlertsEnabled'] == 1,
        createdAt: DateTime.parse(row['createdAt']),
      );

  // ─── Caregivers ───────────────────────────────────────────────────────────

  Future<void> insertCaregiver(String patientId, Caregiver cg) async {
    final d = await db;
    await d.insert(
        'caregivers',
        {
          'id': cg.id,
          'patientId': patientId,
          'name': cg.name,
          'email': cg.email,
          'phone': cg.phone,
          'relationship': cg.relationship,
          'permission': cg.permission.name,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCaregiver(String caregiverId) async {
    final d = await db;
    await d.delete('caregivers', where: 'id = ?', whereArgs: [caregiverId]);
  }

  Future<List<Caregiver>> _getCaregivers(String patientId, Database d) async {
    final rows = await d
        .query('caregivers', where: 'patientId = ?', whereArgs: [patientId]);
    return rows
        .map((r) => Caregiver(
              id: r['id'] as String,
              name: r['name'] as String,
              email: r['email'] as String?,
              phone: r['phone'] as String,
              relationship: r['relationship'] as String,
              permission: NotificationPermission.values
                  .byName(r['permission'] as String),
            ))
        .toList();
  }

  // ─── Medications ──────────────────────────────────────────────────────────

  Future<void> insertMedication(String patientId, Medication med) async {
    final d = await db;
    final timesJson =
        med.reminderTimes.map((t) => '${t.hour}:${t.minute}').join(',');
    await d.insert(
        'medications',
        {
          'id': med.id,
          'patientId': patientId,
          'name': med.name,
          'nameAr': med.nameAr,
          'dosage': med.dosage,
          'form': med.form.name,
          'indication': med.indication,
          'indicationAr': med.indicationAr,
          'reminderTimesJson': timesJson,
          'reminderType': med.reminderType.name,
          'status': med.status.name,
          'startDate': med.startDate.toIso8601String(),
          'endDate': med.endDate?.toIso8601String(),
          'quantityRemaining': med.quantityRemaining,
          'dosesPerDay': med.dosesPerDay,
          'refillThreshold': med.refillThreshold,
          'notes': med.notes,
          'notesAr': med.notesAr,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMedication(String patientId, Medication med) async =>
      insertMedication(patientId, med);

  Future<void> deleteMedication(String medicationId,
      {String? patientId}) async {
    final d = await db;
    await d.delete(
      'medications',
      where: patientId == null ? 'id = ?' : 'id = ? AND patientId = ?',
      whereArgs: patientId == null ? [medicationId] : [medicationId, patientId],
    );
  }

  Future<List<DoseConfirmation>> getPendingDosesForMedication({
    required String patientId,
    required String medicationId,
  }) async {
    final d = await db;
    final rows = await d.query(
      'dose_confirmations',
      where: 'patientId = ? AND medicationId = ? AND status = ?',
      whereArgs: [patientId, medicationId, DoseStatus.pending.name],
    );
    return rows
        .map((r) => DoseConfirmation(
              id: r['id'] as String,
              medicationId: r['medicationId'] as String,
              medicationName: r['medicationName'] as String,
              scheduledTime: r['scheduledTime'] as String,
              scheduledDate: DateTime.parse(r['scheduledDate'] as String),
              confirmedAt: r['confirmedAt'] != null
                  ? DateTime.parse(r['confirmedAt'] as String)
                  : null,
              status: DoseStatus.values.byName(r['status'] as String),
              caregiverNotified: r['caregiverNotified'] == 1,
              secondReminderSent: r['secondReminderSent'] == 1,
            ))
        .toList();
  }

  Future<void> deletePendingDosesForMedication({
    required String patientId,
    required String medicationId,
  }) async {
    final d = await db;
    await d.delete(
      'dose_confirmations',
      where: 'patientId = ? AND medicationId = ? AND status = ?',
      whereArgs: [patientId, medicationId, DoseStatus.pending.name],
    );
  }

  Future<List<Medication>> getMedications(String patientId) async {
    final d = await db;
    final rows = await d
        .query('medications', where: 'patientId = ?', whereArgs: [patientId]);
    return rows.map(_rowToMedication).toList();
  }

  Medication _rowToMedication(Map<String, dynamic> r) {
    final timesRaw = (r['reminderTimesJson'] as String).split(',');
    final times = timesRaw.map((t) {
      final parts = t.split(':');
      return ReminderTime(
          hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }).toList();
    return Medication(
      id: r['id'],
      name: r['name'],
      nameAr: r['nameAr'] ?? r['name'],
      dosage: r['dosage'],
      form: MedicationForm.values.byName(r['form']),
      indication: r['indication'] ?? '',
      indicationAr: r['indicationAr'] ?? '',
      reminderTimes: times,
      reminderType: ReminderType.values.byName(r['reminderType']),
      status: MedicationStatus.values.byName(r['status']),
      startDate: DateTime.parse(r['startDate']),
      endDate: r['endDate'] != null
          ? DateTime.tryParse(r['endDate'] as String)
          : null,
      quantityRemaining: (r['quantityRemaining'] as int?) ?? 0,
      dosesPerDay: (r['dosesPerDay'] as num?)?.toDouble() ?? 1,
      refillThreshold: (r['refillThreshold'] as int?) ?? 7,
      notes: r['notes'],
      notesAr: r['notesAr'],
    );
  }

  Future<void> logMedicationChange({
    required String patientId,
    required String medicationId,
    required String action,
    required String actorRole,
    String? actorId,
    String? details,
  }) async {
    final d = await db;
    final now = DateTime.now();
    await d.insert(
      'medication_change_logs',
      {
        'id': 'MLOG-${now.microsecondsSinceEpoch}',
        'patientId': patientId,
        'medicationId': medicationId,
        'action': action,
        'actorRole': actorRole,
        'actorId': actorId,
        'changedAt': now.toIso8601String(),
        'details': details,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> logAdherenceEvent({
    required String patientId,
    String? medicationId,
    required String eventType,
    required String source,
    String? details,
  }) async {
    final d = await db;
    final now = DateTime.now();
    await d.insert(
      'adherence_events',
      {
        'id': 'AE-${now.microsecondsSinceEpoch}',
        'patientId': patientId,
        'medicationId': medicationId,
        'eventType': eventType,
        'source': source,
        'timestamp': now.toIso8601String(),
        'details': details,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> logRefillEvent({
    required String patientId,
    required Medication medication,
    int? milestone,
  }) async {
    final d = await db;
    final now = DateTime.now();
    await d.insert(
      'refill_events',
      {
        'id': 'REF-${now.microsecondsSinceEpoch}',
        'patientId': patientId,
        'medicationId': medication.id,
        'medicationName': medication.name,
        'daysRemaining': medication.estimatedDaysRemaining,
        'threshold': medication.refillThreshold,
        'milestone': milestone,
        'createdAt': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> hasRefillEventForMilestone({
    required String patientId,
    required String medicationId,
    required int milestone,
  }) async {
    final d = await db;
    final rows = await d.query(
      'refill_events',
      where:
          'patientId = ? AND medicationId = ? AND milestone = ? AND completedAt IS NULL',
      whereArgs: [patientId, medicationId, milestone],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> logRefillCompleted({
    required String patientId,
    required Medication medication,
  }) async {
    final d = await db;
    final now = DateTime.now().toIso8601String();
    await d.update(
      'refill_events',
      {'completedAt': now},
      where: 'patientId = ? AND medicationId = ? AND completedAt IS NULL',
      whereArgs: [patientId, medication.id],
    );
  }

  // ─── Dose confirmations ───────────────────────────────────────────────────

  Future<void> insertDose(String patientId, DoseConfirmation dose) async {
    final d = await db;
    await d.insert(
        'dose_confirmations',
        {
          'id': dose.id,
          'patientId': patientId,
          'medicationId': dose.medicationId,
          'medicationName': dose.medicationName,
          'scheduledTime': dose.scheduledTime,
          'scheduledDate': dose.scheduledDate.toIso8601String(),
          'confirmedAt': dose.confirmedAt?.toIso8601String(),
          'status': dose.status.name,
          'caregiverNotified': dose.caregiverNotified ? 1 : 0,
          'secondReminderSent': dose.secondReminderSent ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateDose(String patientId, DoseConfirmation dose) async =>
      insertDose(patientId, dose);

  Future<List<DoseConfirmation>> getDoseHistory(String patientId) async {
    final d = await db;
    final rows = await d.query('dose_confirmations',
        where: 'patientId = ?',
        whereArgs: [patientId],
        orderBy: 'scheduledDate ASC');
    return rows
        .map((r) => DoseConfirmation(
              id: r['id'] as String,
              medicationId: r['medicationId'] as String,
              medicationName: r['medicationName'] as String,
              scheduledTime: r['scheduledTime'] as String,
              scheduledDate: DateTime.parse(r['scheduledDate'] as String),
              confirmedAt: r['confirmedAt'] != null
                  ? DateTime.parse(r['confirmedAt'] as String)
                  : null,
              status: DoseStatus.values.byName(r['status'] as String),
              caregiverNotified: r['caregiverNotified'] == 1,
              secondReminderSent: r['secondReminderSent'] == 1,
            ))
        .toList();
  }

  // ─── Caregiver notifications ──────────────────────────────────────────────

  Future<void> insertCaregiverNotification(
      String patientId, CaregiverNotification n) async {
    final d = await db;
    await d.insert(
        'caregiver_notifications',
        {
          'id': n.id,
          'patientId': patientId,
          'patientName': n.patientName,
          'caregiverId': n.caregiverId,
          'caregiverName': n.caregiverName,
          'medicationId': n.medicationId,
          'medicationName': n.medicationName,
          'missedAt': n.missedAt?.toIso8601String(),
          'sentAt': n.sentAt.toIso8601String(),
          'channel': n.channel.name,
          'acknowledged': n.acknowledged ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<CaregiverNotification>> getCaregiverNotifications(
      String patientId) async {
    final d = await db;
    // For local simplicity, we'll fetch all; ideally we filter by patientId OR caregiverId
    final rows = await d.query('caregiver_notifications',
        where: 'patientId = ?', whereArgs: [patientId], orderBy: 'sentAt DESC');
    return rows
        .map((r) => CaregiverNotification(
              id: r['id'] as String,
              caregiverId: r['caregiverId'] as String,
              caregiverName: r['caregiverName'] as String,
              patientId: r['patientId'] as String,
              patientName: r['patientName'] as String,
              medicationId: r['medicationId'] as String?,
              medicationName: r['medicationName'] as String?,
              missedAt: r['missedAt'] != null
                  ? DateTime.parse(r['missedAt'] as String)
                  : null,
              sentAt: DateTime.parse(r['sentAt'] as String),
              channel:
                  NotificationChannel.values.byName(r['channel'] as String),
              acknowledged: r['acknowledged'] == 1,
            ))
        .toList();
  }

  Future<void> markNotificationRead(String notifId) async {
    final d = await db;
    await d.update('caregiver_notifications', {'acknowledged': 1},
        where: 'id = ?', whereArgs: [notifId]);
  }
}
