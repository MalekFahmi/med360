import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final patient = auth.patient;
    final isAr = auth.arabicMode;

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(title: Text(isAr ? 'الإعدادات' : 'Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.teal,
                  child: Icon(
                    Icons.person_rounded,
                    color: AppColors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient?.name ?? (isAr ? 'المريض' : 'Patient'),
                        style: AppTextStyles.screenTitle.copyWith(fontSize: 23),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isAr
                            ? 'رقم الهاتف: ${patient?.phone ?? '-'}'
                            : 'Phone: ${patient?.phone ?? '-'}',
                        style: AppTextStyles.medDetail,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Row(
              children: [
                const Icon(
                  Icons.language_rounded,
                  color: AppColors.teal,
                  size: 30,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? 'اللغة' : 'Language',
                        style: AppTextStyles.medName,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAr ? 'العربية' : 'English',
                        style: AppTextStyles.medDetail,
                      ),
                    ],
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('عربي')),
                    ButtonSegment(value: false, label: Text('English')),
                  ],
                  selected: {isAr},
                  onSelectionChanged: (_) => auth.toggleArabicMode(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout_rounded),
            label: Text(isAr ? 'تسجيل الخروج' : 'Log out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
  }
}
