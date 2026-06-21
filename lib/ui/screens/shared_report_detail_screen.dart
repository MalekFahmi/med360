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

  const SharedReportDetailScreen({
    super.key,
    required this.report,
    this.onReview,
    this.onArchive,
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
                    onPressed: onArchive,
                    icon: const Icon(Icons.archive_outlined),
                    label: Text(strings.archive),
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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medication_rounded, color: AppColors.teal),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(name, style: AppTextStyles.medName)),
              Text('$adherence%',
                  style: AppTextStyles.screenTitle.copyWith(
                    color: AppColors.teal,
                    fontSize: 22,
                  )),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AdherenceBar(rate: adherence / 100, height: 10),
          const SizedBox(height: AppSpacing.sm),
          Text(
            strings.medicationReportStats(
              taken: taken,
              missed: missed,
              pending: pending,
            ),
            style: AppTextStyles.medDetail,
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
