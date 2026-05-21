// FR5 — Dose Confirmation (patient taps "Taken" or "Missed")
// FR6 — Adherence Tracking (every confirmation is stored and computed)
// FR8 — Caregiver Notification trigger lives here: after a missed confirmation,
//        this provider flags which caregivers need to be alerted.
//
// This is the most interactive provider in the app — every tap on the
// dashboard's "Take now" / "Missed" buttons calls into this provider,
// and every screen that shows adherence data (calendar, charts, dashboard
// metrics) listens to it.

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/med_repository.dart';

class AdherenceProvider extends ChangeNotifier {
  final MedRepository _repo;

  AdherenceProvider(this._repo);

  // ─── State ────────────────────────────────────────────────────────────────
  LoadStatus _status = LoadStatus.initial;
  List<DoseConfirmation> _allDoses = [];
  String? _errorMessage;

  // ─── Getters ──────────────────────────────────────────────────────────────
  LoadStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == LoadStatus.loading;

  /// Full dose history — used by the calendar and weekly bar chart
  List<DoseConfirmation> get allDoses => _allDoses;

  /// Today's doses — the dashboard medication list
  List<DoseConfirmation> get todaysDoses {
    final today = DateTime.now();
    return _allDoses
        .where((d) => d.isOnDate(today))
        .toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  }

  /// Pending doses for today — drives the "X doses due" badge
  List<DoseConfirmation> get pendingTodayDoses =>
      todaysDoses.where((d) => d.isPending).toList();

  int get pendingCount => pendingTodayDoses.length;

  /// Doses for a specific calendar date — used by the adherence calendar
  List<DoseConfirmation> dosesForDate(DateTime date) =>
      _allDoses.where((d) => d.isOnDate(date)).toList();

  /// True if ALL doses on a given date were taken (calendar green cell)
  bool allTakenOnDate(DateTime date) {
    final doses = dosesForDate(date);
    if (doses.isEmpty) return false;
    return doses.every((d) => d.isTaken);
  }

  /// True if ANY dose on a given date was missed (calendar red cell)
  bool anyMissedOnDate(DateTime date) =>
      dosesForDate(date).any((d) => d.isMissed);

  // ─── Monthly adherence stats (FR6) ────────────────────────────────────────

  /// Overall adherence rate for a given month (0.0 – 1.0)
  double monthlyAdherenceRate(int year, int month) {
    final doses = _allDoses.where((d) =>
        d.scheduledDate.year == year && d.scheduledDate.month == month);
    final taken = doses.where((d) => d.isTaken).length;
    final missed = doses.where((d) => d.isMissed).length;
    final resolved = taken + missed;
    if (resolved == 0) return 0.0;
    return taken / resolved;
  }

  /// Adherence % string, e.g. "87%"
  String monthlyAdherencePercentage(int year, int month) =>
      '${(monthlyAdherenceRate(year, month) * 100).round()}%';

  /// Per-week adherence rates for the current month — used by bar chart.
  /// Returns a list of up to 5 maps: { 'label': 'W1', 'rate': 0.93 }
  List<Map<String, dynamic>> weeklyBreakdown(int year, int month) {
    final weeks = <Map<String, dynamic>>[];
    int weekNum = 1;
    int day = 1;

    while (day <= 31) {
      final start = DateTime(year, month, day);
      if (start.month != month) break;

      final end = DateTime(year, month, day + 6);
      final weekDoses = _allDoses.where((d) =>
          d.scheduledDate.isAfter(start.subtract(const Duration(days: 1))) &&
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

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> loadHistory() async {
    if (_status == LoadStatus.loading) return;
    _status = LoadStatus.loading;
    notifyListeners();

    try {
      _allDoses = await _repo.getDoseHistory();
      _status = LoadStatus.loaded;
    } catch (e) {
      _errorMessage = 'Could not load dose history.';
      _status = LoadStatus.error;
    }

    notifyListeners();
  }

  /// FR5 — Patient confirms a dose was TAKEN.
  /// Updates the local dose record immediately (optimistic update) so the
  /// UI responds instantly without waiting for a server round-trip.
  void confirmDoseTaken(String doseId) {
    _allDoses = _allDoses.map((d) {
      if (d.id != doseId) return d;
      return d.copyWith(
        status: DoseStatus.taken,
        confirmedAt: DateTime.now(),
        caregiverNotified: false,
      );
    }).toList();
    notifyListeners();
    // TODO: persist to local DB (Step 3) and sync to API (Step 6)
  }

  /// FR5 + FR8 — Patient confirms a dose was MISSED.
  /// Returns the list of caregiver IDs that should be notified so the
  /// CaregiverProvider (or future NotificationService) can dispatch alerts.
  List<String> confirmDoseMissed(
    String doseId, {
    required List<Caregiver> caregivers,
    required bool caregiverAlertsEnabled,
  }) {
    _allDoses = _allDoses.map((d) {
      if (d.id != doseId) return d;
      return d.copyWith(
        status: DoseStatus.missed,
        confirmedAt: DateTime.now(),
        caregiverNotified: caregiverAlertsEnabled && caregivers.isNotEmpty,
      );
    }).toList();
    notifyListeners();

    // Return IDs of caregivers who should receive an alert (FR8)
    if (!caregiverAlertsEnabled) return [];
    return caregivers
        .where((c) =>
            c.permission == NotificationPermission.missedDoseOnly ||
            c.permission == NotificationPermission.all)
        .map((c) => c.id)
        .toList();
  }
}

// Re-export LoadStatus so screens can import from one place
enum LoadStatus { initial, loading, loaded, error }