// lib/ui/screens/caregiver_screen.dart
// FR8 — Caregiver Notifications (Master toggle & assigned caregivers)
// FR9 — Caregiver Monitoring (Permission levels)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class CaregiverScreen extends StatelessWidget {
  const CaregiverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAr = auth.arabicMode;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.grayLight,
        title: Text(
          isAr ? 'مقدمي الرعاية' : 'Caregivers',
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
            // FR8 — Master notification switch
            AppCard(
              child: ToggleRow(
                title: isAr ? 'تنبيهات مقدم الرعاية' : 'Caregiver Alerts',
                subtitle: isAr 
                    ? 'إرسال تنبيه في حال تفويت جرعة' 
                    : 'Notify caregivers if a dose is missed',
                value: auth.caregiverAlertsEnabled,
                onChanged: (_) => auth.toggleCaregiverAlerts(),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            SectionLabel(isAr ? 'الأشخاص المصرح لهم' : 'Authorized Caregivers'),
            
            // Caregiver 1 (Full monitoring)
            _buildCaregiverCard(
              isAr: isAr,
              nameEn: 'Fatima Ahmed', nameAr: 'فاطمة أحمد',
              relationEn: 'Daughter', relationAr: 'ابنة',
              canViewReports: true,
            ),
            const SizedBox(height: AppSpacing.md),
            
            // Caregiver 2 (View only)
            _buildCaregiverCard(
              isAr: isAr,
              nameEn: 'Khalid Ahmed', nameAr: 'خالد أحمد',
              relationEn: 'Son', relationAr: 'ابن',
              canViewReports: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaregiverCard({
    required bool isAr,
    required String nameEn, required String nameAr,
    required String relationEn, required String relationAr,
    required bool canViewReports,
  }) {
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.tealLight,
            foregroundColor: AppColors.tealDark,
            child: Text(nameEn[0]),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isAr ? nameAr : nameEn, style: AppTextStyles.medName),
                Text(isAr ? relationAr : relationEn, style: AppTextStyles.medDetail),
              ],
            ),
          ),
          AppBadge(
            label: canViewReports 
                ? (isAr ? 'تقارير كاملة' : 'Full Access')
                : (isAr ? 'تنبيهات فقط' : 'Alerts Only'),
            variant: canViewReports ? BadgeVariant.blue : BadgeVariant.amber,
          ),
        ],
      ),
    );
  }
}