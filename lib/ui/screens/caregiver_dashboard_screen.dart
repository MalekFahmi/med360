import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/caregiver_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class CaregiverDashboardScreen extends StatelessWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final caregiver = auth.caregiver;
    final provider = context.watch<CaregiverProvider>();

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.grayLight,
        elevation: 0,
        title:
            const Text('Caregiver Dashboard', style: AppTextStyles.screenTitle),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthProvider>().logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.tealLight,
                  foregroundColor: AppColors.tealDark,
                  child: Icon(Icons.health_and_safety_outlined),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(caregiver?.name ?? 'Caregiver',
                          style: AppTextStyles.medName),
                      Text(caregiver?.email ?? '',
                          style: AppTextStyles.medDetail),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Linked Patients'),
          if (provider.linkedPatients.isEmpty)
            const EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No linked patients',
              subtitle:
                  'Patients can link you using your registered email address',
            )
          else
            ...provider.linkedPatients.map(
              (patient) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.blueLight,
                      foregroundColor: AppColors.blue,
                      child: Icon(Icons.person_outline_rounded),
                    ),
                    title: Text(patient['name'] ?? 'Patient'),
                    subtitle: Text(patient['phone'] ?? ''),
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel('Notification Inbox'),
              AppBadge(
                label: '${provider.unreadCount} unread',
                variant: provider.unreadCount > 0
                    ? BadgeVariant.amber
                    : BadgeVariant.gray,
              ),
            ],
          ),
          if (provider.notifications.isEmpty)
            const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications',
              subtitle: 'Missed-dose alerts will appear here',
            )
          else
            ...provider.notifications.map(
              (notification) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      notification.acknowledged
                          ? Icons.mark_email_read_outlined
                          : Icons.notification_important_outlined,
                      color: notification.acknowledged
                          ? AppColors.grayMid
                          : AppColors.amber,
                    ),
                    title: Text(
                      notification.type == 'caregiverAdded'
                          ? 'Caregiver linked'
                          : 'Missed Medication Alert',
                    ),
                    subtitle: Text(
                      notification.medicationName == null
                          ? notification.caregiverName
                          : '${notification.caregiverName} missed ${notification.medicationName}',
                    ),
                    trailing: notification.acknowledged
                        ? null
                        : IconButton(
                            tooltip: 'Mark as read',
                            icon: const Icon(Icons.done_rounded),
                            onPressed: () =>
                                provider.markAsRead(notification.id),
                          ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Alert History'),
          ...provider.notifications
              .where((notification) => notification.type == 'missedDose')
              .take(10)
              .map(
                (notification) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded),
                  title:
                      Text(notification.medicationName ?? 'Medication alert'),
                  subtitle: Text(notification.sentAt.toLocal().toString()),
                ),
              ),
        ],
      ),
    );
  }
}
