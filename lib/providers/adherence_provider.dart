import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/escalation_service.dart';
import '../services/firebase_backend_domains.dart';
import '../services/firebase_backend_service.dart';
import '../services/local_db_service.dart';
import '../services/notification_service.dart';
import '../services/dose_generator.dart';
import 'medication_provider.dart' show LoadStatus;

export 'medication_provider.dart' show LoadStatus;

class AdherenceProvider extends ChangeNotifier {
  final LocalDbService _db;
  AdherenceProvider(this._db);

  LoadStatus _status = LoadStatus.initial;
  List<DoseConfirmation> _allDoses = [];
  String? _errorMessage;

  LoadStatus get status => _status;
  bool get isLoading => _status == LoadStatus.loading;
  String? get errorMessage => _errorMessage;
  List<DoseConfirmation> get allDoses => _allDoses;
  bool _showDailyCelebration = false;

  bool get showDailyCelebration => _showDailyCelebration;

  List<DoseConfirmation> get todaysDoses {
    final today = DateTime.now();
    return _allDoses.where((d) => d.isOnDate(today)).toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  }

  int get pendingCount => todaysDoses.where((d) => d.isPending).length;
  int get todaysTakenCount => todaysDoses.where((d) => d.isTaken).length;
  int get todaysMissedCount => todaysDoses.where((d) => d.isMissed).length;
  double get todaysAdherenceRate {
    final resolved = todaysTakenCount + todaysMissedCount;
    if (resolved == 0) {
      return todaysDoses.isNotEmpty && pendingCount == 0 ? 1.0 : 0.0;
    }
    return todaysTakenCount / resolved;
  }

  int get currentStreak => _streaks().$1;
  int get longestStreak => _streaks().$2;

  List<DoseConfirmation> dosesForDate(DateTime date) =>
      _allDoses.where((d) => d.isOnDate(date)).toList();

  bool allTakenOnDate(DateTime date) {
    final doses = dosesForDate(date);
    return doses.isNotEmpty && doses.every((d) => d.isTaken);
  }

  void clearDailyCelebration() {
    _showDailyCelebration = false;
    notifyListeners();
  }

  bool anyMissedOnDate(DateTime date) =>
      dosesForDate(date).any((d) => d.isMissed);

  double monthlyAdherenceRate(int year, int month) {
    final doses = _allDoses.where(
        (d) => d.scheduledDate.year == year && d.scheduledDate.month == month);
    final taken = doses.where((d) => d.isTaken).length;
    final missed = doses.where((d) => d.isMissed).length;
    final resolved = taken + missed;
    return resolved == 0 ? 0.0 : taken / resolved;
  }

  String monthlyAdherencePercentage(int year, int month) =>
      '${(monthlyAdherenceRate(year, month) * 100).round()}%';

  List<Map<String, dynamic>> weeklyBreakdown(int year, int month) {
    final weeks = <Map<String, dynamic>>[];
    int weekNum = 1, day = 1;
    while (day <= 31) {
      final start = DateTime(year, month, day);
      if (start.month != month) break;
      final end = DateTime(year, month, day + 6);
      final weekDoses = _allDoses.where((d) =>
          !d.scheduledDate.isBefore(start) &&
          d.scheduledDate.isBefore(end.add(const Duration(days: 1))) &&
          d.scheduledDate.month == month);
      final taken = weekDoses.where((d) => d.isTaken).length;
      final missed = weekDoses.where((d) => d.isMissed).length;
      final resolved = taken + missed;
      weeks.add({
        'label': 'W$weekNum',
        'rate': resolved == 0 ? 0.0 : taken / resolved,
        'taken': taken,
        'missed': missed,
      });
      weekNum++;
      day += 7;
    }
    return weeks;
  }

