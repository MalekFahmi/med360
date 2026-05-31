import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/caregiver_provider.dart';
import 'shared_patient_medications_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class CaregiverDashboardScreen extends StatelessWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final caregiver = auth.caregiver;
    final provider = context.watch<CaregiverProvider>();
    final urgentAlerts = provider.notifications
        .where((notification) =>
            notification.type == 'missedDose' && !notification.acknowledged)
        .toList();
    final recentAlerts = provider.notifications.take(8).toList();
    final sharedReports = provider.sharedReports
        .where((report) => report['archived'] != true)
        .take(5)
        .toList();

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
      body: RefreshIndicator(
        onRefresh: () async {
          final uid = context.read<AuthProvider>().caregiver?.uid;
          if (uid != null) {
            context.read<CaregiverProvider>().listenToCaregiverData(uid);
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _CaregiverHeader(
              name: caregiver?.name ?? 'Caregiver',
              email: caregiver?.email ?? '',
              unreadCount: provider.unreadCount,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Patients',
                    value: '${provider.linkedPatients.length}',
                    valueColor: AppColors.blue,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: MetricTile(
                    label: 'Unread',
                    value: '${provider.unreadCount}',
                    valueColor: provider.unreadCount > 0
                        ? AppColors.red
                        : AppColors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              title: 'Needs attention',
              action: provider.unreadCount == 0
                  ? null
                  : TextButton.icon(
                      onPressed: () =>
                          context.read<CaregiverProvider>().markAllAsRead(),
                      icon: const Icon(Icons.done_all_rounded, size: 16),
                      label: const Text('Mark all read'),
                    ),
            ),
            if (urgentAlerts.isEmpty)
              const _QuietPanel()
            else
              ...urgentAlerts.map((alert) => _AlertTile(
                    notification: alert,
                    prominent: true,
                    onMarkRead: () => provider.markAsRead(alert.id),
                  )),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              title: 'Linked Patients',
              action: TextButton.icon(
                onPressed: () => _openPatientAction(context),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: const Text('Add'),
              ),
            ),
            if (provider.linkedPatients.isEmpty)
              const EmptyState(
                icon: Icons.people_outline_rounded,
                title: 'No linked patients',
                subtitle:
                    'Patients can link you using your registered email address or phone number.',
              )
            else
              ...provider.linkedPatients.map(
                (patient) => _PatientTile(patient: patient),
              ),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              title: 'Shared reports',
              trailing: AppBadge(
                label: '${sharedReports.length}',
                variant: sharedReports.isEmpty
                    ? BadgeVariant.gray
                    : BadgeVariant.blue,
              ),
            ),
            if (sharedReports.isEmpty)
              const EmptyState(
                icon: Icons.summarize_outlined,
                title: 'No shared reports',
                subtitle: 'Patient reports shared with you will appear here.',
              )
            else
              ...sharedReports.map((report) => _ReportTile(
                    report: report,
                    onReview: () => provider.markReportReviewed(report['id']),
                    onArchive: () => provider.archiveReport(report['id']),
                  )),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              title: 'Recent inbox',
              trailing: AppBadge(
                label: '${provider.unreadCount} unread',
                variant: provider.unreadCount > 0
                    ? BadgeVariant.amber
                    : BadgeVariant.gray,
              ),
            ),
            if (recentAlerts.isEmpty)
              const EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'No notifications',
                subtitle: 'Missed-dose alerts will appear here.',
              )
            else
              ...recentAlerts.map((notification) => _AlertTile(
                    notification: notification,
                    onMarkRead: notification.acknowledged
                        ? null
                        : () => provider.markAsRead(notification.id),
                  )),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

Future<void> _openPatientAction(BuildContext context) async {
  final action = await showModalBottomSheet<_PatientAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const _PatientActionSheet(),
  );
  if (action == null || !context.mounted) return;
  final provider = context.read<CaregiverProvider>();
  final ok = action.createNew
      ? await provider.createManagedPatient(
          name: action.name,
          phone: action.phone,
          chronicCondition: action.chronicCondition,
        )
      : await provider.linkExistingPatientByPhone(action.phone);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(ok ? 'Patient added' : 'Could not add patient'),
    backgroundColor: ok ? AppColors.teal : AppColors.red,
    behavior: SnackBarBehavior.floating,
  ));
}

