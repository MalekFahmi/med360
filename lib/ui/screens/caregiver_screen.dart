import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class CaregiverScreen extends StatelessWidget {
  const CaregiverScreen({super.key});

  Future<void> _addCaregiver(BuildContext context) async {
    final request = await showModalBottomSheet<_CaregiverLinkRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CaregiverFormSheet(),
    );
    if (request == null || !context.mounted) return;

    final ok = await context.read<AuthProvider>().addCaregiverByEmail(
          email: request.email,
          relationship: request.relationship,
          permission: request.permission,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'تم ربط حساب المرافق'
            : context.read<AuthProvider>().errorMessage ??
                'لم يتم العثور على مرافق بهذا البريد'),
        backgroundColor: ok ? AppColors.teal : AppColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final caregivers = auth.caregivers;

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(title: const Text('فريق الرعاية')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            child: ToggleRow(
              title: 'تنبيهات المرافقين',
              subtitle: 'إرسال تنبيه للمرافق عند تفويت جرعة',
              value: auth.caregiverAlertsEnabled,
              onChanged: (_) => auth.toggleCaregiverAlerts(),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Text(
                'المرافقون',
                style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _addCaregiver(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('ربط'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (caregivers.isEmpty)
            const EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'لا يوجد مرافقون',
              subtitle: 'اربط حساب مرافق لمتابعة التنبيهات',
            )
          else
            ...caregivers.map(
              (caregiver) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _CaregiverCard(caregiver: caregiver),
              ),
            ),
        ],
      ),
    );
  }
}

class _CaregiverCard extends StatelessWidget {
  final Caregiver caregiver;

  const _CaregiverCard({required this.caregiver});

  @override
  Widget build(BuildContext context) {
    final permissionLabel = switch (caregiver.permission) {
      NotificationPermission.all => 'وصول كامل',
      NotificationPermission.missedDoseOnly => 'تنبيهات فقط',
      NotificationPermission.none => 'بدون تنبيهات',
    };
    final variant = switch (caregiver.permission) {
      NotificationPermission.all => BadgeVariant.blue,
      NotificationPermission.missedDoseOnly => BadgeVariant.amber,
      NotificationPermission.none => BadgeVariant.gray,
    };

    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.tealLight,
            foregroundColor: AppColors.tealDark,
            child: Text(caregiver.initials),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caregiver.name, style: AppTextStyles.medName),
                const SizedBox(height: 4),
                Text(
                  caregiver.email ?? caregiver.phone,
                  style: AppTextStyles.medDetail,
                ),
                const SizedBox(height: 8),
                AppBadge(label: permissionLabel, variant: variant),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              final auth = context.read<AuthProvider>();
              if (value == 'missed') {
                await auth.updateCaregiverPermission(
                  caregiver.id,
                  NotificationPermission.missedDoseOnly,
                );
              } else if (value == 'all') {
                await auth.updateCaregiverPermission(
                  caregiver.id,
                  NotificationPermission.all,
                );
              } else if (value == 'none') {
                await auth.updateCaregiverPermission(
                  caregiver.id,
                  NotificationPermission.none,
                );
              } else if (value == 'remove') {
                await auth.removeCaregiver(caregiver.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'missed', child: Text('تنبيهات فقط')),
              PopupMenuItem(value: 'all', child: Text('وصول كامل')),
              PopupMenuItem(value: 'none', child: Text('بدون تنبيهات')),
              PopupMenuItem(value: 'remove', child: Text('إزالة')),
            ],
          ),
        ],
      ),
    );
  }
}

class _CaregiverFormSheet extends StatefulWidget {
  const _CaregiverFormSheet();

  @override
  State<_CaregiverFormSheet> createState() => _CaregiverFormSheetState();
}

class _CaregiverFormSheetState extends State<_CaregiverFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();
  NotificationPermission _permission = NotificationPermission.missedDoseOnly;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _relationCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _CaregiverLinkRequest(
        email: _emailCtrl.text.trim().toLowerCase(),
        relationship: _relationCtrl.text.trim(),
        permission: _permission,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ربط مرافق',
                style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'بريد المرافق',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'أدخل بريد المرافق';
                  }
                  if (!value.contains('@')) return 'أدخل بريد صحيح';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _relationCtrl,
                decoration: const InputDecoration(
                  labelText: 'صلة القرابة',
                  prefixIcon: Icon(Icons.people_outline_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل صلة القرابة'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<NotificationPermission>(
                value: _permission,
                decoration: const InputDecoration(labelText: 'الصلاحية'),
                items: const [
                  DropdownMenuItem(
                    value: NotificationPermission.missedDoseOnly,
                    child: Text('تنبيهات فقط'),
                  ),
                  DropdownMenuItem(
                    value: NotificationPermission.all,
                    child: Text('وصول كامل'),
                  ),
                  DropdownMenuItem(
                    value: NotificationPermission.none,
                    child: Text('بدون تنبيهات'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _permission = value);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.link_rounded),
                label: const Text('ربط المرافق'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaregiverLinkRequest {
  final String email;
  final String relationship;
  final NotificationPermission permission;

  const _CaregiverLinkRequest({
    required this.email,
    required this.relationship,
    required this.permission,
  });
}
