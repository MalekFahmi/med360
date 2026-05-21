// lib/ui/screens/medications_screen.dart
// FR3 — Medication Information Integration (List display)
// FR10 — Medication Data Synchronization (Sync status)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAr = auth.arabicMode;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.grayLight,
        title: Text(
          isAr ? 'أدويتي' : 'My Medications',
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
            // FR10 — Sync Status Banner
            InfoBanner(
              message: isAr 
                  ? 'تمت المزامنة مع نظام LIMU Care اليوم الساعة 08:00 ص' 
                  : 'Synced with LIMU Care today at 08:00 AM',
              color: AppColors.blue,
              icon: Icons.sync_rounded,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Active Medications List
            SectionLabel(isAr ? 'الأدوية الحالية' : 'Active Prescriptions'),
            
            _buildMedicationCard(
              isAr: isAr,
              medId: 'MED-001',
              nameEn: 'Metformin', nameAr: 'ميتفورمين',
              dosage: '500mg',
              freqEn: 'Twice daily', freqAr: 'مرتين يومياً',
              formEn: 'Tablet', formAr: 'قرص',
            ),
            const SizedBox(height: AppSpacing.md),
            
            _buildMedicationCard(
              isAr: isAr,
              medId: 'MED-002',
              nameEn: 'Lisinopril', nameAr: 'ليسينوبريل',
              dosage: '10mg',
              freqEn: 'Once daily', freqAr: 'مرة يومياً',
              formEn: 'Tablet', formAr: 'قرص',
            ),

            _buildMedicationCard(
              isAr: isAr,
              medId: 'MED-002',
              nameEn: 'panadol', nameAr: 'بانادول',
              dosage: '10mg',
              freqEn: 'Once daily', freqAr: 'مرة يومياً',
              formEn: 'Tablet', formAr: 'قرص',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicationCard({
    required bool isAr,
    required String medId,
    required String nameEn, required String nameAr,
    required String dosage,
    required String freqEn, required String freqAr,
    required String formEn, required String formAr,
  }) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          MedIconBubble(medicationId: medId, size: 48),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Text('${isAr ? nameAr : nameEn} $dosage', style: AppTextStyles.medName),
                const SizedBox(height: 4),
                Text(isAr ? freqAr : freqEn, style: AppTextStyles.medDetail),
                const SizedBox(height: 8),
                AppBadge(
                  label: isAr ? formAr : formEn,
                  variant: BadgeVariant.teal,
                  icon: Icons.medication_rounded,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.grayMid),
        ],
      ),
      onTap: () {
        // Navigate to details screen
      },
    );
  }
}