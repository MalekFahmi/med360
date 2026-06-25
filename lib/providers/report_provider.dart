import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/firebase_backend_domains.dart';
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

  Future<bool> shareCurrentReport({
    required String patientId,
    required String patientName,
    required String recipientRole,
    required String recipientId,
    String reportType = 'monthly',
  }) async {
    final report = _reportPayload(reportType);
    if (report == null) return false;
    try {
      await FirebaseBackendService().reports.share(
            patientId: patientId,
            patientName: patientName,
            recipientRole: recipientRole,
            recipientId: recipientId,
            reportType: reportType,
            report: report,
          );
      return true;
    } catch (e) {
      debugPrint('Report sharing failed: $e');
      return false;
    }
  }

  Uint8List? exportCurrentMonthPdfBytes({
    required String patientName,
    String reportType = 'monthly',
  }) {
    final report = _reportPayload(reportType);
    if (report == null) return null;
    final medications = (report['medications'] as List<dynamic>? ?? const []);

    return _buildReportPdf(
      report: report,
      medications: medications,
      patientName: patientName,
      reportType: reportType,
    );
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
              'Week ${_formatDate(_weekStart(now))} - ${_formatDate(_weekStart(now).add(const Duration(days: 6)))}',
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
      'start': DateTime(report.year, report.month).toIso8601String(),
      'end': DateTime(report.year, report.month + 1, 0, 23, 59, 59)
          .toIso8601String(),
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
                ..._medicationDetails(record.medicationId),
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
        final medication =
            matchingMedication.isEmpty ? null : matchingMedication.first;
        final taken = medicationDoses.where((dose) => dose.isTaken).length;
        final missed = medicationDoses.where((dose) => dose.isMissed).length;
        final resolved = taken + missed;
        return {
          ..._medicationDetails(medicationId, medication: medication),
          'medicationId': medicationId,
          'medicationName': medicationName,
          'totalDoses': medicationDoses.length,
          'takenDoses': taken,
          'missedDoses': missed,
          'pendingDoses':
              medicationDoses.where((dose) => dose.isPending).length,
          'adherenceRate': resolved == 0 ? 0.0 : taken / resolved,
          'scheduledTimes':
              medicationDoses.map((dose) => dose.scheduledTime).toSet().toList()
                ..sort(),
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

  Map<String, dynamic> _medicationDetails(
    String medicationId, {
    Medication? medication,
  }) {
    if (medication == null) {
      for (final candidate in _medications) {
        if (candidate.id == medicationId) {
          medication = candidate;
          break;
        }
      }
    }
    if (medication == null) return const {};
    return {
      'dosage': medication.dosage,
      'form': medication.form.name,
      'reminderTimes':
          medication.reminderTimes.map((time) => time.display).toList(),
      'dosesPerDay': medication.dosesPerDay,
      'quantityRemaining': medication.quantityRemaining,
      if ((medication.notes ?? '').trim().isNotEmpty)
        'notes': medication.notes!.trim(),
      if ((medication.notesAr ?? '').trim().isNotEmpty)
        'notesAr': medication.notesAr!.trim(),
    };
  }

  DateTime _weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _titleCase(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  List<MonthlyAdherenceSummary> get pastReports {
    final now = DateTime.now();
    return _reports
        .where((r) => !(r.year == now.year && r.month == now.month))
        .toList();
  }

  Uint8List _buildReportPdf({
    required Map<String, dynamic> report,
    required List<dynamic> medications,
    required String patientName,
    required String reportType,
  }) {
    final adherence = (((report['adherenceRate'] ?? 0.0) as num) * 100).round();
    final medRows = medications.whereType<Map>().toList();
    final pages = <String>[];
    var index = 0;

    final firstPage = _newReportPage()
      ..writeln(_pdfRect(0, 700, 612, 92, '0.000 0.478 0.620'))
      ..writeln(
          _pdfText('MED360', 42, 754, size: 22, color: '1 1 1', bold: true))
      ..writeln(_pdfText('${_titleCase(reportType)} adherence report', 42, 728,
          size: 16, color: '1 1 1'))
      ..writeln(_pdfText('Patient: $patientName', 42, 672,
          size: 13, color: '0.110 0.145 0.180', bold: true))
      ..writeln(_pdfText('Period: ${report['label']}', 42, 652,
          size: 11, color: '0.330 0.380 0.420'));

    _pdfMetricCard(
        firstPage, 42, 560, 'Adherence', '$adherence%', '0.000 0.478 0.620');
    _pdfMetricCard(
      firstPage,
      202,
      560,
      'Taken',
      '${report['takenDoses']}',
      '0.070 0.560 0.350',
    );
    _pdfMetricCard(
      firstPage,
      362,
      560,
      'Missed',
      '${report['missedDoses']}',
      '0.820 0.220 0.250',
    );

    firstPage.writeln(_pdfText('Medication details', 42, 520,
        size: 15, color: '0.110 0.145 0.180', bold: true));
    index = _appendMedicationRows(firstPage, medRows, index, startY: 482);
    _pdfFooter(firstPage, pageNumber: 1);
    pages.add(firstPage.toString());

    var pageNumber = 2;
    while (index < medRows.length) {
      final page = _newReportPage()
        ..writeln(_pdfText('Medication details continued', 42, 744,
            size: 15, color: '0.110 0.145 0.180', bold: true))
        ..writeln(_pdfText('Patient: $patientName', 42, 724,
            size: 10, color: '0.330 0.380 0.420'));
      index = _appendMedicationRows(page, medRows, index, startY: 680);
      _pdfFooter(page, pageNumber: pageNumber);
      pages.add(page.toString());
      pageNumber += 1;
    }

    return _assemblePdf(pages);
  }

  StringBuffer _newReportPage() =>
      StringBuffer()..writeln(_pdfRect(0, 0, 612, 792, '0.965 0.977 0.980'));

  int _appendMedicationRows(
    StringBuffer content,
    List<Map<dynamic, dynamic>> medications,
    int startIndex, {
    required double startY,
  }) {
    var y = startY;
    var index = startIndex;
    while (index < medications.length && y >= 110) {
      _pdfMedicationRow(content, medications[index], y);
      y -= 82;
      index += 1;
    }
    return index;
  }

  void _pdfMedicationRow(
    StringBuffer content,
    Map<dynamic, dynamic> item,
    double y,
  ) {
    final name = '${item['medicationName'] ?? 'Medication'}';
    final medAdherence =
        (((item['adherenceRate'] ?? 0.0) as num) * 100).round();
    final times = _pdfTimes(item);
    final dosage = '${item['dosage'] ?? ''}'.trim();
    final daily = item['dosesPerDay'] as num?;
    content
      ..writeln(_pdfRect(42, y - 54, 528, 68, '1 1 1'))
      ..writeln(_pdfStrokeRect(42, y - 54, 528, 68, '0.850 0.890 0.900'))
      ..writeln(_pdfText(name, 58, y,
          size: 12, color: '0.110 0.145 0.180', bold: true))
      ..writeln(_pdfText('$medAdherence%', 516, y,
          size: 12, color: '0.000 0.478 0.620', bold: true))
      ..writeln(_pdfText(
        'Taken ${item['takenDoses']}   Missed ${item['missedDoses']}   Pending ${item['pendingDoses']}',
        58,
        y - 19,
        size: 9,
        color: '0.330 0.380 0.420',
      ));
    final detailParts = <String>[
      if (dosage.isNotEmpty) 'Dose $dosage',
      if (daily != null) '${daily.toStringAsFixed(1)} daily',
      if (times.isNotEmpty) 'Times ${times.join(', ')}',
    ];
    if (detailParts.isNotEmpty) {
      content.writeln(_pdfText(
        detailParts.join('  |  '),
        58,
        y - 36,
        size: 8,
        color: '0.330 0.380 0.420',
      ));
    }
  }

  void _pdfFooter(StringBuffer content, {required int pageNumber}) {
    content.writeln(_pdfText(
      'Generated by MED360  |  Page $pageNumber',
      42,
      44,
      size: 9,
      color: '0.500 0.540 0.580',
    ));
  }

  Uint8List _assemblePdf(List<String> pageContents) {
    final pageCount = pageContents.length;
    const pageStartId = 3;
    final contentStartId = pageStartId + pageCount;
    final regularFontId = contentStartId + pageCount;
    final boldFontId = regularFontId + 1;
    final kids = List.generate(
      pageCount,
      (index) => '${pageStartId + index} 0 R',
    ).join(' ');
    final objects = <String>[
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
      '2 0 obj\n<< /Type /Pages /Kids [$kids] /Count $pageCount >>\nendobj\n',
    ];
    for (var i = 0; i < pageCount; i++) {
      objects.add('${pageStartId + i} 0 obj\n'
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Resources << /Font << /F1 $regularFontId 0 R /F2 $boldFontId 0 R >> >> '
          '/Contents ${contentStartId + i} 0 R >>\n'
          'endobj\n');
    }
    for (var i = 0; i < pageCount; i++) {
      final contentText = pageContents[i];
      objects.add('${contentStartId + i} 0 obj\n'
          '<< /Length ${latin1.encode(contentText).length} >>\n'
          'stream\n$contentText'
          'endstream\nendobj\n');
    }
    objects
      ..add(
        '$regularFontId 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
      )
      ..add(
        '$boldFontId 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>\nendobj\n',
      );

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

  void _pdfMetricCard(
    StringBuffer content,
    double x,
    double y,
    String label,
    String value,
    String color,
  ) {
    content
      ..writeln(_pdfRect(x, y, 132, 64, '1 1 1'))
      ..writeln(_pdfStrokeRect(x, y, 132, 64, '0.850 0.890 0.900'))
      ..writeln(
          _pdfText(label, x + 14, y + 39, size: 9, color: '0.330 0.380 0.420'))
      ..writeln(
          _pdfText(value, x + 14, y + 16, size: 20, color: color, bold: true));
  }

  List<String> _pdfTimes(Map<dynamic, dynamic> item) {
    final reminders = item['reminderTimes'] is List
        ? (item['reminderTimes'] as List).whereType<String>().toList()
        : const <String>[];
    final scheduled = item['scheduledTimes'] is List
        ? (item['scheduledTimes'] as List).whereType<String>().toList()
        : const <String>[];
    return reminders.isNotEmpty ? reminders : scheduled;
  }

  String _pdfRect(double x, double y, double w, double h, String color) =>
      'q $color rg ${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} '
      '${w.toStringAsFixed(1)} ${h.toStringAsFixed(1)} re f Q';

  String _pdfStrokeRect(double x, double y, double w, double h, String color) =>
      'q $color RG 1 w ${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} '
      '${w.toStringAsFixed(1)} ${h.toStringAsFixed(1)} re S Q';

  String _pdfText(
    String text,
    double x,
    double y, {
    double size = 11,
    String color = '0 0 0',
    bool bold = false,
  }) =>
      'q $color rg BT /${bold ? 'F2' : 'F1'} ${size.toStringAsFixed(1)} Tf '
      '${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} Td '
      '(${_escapePdfText(_pdfSafeText(text))}) Tj ET Q';

  String _pdfSafeText(String text) =>
      text.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

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