  // ── Load from DB, then generate today's doses if not already there ────────
  Future<void> loadAndGenerate({
    required String patientId,
    required List<Medication> medications,
    String patientName = 'Patient',
    List<Caregiver> caregivers = const [],
    bool caregiverAlertsEnabled = true,
    bool isArabic = false,
  }) async {
    _status = LoadStatus.loading;
    notifyListeners();
    try {
      _allDoses = await _db.getDoseHistory(patientId);

      // Generate pending doses for today from active medications
      final today = DateTime.now();
      final newDoses = DoseGenerator.generateForDate(
        medications: medications,
        existingDoses: _allDoses,
        date: today,
      );

      for (final dose in newDoses) {
        await _db.insertDose(patientId, dose);
      }
      _allDoses = [..._allDoses, ...newDoses];
      await _mirrorPendingDoses(
        patientId: patientId,
        patientName: patientName,
        caregivers: caregivers,
        caregiverAlertsEnabled: caregiverAlertsEnabled,
        isArabic: isArabic,
      );
      await _schedulePendingEscalations(isArabic: isArabic);
      _status = LoadStatus.loaded;
    } catch (e) {
      _errorMessage = 'تعذر تحميل سجل الجرعات / Could not load dose history.';
      _status = LoadStatus.error;
    }
    notifyListeners();
  }

  // ── FR5: Confirm taken ────────────────────────────────────────────────────
  Future<void> confirmDoseTaken(
    String doseId,
    String patientId, {
    String source = 'patient',
  }) async {
    final confirmedAt = DateTime.now();
    _allDoses = _allDoses.map((d) {
      if (d.id != doseId) return d;
      return d.copyWith(status: DoseStatus.taken, confirmedAt: confirmedAt);
    }).toList();
    notifyListeners();
    final updated = _allDoses.firstWhere((d) => d.id == doseId);
    await _db.updateDose(patientId, updated);
    await NotificationService().cancelDoseEscalation(updated);
    await EscalationService().cancelDoseAutoMiss(updated);
    await _tryCloud(
      'taken dose status sync',
      () => FirebaseBackendService().updateDoseStatus(
        patientId: patientId,
        dose: updated,
      ),
    );
    await _db.logAdherenceEvent(
      patientId: patientId,
      medicationId: updated.medicationId,
      eventType: 'taken',
      source: source,
      details: updated.id,
    );
    final delay = confirmedAt.difference(_scheduledDateTime(updated));
    if (delay.inMinutes > 0) {
      await _tryCloud(
        'delayed dose analytics',
        () => FirebaseBackendService().analytics.logAdherenceEvent(
          patientId: patientId,
          medicationId: updated.medicationId,
          eventType: 'delayedDose',
          source: source,
          details: {
            'doseId': updated.id,
            'scheduledTime': updated.scheduledTime,
            'delayMinutes': delay.inMinutes,
          },
        ),
      );
    }
    if (allTakenOnDate(DateTime.now())) {
      _showDailyCelebration = true;
      await _tryCloud(
        'daily completion analytics',
        () => FirebaseBackendService().analytics.logAdherenceEvent(
          patientId: patientId,
          eventType: 'dailyCompletion',
          source: 'app',
          details: {'date': DateTime.now().toIso8601String()},
        ),
      );
      notifyListeners();
    }
  }

  // ── FR5 + FR8: Confirm missed, return caregiver IDs to alert ─────────────
  Future<List<String>> confirmDoseMissed(
    String doseId,
    String patientId, {
    required List<Caregiver> caregivers,
    required bool caregiverAlertsEnabled,
  }) async {
    final alertableCaregivers = _alertableCaregivers(caregivers);
    _allDoses = _allDoses.map((d) {
      if (d.id != doseId) return d;
      return d.copyWith(
        status: DoseStatus.missed,
        confirmedAt: DateTime.now(),
        caregiverNotified:
            caregiverAlertsEnabled && alertableCaregivers.isNotEmpty,
      );
    }).toList();
    notifyListeners();
    final updated = _allDoses.firstWhere((d) => d.id == doseId);
    await _db.updateDose(patientId, updated);
    await NotificationService().cancelDoseEscalation(updated);
    await EscalationService().cancelDoseAutoMiss(updated);
    await _tryCloud(
      'missed dose status sync',
      () => FirebaseBackendService().updateDoseStatus(
        patientId: patientId,
        dose: updated,
      ),
    );
    await _db.logAdherenceEvent(
      patientId: patientId,
      medicationId: updated.medicationId,
      eventType: 'missed',
      source: 'patient',
      details: updated.id,
    );
    await _tryCloud(
      'manual missed dose analytics',
      () => FirebaseBackendService().analytics.logAdherenceEvent(
        patientId: patientId,
        medicationId: updated.medicationId,
        eventType: 'manualMissedDose',
        source: 'patient',
        details: {
          'doseId': updated.id,
          'scheduledTime': updated.scheduledTime,
          'caregiverNotified': updated.caregiverNotified,
        },
      ),
    );

    if (!caregiverAlertsEnabled) return [];
    return alertableCaregivers.map((c) => c.id).toList();
  }

