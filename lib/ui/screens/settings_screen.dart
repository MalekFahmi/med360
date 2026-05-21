// lib/ui/screens/settings_screen.dart
// FR1 — Patient Account Provisioning (Profile Info)
// NFR — Accessibility (Arabic, Fonts, Contrast, Biometrics)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAr = auth.arabicMode;
    final patient = auth.patient;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.grayLight,
        title: Text(
          isAr ? 'الإعدادات' : 'Settings',
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
            // FR1 — Profile Summary
            AppCard(
              child: Row(
                children:[
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.teal,
                    child: Icon(Icons.person_rounded, color: AppColors.white, size: 32),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        Text(
                          isAr ? (patient?.nameAr ?? 'أحمد حسن') : (patient?.name ?? 'Ahmed Hassan'),
                          style: AppTextStyles.screenTitle.copyWith(fontSize: 18),
                        ),
                        Text(
                          isAr ? 'رقم الملف: ${patient?.id}' : 'Patient ID: ${patient?.id}',
                          style: AppTextStyles.medDetail,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // NFR — Accessibility Settings
            SectionLabel(isAr ? 'إمكانية الوصول' : 'Accessibility & Preferences'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Column(
                children:[
                  ToggleRow(
                    title: isAr ? 'اللغة العربية' : 'Arabic Language',
                    value: auth.arabicMode,
                    onChanged: (_) => auth.toggleArabicMode(),
                  ),
                  const Divider(height: 1, color: AppColors.grayLight),
                  ToggleRow(
                    title: isAr ? 'خطوط كبيرة' : 'Large Fonts',
                    value: auth.largeFonts,
                    onChanged: (_) => auth.toggleLargeFonts(),
                  ),
                  const Divider(height: 1, color: AppColors.grayLight),
                  ToggleRow(
                    title: isAr ? 'تباين عالي' : 'High Contrast Mode',
                    value: auth.highContrast,
                    onChanged: (_) => auth.toggleHighContrast(),
                  ),
                  const Divider(height: 1, color: AppColors.grayLight),
                  ToggleRow(
                    title: isAr ? 'تسجيل الدخول بالبصمة' : 'Biometric Login',
                    value: auth.biometricEnabled,
                    onChanged: (_) => auth.toggleBiometric(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // FR2 Logout
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => auth.logout(),
                icon: const Icon(Icons.logout_rounded, color: AppColors.red),
                label: Text(
                  isAr ? 'تسجيل الخروج' : 'Log out',
                  style: const TextStyle(color: AppColors.red),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.redLight),
                  shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}