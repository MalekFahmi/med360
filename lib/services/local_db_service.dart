// Full local SQLite database — no server needed.
// Stores patients, medications, dose history, and caregiver notifications.
// Uses sqflite package.

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart';
import '../models/models.dart';

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
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: _ensureCaregiverEmailColumn,
      );
    }
    final path = join(await getDatabasesPath(), 'med360.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _ensureCaregiverEmailColumn,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _ensureCaregiverEmailColumn(db);
    }
    if (oldVersion < 3) {
      await _ensureDoseEscalationColumns(db);
    }
  }

  Future<void> _ensureCaregiverEmailColumn(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'caregivers'",
    );
    if (tables.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info(caregivers)');
    final hasEmail = columns.any((column) => column['name'] == 'email');
    if (!hasEmail) {
      await db.execute('ALTER TABLE caregivers ADD COLUMN email TEXT');
    }
  }

  Future<void> _ensureDoseEscalationColumns(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'dose_confirmations'",
    );
    if (tables.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info(dose_confirmations)');
    final hasSecondReminder =
        columns.any((column) => column['name'] == 'secondReminderSent');
    if (!hasSecondReminder) {
      await db.execute(
        'ALTER TABLE dose_confirmations ADD COLUMN secondReminderSent INTEGER DEFAULT 0',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Patients table
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        passwordHash TEXT NOT NULL,
        dateOfBirth TEXT,
        chronicCondition TEXT,
        arabicMode INTEGER DEFAULT 0,
        largeFonts INTEGER DEFAULT 0,
        highContrast INTEGER DEFAULT 0,
        caregiverAlertsEnabled INTEGER DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    // Caregivers table (linked to a patient)
    await db.execute('''
      CREATE TABLE caregivers (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        name TEXT NOT NULL,
        email TEXT,
        phone TEXT NOT NULL,
        relationship TEXT NOT NULL,
        permission TEXT NOT NULL,
        FOREIGN KEY (patientId) REFERENCES patients (id)
      )
    ''');

    // Medications table
    await db.execute('''
      CREATE TABLE medications (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        name TEXT NOT NULL,
        nameAr TEXT,
        dosage TEXT NOT NULL,
        form TEXT NOT NULL,
        indication TEXT,
        indicationAr TEXT,
        reminderTimesJson TEXT NOT NULL,
        reminderType TEXT NOT NULL,
        status TEXT NOT NULL,
        startDate TEXT NOT NULL,
        notes TEXT,
        notesAr TEXT,
        FOREIGN KEY (patientId) REFERENCES patients (id)
      )
    ''');

    // Dose confirmations table
    await db.execute('''
      CREATE TABLE dose_confirmations (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        medicationId TEXT NOT NULL,
        medicationName TEXT NOT NULL,
        scheduledTime TEXT NOT NULL,
        scheduledDate TEXT NOT NULL,
        confirmedAt TEXT,
        status TEXT NOT NULL,
        caregiverNotified INTEGER DEFAULT 0,
        secondReminderSent INTEGER DEFAULT 0,
        FOREIGN KEY (patientId) REFERENCES patients (id)
      )
    ''');

    // Caregiver notifications log
    await db.execute('''
      CREATE TABLE caregiver_notifications (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        patientName TEXT NOT NULL,
        caregiverId TEXT NOT NULL,
        caregiverName TEXT NOT NULL,
        medicationId TEXT,
        medicationName TEXT,
        missedAt TEXT,
        sentAt TEXT NOT NULL,
        channel TEXT NOT NULL,
        acknowledged INTEGER DEFAULT 0,
        FOREIGN KEY (patientId) REFERENCES patients (id)
      )
    ''');
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
        arabicMode: row['arabicMode'] == 1,
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
          'notes': med.notes,
          'notesAr': med.notesAr,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMedication(String patientId, Medication med) async =>
      insertMedication(patientId, med);

  Future<void> deleteMedication(String medicationId) async {
    final d = await db;
    await d.delete('medications', where: 'id = ?', whereArgs: [medicationId]);
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
      notes: r['notes'],
      notesAr: r['notesAr'],
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
      String userId) async {
    final d = await db;
    // For local simplicity, we'll fetch all; ideally we filter by patientId OR caregiverId
    final rows = await d.query('caregiver_notifications',
        where: 'patientId = ?', whereArgs: [patientId], orderBy: 'sentAt DESC');
    return rows
        .map((r) => CaregiverNotification(
              id: r['id'] as String,
              caregiverId: r['caregiverId'] as String,
              caregiverName: r['caregiverName'] as String,
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
