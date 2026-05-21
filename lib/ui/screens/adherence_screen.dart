// lib/ui/screens/adherence_screen.dart
// FR6 — Adherence Tracking (Calculated metrics)
// FR7 — Adherence Reporting (Monthly summaries)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class AdherenceScreen extends StatelessWidget {
  const AdherenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAr = auth.arabicMode;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.grayLight,
        title: Text(
          isAr ? 'التقارير والالتزام' : 'Adherence Reports',
          style: AppTextStyles.screenTitle,
        ),
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            // Current Month Overview (FR6)
            SectionLabel(isAr ? 'مايو 2026' : 'May 2026 Overview'),
            Row(
              children:[
                Expanded(
                  child: MetricTile(
                    label: isAr ? 'نسبة الالتزام' : 'Adherence',
                    value: '87%',
                    valueColor: AppColors.teal,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: MetricTile(
                    label: isAr ? 'تم أخذها' : 'Doses Taken',
                    value: '34',
                    valueColor: AppColors.grayDark,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: MetricTile(
                    label: isAr ? 'فائتة' : 'Missed',
                    value: '5',
                    valueColor: AppColors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Historical Reporting (FR7)
            SectionLabel(isAr ? 'تقارير الأشهر السابقة' : 'Past Months'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children:[
                  _buildMonthRow('April 2026', 'أبريل 2026', 0.92, isAr),
                  const Divider(height: 1, color: AppColors.grayLight),
                  _buildMonthRow('March 2026', 'مارس 2026', 0.78, isAr),
                  const Divider(height: 1, color: AppColors.grayLight),
                  _buildMonthRow('February 2026', 'فبراير 2026', 0.85, isAr),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthRow(String monthEn, String monthAr, double rate, bool isAr) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children:[
          Expanded(
            flex: 2,
            child: Text(isAr ? monthAr : monthEn, style: AppTextStyles.medName),
          ),
          Expanded(
            flex: 3,
            child: AdherenceBar(rate: rate),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            '${(rate * 100).toInt()}%',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}