  Future<List<DoseConfirmation>> markOverdueDosesMissed(
    String patientId, {
    required List<Caregiver> caregivers,
    required bool caregiverAlertsEnabled,
  }) async {
    final now = DateTime.now();
    final alertableCaregivers = _alertableCaregivers(caregivers);
    final notifyCaregivers =
        caregiverAlertsEnabled && alertableCaregivers.isNotEmpty;
    final missedDoses = <DoseConfirmation>[];

    _allDoses = _allDoses.map((dose) {
      if (!dose.isPending || !_isOverdue(dose, now)) return dose;
      final updated = dose.copyWith(
        status: DoseStatus.missed,
        confirmedAt: now,
        caregiverNotified: notifyCaregivers,
      );
      missedDoses.add(updated);
      return updated;
    }).toList();

    for (final dose in missedDoses) {
      await _db.updateDose(patientId, dose);
      await NotificationService().cancelDoseEscalation(dose);
      await EscalationService().cancelDoseAutoMiss(dose);
      await _tryCloud(
        'auto missed dose status sync',
        () => FirebaseBackendService().updateDoseStatus(
          patientId: patientId,
          dose: dose,
        ),
      );
      await _tryCloud(
        'auto missed dose analytics',
        () => FirebaseBackendService().analytics.logAdherenceEvent(
          patientId: patientId,
          medicationId: dose.medicationId,
          eventType: 'autoMissedDose',
          source: 'appScheduler',
          details: {
            'doseId': dose.id,
            'scheduledTime': dose.scheduledTime,
            'autoMissDelayMinutes': EscalationService.autoMissDelay.inMinutes,
            'caregiverNotified': dose.caregiverNotified,
          },
        ),
      );
    }
    if (missedDoses.isNotEmpty) notifyListeners();
    return missedDoses;
  }

  List<String> caregiverIdsForMissedDoseAlerts(List<Caregiver> caregivers) =>
      _alertableCaregivers(caregivers).map((c) => c.id).toList();

  List<Caregiver> _alertableCaregivers(List<Caregiver> caregivers) => caregivers
      .where((c) =>
          c.permission == NotificationPermission.missedDoseOnly ||
          c.permission == NotificationPermission.all)
      .toList();

  bool _isOverdue(DoseConfirmation dose, DateTime now) => now
      .isAfter(_scheduledDateTime(dose).add(EscalationService.autoMissDelay));

  Future<void> _mirrorPendingDoses({
    required String patientId,
    required String patientName,
    required List<Caregiver> caregivers,
    required bool caregiverAlertsEnabled,
    required bool isArabic,
  }) async {
    for (final dose in _allDoses.where((dose) => dose.isPending)) {
      await _tryCloud(
        'pending dose mirror',
        () => FirebaseBackendService().upsertDose(
          patientId: patientId,
          patientName: patientName,
          dose: dose,
          caregivers: caregivers,
          caregiverAlertsEnabled: caregiverAlertsEnabled,
          isArabic: isArabic,
        ),
      );
    }
  }

  Future<void> _schedulePendingEscalations({required bool isArabic}) async {
    for (final dose in _allDoses.where((dose) => dose.isPending)) {
      await NotificationService().scheduleDoseEscalation(
        dose,
        isArabic: isArabic,
      );
      await EscalationService().scheduleDoseAutoMiss(dose);
    }
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

  Future<void> _tryCloud(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('$label skipped: $e');
    }
  }

  (int current, int longest) _streaks() {
    if (_allDoses.isEmpty) return (0, 0);
    final dates = _allDoses
        .map((dose) => DateTime(
              dose.scheduledDate.year,
              dose.scheduledDate.month,
              dose.scheduledDate.day,
            ))
        .toSet()
        .toList()
      ..sort();

    var longest = 0;
    var run = 0;
    DateTime? previous;
    for (final date in dates) {
      if (!allTakenOnDate(date)) {
        run = 0;
        previous = date;
        continue;
      }
      if (previous == null || date.difference(previous).inDays == 1) {
        run += 1;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
      previous = date;
    }

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    var current = 0;
    var cursor = todayOnly;
    while (true) {
      final doses = dosesForDate(cursor);
      if (doses.isEmpty || !doses.every((dose) => dose.isTaken)) break;
      current += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return (current, longest);
  }
}
