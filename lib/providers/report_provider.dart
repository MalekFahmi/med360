import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/local_db_service.dart';
import 'adherence_provider.dart' show LoadStatus;

class ReportProvider extends ChangeNotifier {
  ReportProvider(LocalDbService db);

  final LoadStatus _status = LoadStatus.initial;
  List<MonthlyAdherenceSummary> _reports = [];

  LoadStatus get status => _status;
  bool get isLoading => _status == LoadStatus.loading;
  List<MonthlyAdherenceSummary> get reports => _reports;

  // Build monthly summaries from the dose history already in memory
  void buildReports({
    required List<DoseConfirmation> allDoses,
    required List<Medication> medications,
  }) {
    if (allDoses.isEmpty) return;

    final Map<String, MonthlyAdherenceSummary> byMonth = {};

    // Find unique year/month combos in history
    final months = allDoses
        .map((d) => '${d.scheduledDate.year}-${d.scheduledDate.month}')
        .toSet();

    for (final key in months) {
      final parts = key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);

      final monthDoses = allDoses
          .where((d) =>
              d.scheduledDate.year == year && d.scheduledDate.month == month)
          .toList();

      final medIds = monthDoses.map((d) => d.medicationId).toSet();
      final records = medIds.map((id) {
        final medDoses = monthDoses.where((d) => d.medicationId == id).toList();
        final medName = medications
            .firstWhere(
              (m) => m.id == id,
              orElse: () => medications.first,
            )
            .displayName;
        return AdherenceRecord(
          medicationId: id,
          medicationName: medName,
          year: year,
          month: month,
          totalDoses: medDoses.length,
          takenDoses: medDoses.where((d) => d.isTaken).length,
          missedDoses: medDoses.where((d) => d.isMissed).length,
          pendingDoses: medDoses.where((d) => d.isPending).length,
        );
      }).toList();

      byMonth[key] = MonthlyAdherenceSummary(
          year: year, month: month, perMedication: records);
    }

    _reports = byMonth.values.toList()
      ..sort((a, b) {
        final aDate = DateTime(a.year, a.month);
        final bDate = DateTime(b.year, b.month);
        return bDate.compareTo(aDate); // newest first
      });

    notifyListeners();
  }

  MonthlyAdherenceSummary? get currentMonthReport {
    final now = DateTime.now();
    try {
      return _reports
          .firstWhere((r) => r.year == now.year && r.month == now.month);
    } catch (_) {
      return null;
    }
  }

  List<MonthlyAdherenceSummary> get pastReports {
    final now = DateTime.now();
    return _reports
        .where((r) => !(r.year == now.year && r.month == now.month))
        .toList();
  }
}
