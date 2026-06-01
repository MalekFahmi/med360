import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/firebase_backend_service.dart';
import '../services/local_db_service.dart';
import 'adherence_provider.dart' show LoadStatus;

class ReportProvider extends ChangeNotifier {
  ReportProvider(LocalDbService db);

  final LoadStatus _status = LoadStatus.initial;
  List<MonthlyAdherenceSummary> _reports = [];
  List<DoseConfirmation> _allDoses = [];
  List<Medication> _medications = [];

  LoadStatus get status => _status;
  bool get isLoading => _status == LoadStatus.loading;
  List<MonthlyAdherenceSummary> get reports => _reports;

  // Build monthly summaries from the dose history already in memory
  void buildReports({
    required List<DoseConfirmation> allDoses,
    required List<Medication> medications,
  }) {
    _allDoses = allDoses;
    _medications = medications;
    if (allDoses.isEmpty) {
      _reports = [];
      notifyListeners();
      return;
    }

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
        final matchingMedication =
            medications.where((medication) => medication.id == id);
        final medName = matchingMedication.isEmpty
            ? medDoses.first.medicationName
            : matchingMedication.first.displayName;
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

  Future<void> shareCurrentReport({
    required String patientId,
    required String patientName,
    required String recipientRole,
    required String recipientId,
    String reportType = 'monthly',
  }) async {
    final report = _reportPayload(reportType);
    if (report == null) return;
    await FirebaseBackendService().shareReport(
      patientId: patientId,
      patientName: patientName,
      recipientRole: recipientRole,
      recipientId: recipientId,
      reportType: reportType,
      report: report,
    );
  }

  Uint8List? exportCurrentMonthPdfBytes({
    required String patientName,
    String reportType = 'monthly',
  }) {
    final report = _reportPayload(reportType);
    if (report == null) return null;
    final medications = (report['medications'] as List<dynamic>? ?? const []);

    final lines = <String>[
      'Med360 Adherence Report',
      'Patient: $patientName',
      'Type: ${_titleCase(reportType)}',
      'Period: ${report['label']}',
      'Overall adherence: ${((report['adherenceRate'] ?? 0.0) * 100).round()}%',
      'Taken doses: ${report['takenDoses']}',
      'Missed doses: ${report['missedDoses']}',
      'Pending doses: ${report['pendingDoses']}',
      '',
      'Medication breakdown',
      for (final item in medications)
        '${item['medicationName']}: ${(((item['adherenceRate'] ?? 0.0) as num) * 100).round()}% '
            '(${item['takenDoses']} taken, ${item['missedDoses']} missed, '
            '${item['pendingDoses']} pending)',
    ];

    return _buildSimplePdf(lines);
  }

  Map<String, dynamic>? _reportPayload(String reportType) {
    final now = DateTime.now();
    return switch (reportType) {
      'daily' => _rangeReport(
          reportType: 'daily',
          label:
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        ),
      'weekly' => _rangeReport(
          reportType: 'weekly',
          label:
              'Week of ${_weekStart(now).month}/${_weekStart(now).day}/${_weekStart(now).year}',
          start: _weekStart(now),
          end: _weekStart(now).add(
              const Duration(days: 6, hours: 23, minutes: 59, seconds: 59)),
        ),
      _ => _monthlyReportPayload(),
    };
  }

  Map<String, dynamic>? _monthlyReportPayload() {
    final report = currentMonthReport;
    if (report == null) return null;
    return {
      'year': report.year,
      'month': report.month,
      'label': report.monthLabel,
      'takenDoses': report.takenDoses,
      'missedDoses': report.missedDoses,
      'pendingDoses': report.perMedication.fold<int>(
        0,
        (sum, record) => sum + record.pendingDoses,
      ),
      'adherenceRate': report.overallAdherenceRate,
      'medications': report.perMedication
          .map((record) => {
                'medicationId': record.medicationId,
                'medicationName': record.medicationName,
                'totalDoses': record.totalDoses,
                'takenDoses': record.takenDoses,
                'missedDoses': record.missedDoses,
                'pendingDoses': record.pendingDoses,
                'adherenceRate': record.adherenceRate,
              })
          .toList(),
    };
  }

  Map<String, dynamic>? _rangeReport({
    required String reportType,
    required String label,
    required DateTime start,
    required DateTime end,
  }) {
    final doses = _allDoses
        .where((dose) =>
            !dose.scheduledDate.isBefore(start) &&
            !dose.scheduledDate.isAfter(end))
        .toList();
    if (doses.isEmpty) return null;

    final medicationRows = doses.map((dose) => dose.medicationId).toSet().map(
      (medicationId) {
        final medicationDoses =
            doses.where((dose) => dose.medicationId == medicationId).toList();
        final matchingMedication =
            _medications.where((medication) => medication.id == medicationId);
        final medicationName = matchingMedication.isEmpty
            ? medicationDoses.first.medicationName
            : matchingMedication.first.displayName;
        final taken = medicationDoses.where((dose) => dose.isTaken).length;
        final missed = medicationDoses.where((dose) => dose.isMissed).length;
        final resolved = taken + missed;
        return {
          'medicationId': medicationId,
          'medicationName': medicationName,
          'totalDoses': medicationDoses.length,
          'takenDoses': taken,
          'missedDoses': missed,
          'pendingDoses':
              medicationDoses.where((dose) => dose.isPending).length,
          'adherenceRate': resolved == 0 ? 0.0 : taken / resolved,
        };
      },
    ).toList();
    final taken = medicationRows.fold<int>(
      0,
      (sum, row) => sum + ((row['takenDoses'] as num?)?.toInt() ?? 0),
    );
    final missed = medicationRows.fold<int>(
      0,
      (sum, row) => sum + ((row['missedDoses'] as num?)?.toInt() ?? 0),
    );
    final pending = medicationRows.fold<int>(
      0,
      (sum, row) => sum + ((row['pendingDoses'] as num?)?.toInt() ?? 0),
    );
    final resolved = taken + missed;
    return {
      'reportType': reportType,
      'label': label,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'takenDoses': taken,
      'missedDoses': missed,
      'pendingDoses': pending,
      'adherenceRate': resolved == 0 ? 0.0 : taken / resolved,
      'medications': medicationRows,
    };
  }

  DateTime _weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  String _titleCase(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  List<MonthlyAdherenceSummary> get pastReports {
    final now = DateTime.now();
    return _reports
        .where((r) => !(r.year == now.year && r.month == now.month))
        .toList();
  }

  Uint8List _buildSimplePdf(List<String> lines) {
    final content = StringBuffer()
      ..writeln('BT')
      ..writeln('/F1 18 Tf')
      ..writeln('72 740 Td');

    for (var i = 0; i < lines.length; i++) {
      final size = i == 0 ? 18 : 11;
      if (i > 0) content.writeln('0 -18 Td');
      content
        ..writeln('/F1 $size Tf')
        ..writeln('(${_escapePdfText(lines[i])}) Tj');
    }
    content.writeln('ET');

    final contentText = content.toString();
    final objects = <String>[
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
      '3 0 obj\n'
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\n'
          'endobj\n',
      '4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\n'
          'endobj\n',
      '5 0 obj\n<< /Length ${latin1.encode(contentText).length} >>\n'
          'stream\n$contentText'
          'endstream\nendobj\n',
    ];

    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    var byteOffset = latin1.encode(buffer.toString()).length;
    for (final object in objects) {
      offsets.add(byteOffset);
      buffer.write(object);
      byteOffset += latin1.encode(object).length;
    }

    final xrefOffset = byteOffset;
    buffer
      ..writeln('xref')
      ..writeln('0 ${objects.length + 1}')
      ..writeln('0000000000 65535 f ');
    for (final offset in offsets.skip(1)) {
      buffer.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
    }
    buffer
      ..writeln('trailer')
      ..writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>')
      ..writeln('startxref')
      ..writeln('$xrefOffset')
      ..writeln('%%EOF');

    return Uint8List.fromList(latin1.encode(buffer.toString()));
  }

  String _escapePdfText(String text) {
    final latinText = String.fromCharCodes(
      text.runes.map((rune) => rune <= 255 ? rune : 63),
    );
    return latinText
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }
}
