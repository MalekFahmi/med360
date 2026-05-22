import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../theme/app_theme.dart';
import '../../providers/providers.dart';

class AdherenceScreen extends StatelessWidget {
  const AdherenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reportProv = context.watch<ReportProvider>();
    final isAr = auth.arabicMode;

    final current = reportProv.currentMonthReport;
    final past = reportProv.pastReports;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.grayLight,
        title: Text(isAr ? 'التقارير والالتزام' : 'Adherence Reports',
            style: AppTextStyles.screenTitle),
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current != null) ...[
              SectionLabel(isAr ? current.monthLabelAr : current.monthLabel),
              Row(
                children: [
                  Expanded(
                      child: MetricTile(
                          label: isAr ? 'نسبة الالتزام' : 'Adherence',
                          value: current.overallPercentage,
                          valueColor: AppColors.teal)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                      child: MetricTile(
                          label: isAr ? 'تم أخذها' : 'Doses Taken',
                          value: '${current.takenDoses}',
                          valueColor: AppColors.grayDark)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                      child: MetricTile(
                          label: isAr ? 'فائتة' : 'Missed',
                          value: '${current.missedDoses}',
                          valueColor: AppColors.red)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            SectionLabel(isAr ? 'تقارير الأشهر السابقة' : 'Past Months'),
            if (past.isEmpty)
              Text(isAr
                  ? 'لا توجد بيانات سابقة.'
                  : 'No past data available yet.')
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: past
                      .map((r) => Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Row(
                                  children: [
                                    Expanded(
                                        flex: 2,
                                        child: Text(
                                            isAr
                                                ? r.monthLabelAr
                                                : r.monthLabel,
                                            style: AppTextStyles.medName)),
                                    Expanded(
                                        flex: 3,
                                        child: AdherenceBar(
                                            rate: r.overallAdherenceRate)),
                                    const SizedBox(width: AppSpacing.md),
                                    Text(r.overallPercentage,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                              const Divider(
                                  height: 1, color: AppColors.grayLight),
                            ],
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
