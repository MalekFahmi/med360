import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import '../theme/app_theme.dart';
import 'shared_widgets.dart';

class SharedReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback onOpen;
  final VoidCallback onReview;
  final VoidCallback onArchive;

  const SharedReportCard({
    super.key,
    required this.report,
    required this.onOpen,
    required this.onReview,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final data = (report['report'] as Map?) ?? const {};
    final adherence = (((data['adherenceRate'] as num?) ?? 0) * 100).round();
    final patientName = '${report['patientName'] ?? strings.patient}';
    final reviewed = report['reviewed'] == true || report['reviewedAt'] != null;
    final type = '${report['reportType'] ?? data['reportType'] ?? 'monthly'}';

    return AppCard(
      onTap: onOpen,
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.tealLight,
            child: Icon(Icons.summarize_outlined, color: AppColors.teal),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patientName, style: AppTextStyles.medName),
                const SizedBox(height: 4),
                Text(
                  type == 'uploaded'
                      ? '${data['fileName'] ?? data['label'] ?? strings.uploadedFile}'
                      : strings.adherencePercent(adherence),
                  style: AppTextStyles.medDetail,
                ),
              ],
            ),
          ),
          AppBadge(
            label: reviewed ? strings.reviewed : strings.newItem,
            variant: reviewed ? BadgeVariant.teal : BadgeVariant.amber,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'review') onReview();
              if (value == 'archive') onArchive();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'review',
                child: Text(strings.reviewed),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Text(strings.archive),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
