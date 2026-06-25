import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../i18n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class SharedReportDetailScreen extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback? onReview;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;

  const SharedReportDetailScreen({
    super.key,
    required this.report,
    this.onReview,
    this.onArchive,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final payload = (report['report'] as Map?) ?? const {};
    final strings = AppStrings.of(context);
    final patientName = '${report['patientName'] ?? strings.patient}';
    final type =
        '${report['reportType'] ?? payload['reportType'] ?? 'monthly'}';
    final isUploaded = type == 'uploaded' || payload['downloadUrl'] != null;
    final label = '${payload['label'] ?? strings.report}';
    final isArabic = context.watch<AuthProvider>().arabicMode;
    final archived = report['archived'] == true;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.pageTint,
        appBar: AppBar(title: Text(strings.reportTitle(patientName))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.typeLabel(type),
                    style: AppTextStyles.screenTitle.copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 6),
                  Text(patientName, style: AppTextStyles.medName),
                  const SizedBox(height: 4),
                  Text(label, style: AppTextStyles.medDetail),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (isUploaded)
              _UploadedReportCard(payload: payload)
            else
              _StructuredReport(payload: payload),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(strings.reviewed),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: archived ? onRestore : onArchive,
                    icon: Icon(
                      archived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                    ),
                    label: Text(
                      archived
                          ? strings.pick('استعادة', 'Restore')
                          : strings.archive,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StructuredReport extends StatelessWidget {
  final Map<dynamic, dynamic> payload;

  const _StructuredReport({required this.payload});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final adherence = (((payload['adherenceRate'] as num?) ?? 0) * 100).round();
    final taken = ((payload['takenDoses'] as num?) ?? 0).toInt();
    final missed = ((payload['missedDoses'] as num?) ?? 0).toInt();
    final pending = ((payload['pendingDoses'] as num?) ?? 0).toInt();
    final medications = payload['medications'] is List
        ? payload['medications'] as List
        : const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.adherenceSummary,
                  style: AppTextStyles.screenTitle.copyWith(fontSize: 22)),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: strings.adherence,
                      value: '$adherence%',
                      valueColor: AppColors.teal,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: MetricTile(
                      label: strings.taken,
                      value: '$taken',
                      valueColor: AppColors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: strings.missed,
                      value: '$missed',
                      valueColor: AppColors.red,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: MetricTile(
                      label: strings.pending,
                      value: '$pending',
                      valueColor: AppColors.amber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AdherenceBar(rate: adherence / 100, height: 14),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(strings.medicationDetails,
            style: AppTextStyles.screenTitle.copyWith(fontSize: 22)),
        const SizedBox(height: AppSpacing.md),
        if (medications.isEmpty)
          EmptyState(
            icon: Icons.medication_outlined,
            title: strings.noMedicationDetails,
          )
        else
          ...medications.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _MedicationReportCard(
                item: item is Map ? item : const {},
              ),
            ),
          ),
      ],
    );
  }
}

class _MedicationReportCard extends StatelessWidget {
  final Map<dynamic, dynamic> item;

  const _MedicationReportCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final name = '${item['medicationName'] ?? strings.medications}';
    final adherence = (((item['adherenceRate'] as num?) ?? 0) * 100).round();
    final taken = ((item['takenDoses'] as num?) ?? 0).toInt();
    final missed = ((item['missedDoses'] as num?) ?? 0).toInt();
    final pending = ((item['pendingDoses'] as num?) ?? 0).toInt();
    final times = _times();
    final dosage = '${item['dosage'] ?? ''}'.trim();
    final dailyDoses = item['dosesPerDay'] as num?;
    final notes = _notes(context);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medication_rounded, color: AppColors.teal),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(name, style: AppTextStyles.medName)),
              AppBadge(
                label: '$adherence%',
                variant: adherence >= 80
                    ? BadgeVariant.green
                    : adherence >= 50
                        ? BadgeVariant.amber
                        : BadgeVariant.red,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AdherenceBar(rate: adherence / 100, height: 10),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ReportMiniStat(
                  label: strings.taken,
                  value: '$taken',
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ReportMiniStat(
                  label: strings.missed,
                  value: '$missed',
                  color: AppColors.red,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ReportMiniStat(
                  label: strings.pending,
                  value: '$pending',
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          if (dosage.isNotEmpty || dailyDoses != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (dosage.isNotEmpty)
                  AppBadge(
                    label: strings.pick('الجرعة $dosage', 'Dose $dosage'),
                    variant: BadgeVariant.blue,
                    icon: Icons.medication_liquid_rounded,
                  ),
                if (dailyDoses != null)
                  AppBadge(
                    label: strings.pick(
                      '${dailyDoses.toStringAsFixed(1)} يومياً',
                      '${dailyDoses.toStringAsFixed(1)} daily',
                    ),
                    variant: BadgeVariant.teal,
                    icon: Icons.today_rounded,
                  ),
              ],
            ),
          ],
          if (times.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              strings.pick('أوقات الدواء', 'Medication times'),
              style: AppTextStyles.medDetail.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.grayDark,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final time in times)
                  AppBadge(
                    label: time,
                    variant: BadgeVariant.gray,
                    icon: Icons.schedule_rounded,
                  ),
              ],
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.skyLight,
                borderRadius: AppRadius.md,
              ),
              child: Text(
                strings.pick('ملاحظات: $notes', 'Notes: $notes'),
                style: AppTextStyles.medDetail.copyWith(
                  color: AppColors.navy,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _times() {
    final reminders = item['reminderTimes'] is List
        ? (item['reminderTimes'] as List).whereType<String>().toList()
        : const <String>[];
    final scheduled = item['scheduledTimes'] is List
        ? (item['scheduledTimes'] as List).whereType<String>().toList()
        : const <String>[];
    return reminders.isNotEmpty ? reminders : scheduled;
  }

  String _notes(BuildContext context) {
    final strings = AppStrings.of(context);
    return strings.isArabic
        ? '${item['notesAr'] ?? item['notes'] ?? ''}'.trim()
        : '${item['notes'] ?? item['notesAr'] ?? ''}'.trim();
  }
}

class _ReportMiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ReportMiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.metricLabel),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.metricValue.copyWith(
              color: color,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadedReportCard extends StatelessWidget {
  final Map<dynamic, dynamic> payload;

  const _UploadedReportCard({required this.payload});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final fileName =
        '${payload['fileName'] ?? payload['label'] ?? strings.uploadedFile}';
    final size = ((payload['sizeBytes'] as num?) ?? 0).toInt();

    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.attach_file_rounded, color: AppColors.sky, size: 34),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fileName, style: AppTextStyles.medName),
                const SizedBox(height: 4),
                Text(
                  size == 0
                      ? strings.uploadedFile
                      : '${(size / 1024).round()} KB',
                  style: AppTextStyles.medDetail,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
