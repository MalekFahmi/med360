import 'package:sqflite/sqflite.dart';

class LocalDbSchema {
  LocalDbSchema._();

  static const version = 4;

  static Future<void> onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        passwordHash TEXT NOT NULL,
        dateOfBirth TEXT,
        chronicCondition TEXT,
        arabicMode INTEGER DEFAULT 1,
        largeFonts INTEGER DEFAULT 0,
        highContrast INTEGER DEFAULT 0,
        caregiverAlertsEnabled INTEGER DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

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
        endDate TEXT,
        quantityRemaining INTEGER DEFAULT 0,
        dosesPerDay REAL DEFAULT 1,
        refillThreshold INTEGER DEFAULT 3,
        FOREIGN KEY (patientId) REFERENCES patients (id)
      )
    ''');

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

    await ensurePhaseTwoTables(db);
  }

  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await ensureCaregiverEmailColumn(db);
    }
    if (oldVersion < 3) {
      await ensureDoseEscalationColumns(db);
    }
    if (oldVersion < 4) {
      await ensureMedicationInventoryColumns(db);
      await ensurePhaseTwoTables(db);
    }
    await ensureCaregiverNotificationPatientNameColumn(db);
  }

  static Future<void> ensureSchema(Database db) async {
    await ensureCaregiverEmailColumn(db);
    await ensureDoseEscalationColumns(db);
    await ensureCaregiverNotificationPatientNameColumn(db);
    await ensureMedicationInventoryColumns(db);
    await ensurePhaseTwoTables(db);
  }

  static Future<void> ensureCaregiverEmailColumn(Database db) async {
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

  static Future<void> ensureDoseEscalationColumns(Database db) async {
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

  static Future<void> ensureCaregiverNotificationPatientNameColumn(
    Database db,
  ) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'caregiver_notifications'",
    );
    if (tables.isEmpty) return;
    final columns =
        await db.rawQuery('PRAGMA table_info(caregiver_notifications)');
    final hasPatientName =
        columns.any((column) => column['name'] == 'patientName');
    if (!hasPatientName) {
      await db.execute(
        "ALTER TABLE caregiver_notifications ADD COLUMN patientName TEXT DEFAULT ''",
      );
    }
  }

  static Future<void> ensureMedicationInventoryColumns(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'medications'",
    );
    if (tables.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info(medications)');
    Future<void> addColumn(String name, String definition) async {
      if (!columns.any((column) => column['name'] == name)) {
        await db.execute('ALTER TABLE medications ADD COLUMN $definition');
      }
    }

    await addColumn('endDate', 'endDate TEXT');
    await addColumn('quantityRemaining', 'quantityRemaining INTEGER DEFAULT 0');
    await addColumn('dosesPerDay', 'dosesPerDay REAL DEFAULT 1');
    await addColumn('refillThreshold', 'refillThreshold INTEGER DEFAULT 3');
  }

  static Future<void> ensurePhaseTwoTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medication_change_logs (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        medicationId TEXT NOT NULL,
        action TEXT NOT NULL,
        actorRole TEXT NOT NULL,
        actorId TEXT,
        changedAt TEXT NOT NULL,
        details TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS refill_events (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        medicationId TEXT NOT NULL,
        medicationName TEXT NOT NULL,
        daysRemaining REAL NOT NULL,
        threshold INTEGER NOT NULL,
        milestone INTEGER,
        createdAt TEXT NOT NULL,
        completedAt TEXT
      )
    ''');
    final columns = await db.rawQuery('PRAGMA table_info(refill_events)');
    if (!columns.any((column) => column['name'] == 'milestone')) {
      await db.execute(
        'ALTER TABLE refill_events ADD COLUMN milestone INTEGER',
      );
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS adherence_events (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        medicationId TEXT,
        eventType TEXT NOT NULL,
        source TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        details TEXT
      )
    ''');
  }
}
