import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';
import '../../services/firebase_backend_service.dart';

class CaregiverDashboardScreen extends StatefulWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  State<CaregiverDashboardScreen> createState() => _CaregiverDashboardScreenState();
}

class _CaregiverDashboardScreenState extends State<CaregiverDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initData());
  }

  void _initData() async {
    final auth = context.read<AuthProvider>();
    if (auth.isCaregiver) {
      final uid = auth.caregiverUser!['uid'];
      await FirebaseBackendService().updateCaregiverToken(uid);
      if (mounted) {
        context.read<CaregiverProvider>().listenToInboundAlerts(uid);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cgProv = context.watch<CaregiverProvider>();
    final isAr = auth.arabicMode;
    final user = auth.caregiverUser;

    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.teal,
        title: Text(
          isAr ? 'لوحة تحكم المراقب' : 'Caregiver Dashboard',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              context.read<CaregiverProvider>().clear();
              auth.logout();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAr ? 'مرحباً، ${user['name']}' : 'Welcome, ${user['name']}',
              style: AppTextStyles.screenTitle,
            ),
            const SizedBox(height: AppSpacing.lg),

            SectionLabel(isAr ? 'تنبيهات المرضى' : 'Patient Alerts'),
            if (cgProv.notifications.isEmpty)
              const EmptyState(
                icon: Icons.notifications_none,
                title: 'No alerts yet',
                subtitle: 'Notifications from your linked patients will appear here.',
              )
            else
              ...cgProv.notifications.map((n) => _NotificationTile(notification: n, isAr: isAr)),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final CaregiverNotification notification;
  final bool isAr;
  const _NotificationTile({required this.notification, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final isMissedDose = notification.type == 'missedDose';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Row(
          children: [
            Icon(
              isMissedDose ? Icons.warning_amber_rounded : Icons.person_add_alt_1_rounded,
              color: isMissedDose ? AppColors.red : AppColors.teal,
              size: 32,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMissedDose
                        ? (isAr ? 'جرعة فائتة: ${notification.medicationName}' : 'Missed Dose: ${notification.medicationName}')
                        : (isAr ? 'تمت إضافتك كمراقب' : 'Linked as Caregiver'),
                    style: AppTextStyles.medName,
                  ),
                  Text(
                    isAr ? 'المريض: ${notification.patientName}' : 'Patient: ${notification.patientName}',
                    style: AppTextStyles.medDetail,
                  ),
                  Text(
                    '${notification.sentAt.hour}:${notification.sentAt.minute.toString().padLeft(2, '0')}',
                    style: AppTextStyles.medDetail.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
