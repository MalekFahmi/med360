import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import '../screens/shared_patient_medications_screen.dart';
import '../theme/app_theme.dart';
import 'shared_widgets.dart';

class SharedPatientCard extends StatelessWidget {
  final Map<String, dynamic> patient;
  final String actorRole;

  const SharedPatientCard({
    super.key,
    required this.patient,
    required this.actorRole,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final name = '${patient['name'] ?? strings.patient}';
    final phone = '${patient['phone'] ?? ''}';

    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SharedPatientMedicationsScreen(
            patient: patient,
            actorRole: actorRole,
          ),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.skyLight,
            child: Icon(Icons.person_rounded, color: AppColors.sky, size: 30),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.medName),
                const SizedBox(height: 6),
                Text(
                  phone.isEmpty ? strings.noPhone : phone,
                  style: AppTextStyles.medDetail,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded, color: AppColors.grayMid),
        ],
      ),
    );
  }
}
