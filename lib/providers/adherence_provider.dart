import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/local_db_service.dart';
import '../services/dose_generator.dart';
import 'medication_provider.dart' show LoadStatus;

export 'medication_provider.dart' show LoadStatus;

class AdherenceProvider extends ChangeNotifier {
  static const missedGracePeriod = Duration(minutes: 5);

  final LocalDbService _db;
  AdherenceProvider(this._db);

  LoadStatus _status = LoadStatus.initial;
  List<DoseConfirmation> _allDoses = [];
  String? _errorMessage;

  LoadStatus get status => _status;
  bool get isLoading => _status == LoadStatus.loading;
  String? get errorMessage => _errorMessage;
  List<DoseConfirmation> get allDoses => _allDoses;

  List<DoseConfirmation> get todaysDoses {
    final today = DateTime.now();
    return _allDoses.where((d) => d.isOnDate(today)).toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  }

  int get pendingCount => todaysDoses.where((d) => d.isPending).length;

  List<DoseConfirmation> dosesForDate(DateTime date) =>
      _allDoses.where((d) => d.isOnDate(date)).toList();

  bool allTakenOnDate(DateTime date) {
    final doses = dosesForDate(date);
    return doses.isNotEmpty && doses.every((d) => d.isTaken);
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
      _status = LoadStatus.loaded;
    } catch (e) {
      _errorMessage = 'Could not load dose history.';
      _status = LoadStatus.error;
    }
    notifyListeners();
  }

  // ── FR5: Confirm taken ────────────────────────────────────────────────────
  Future<void> confirmDoseTaken(String doseId, String patientId) async {
    _allDoses = _allDoses.map((d) {
      if (d.id != doseId) return d;
      return d.copyWith(status: DoseStatus.taken, confirmedAt: DateTime.now());
    }).toList();
    notifyListeners();
    final updated = _allDoses.firstWhere((d) => d.id == doseId);
    await _db.updateDose(patientId, updated);
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

  bool _isOverdue(DoseConfirmation dose, DateTime now) =>
      now.isAfter(_scheduledDateTime(dose).add(missedGracePeriod));

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