class _ReportTile extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback onReview;
  final VoidCallback onArchive;

  const _ReportTile({
    required this.report,
    required this.onReview,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final data = (report['report'] as Map?) ?? const {};
    final adherence = ((data['adherenceRate'] as num?) ?? 0) * 100;
    final reviewed = report['reviewedAt'] != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.blueLight,
              foregroundColor: AppColors.blue,
              child: Icon(Icons.summarize_outlined),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report['patientName'] ?? 'Patient',
                      style: AppTextStyles.medName),
                  const SizedBox(height: 4),
                  Text(
                    '${report['reportType'] ?? 'monthly'} report - ${adherence.round()}% adherence',
                    style: AppTextStyles.medDetail,
                  ),
                  const SizedBox(height: 8),
                  AppBadge(
                    label: reviewed ? 'Reviewed' : 'New',
                    variant: reviewed ? BadgeVariant.green : BadgeVariant.amber,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'review') onReview();
                if (value == 'archive') onArchive();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'review', child: Text('Mark reviewed')),
                PopupMenuItem(value: 'archive', child: Text('Archive')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CaregiverHeader extends StatelessWidget {
  final String name;
  final String email;
  final int unreadCount;

  const _CaregiverHeader({
    required this.name,
    required this.email,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.tealLight,
              borderRadius: AppRadius.md,
            ),
            child: const Icon(
              Icons.health_and_safety_outlined,
              color: AppColors.tealDark,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.medName),
                const SizedBox(height: 2),
                Text(email, style: AppTextStyles.medDetail),
              ],
            ),
          ),
          AppBadge(
            label: unreadCount > 0 ? 'Active' : 'Clear',
            variant: unreadCount > 0 ? BadgeVariant.red : BadgeVariant.green,
            icon: unreadCount > 0
                ? Icons.notification_important_outlined
                : Icons.check_circle_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    this.action,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Text(title.toUpperCase(), style: AppTextStyles.sectionLabel),
          const Spacer(),
          if (action != null) action!,
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _QuietPanel extends StatelessWidget {
  const _QuietPanel();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.greenLight,
              borderRadius: AppRadius.md,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.green,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No missed-dose alerts', style: AppTextStyles.medName),
                SizedBox(height: 2),
                Text('Your linked patients are clear right now.',
                    style: AppTextStyles.medDetail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  final Map<String, dynamic> patient;

  const _PatientTile({required this.patient});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SharedPatientMedicationsScreen(
              patient: patient,
              actorRole: 'caregiver',
            ),
          ),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.blueLight,
              foregroundColor: AppColors.blue,
              child: Icon(Icons.person_outline_rounded),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patient['name'] ?? 'Patient',
                      style: AppTextStyles.medName),
                  const SizedBox(height: 2),
                  Text(patient['phone'] ?? '', style: AppTextStyles.medDetail),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      AppBadge(
                        label:
                            '${(((patient['adherenceRate'] as num?) ?? 0) * 100).round()}% adherence',
                        variant: BadgeVariant.teal,
                      ),
                      if (((patient['missedCount'] as num?) ?? 0) > 0)
                        AppBadge(
                          label: '${patient['missedCount']} missed',
                          variant: BadgeVariant.amber,
                        ),
                      if (((patient['refillRisk'] as num?) ?? 0) > 0)
                        AppBadge(
                          label: '${patient['refillRisk']} refill risks',
                          variant: BadgeVariant.red,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.grayMid),
          ],
        ),
      ),
    );
  }
}

class _PatientAction {
  final bool createNew;
  final String name;
  final String phone;
  final String? chronicCondition;

  const _PatientAction({
    required this.createNew,
    required this.name,
    required this.phone,
    this.chronicCondition,
  });
}

class _PatientActionSheet extends StatefulWidget {
  const _PatientActionSheet();

  @override
  State<_PatientActionSheet> createState() => _PatientActionSheetState();
}

class _PatientActionSheetState extends State<_PatientActionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _conditionCtrl = TextEditingController();
  bool _createNew = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _conditionCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _PatientAction(
        createNew: _createNew,
        name: _nameCtrl.text.trim().isEmpty ? 'Patient' : _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        chronicCondition: _conditionCtrl.text.trim().isEmpty
            ? null
            : _conditionCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add patient',
              style: AppTextStyles.screenTitle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Create'),
                  icon: Icon(Icons.person_add_alt_1_rounded),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Link'),
                  icon: Icon(Icons.link_rounded),
                ),
              ],
              selected: {_createNew},
              onSelectionChanged: (value) =>
                  setState(() => _createNew = value.first),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_createNew) ...[
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Patient name',
                  border: OutlineInputBorder(borderRadius: AppRadius.md),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter patient name'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText:
                    _createNew ? 'Patient phone' : 'Existing patient phone',
                border: const OutlineInputBorder(borderRadius: AppRadius.md),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter patient phone'
                  : null,
            ),
            if (_createNew) ...[
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _conditionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Chronic condition (optional)',
                  border: OutlineInputBorder(borderRadius: AppRadius.md),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check_rounded),
                label: Text(_createNew ? 'Create patient' : 'Link patient'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final CaregiverNotification notification;
  final bool prominent;
  final VoidCallback? onMarkRead;

  const _AlertTile({
    required this.notification,
    this.prominent = false,
    this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final isMissedDose = notification.type == 'missedDose';
    final title = isMissedDose ? 'Missed medication' : 'Caregiver linked';
    final body = notification.medicationName == null
        ? notification.caregiverName
        : '${notification.caregiverName} missed ${notification.medicationName}';
    final color = notification.acknowledged
        ? AppColors.grayMid
        : prominent
            ? AppColors.red
            : AppColors.amber;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.md,
              ),
              child: Icon(
                notification.acknowledged
                    ? Icons.mark_email_read_outlined
                    : Icons.notification_important_outlined,
                color: color,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: AppTextStyles.medName),
                      ),
                      AppBadge(
                        label: notification.acknowledged ? 'Read' : 'New',
                        variant: notification.acknowledged
                            ? BadgeVariant.gray
                            : BadgeVariant.red,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: AppTextStyles.medDetail),
                  const SizedBox(height: 6),
                  Text(_relativeTime(notification.sentAt),
                      style: AppTextStyles.medDetail),
                ],
              ),
            ),
            if (onMarkRead != null) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Mark as read',
                icon: const Icon(Icons.done_rounded),
                onPressed: onMarkRead,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} d ago';
  }
}
