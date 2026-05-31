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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Caregiver account linked'
          : context.read<AuthProvider>().errorMessage ??
              'No caregiver account was found for that email'),
      backgroundColor: ok ? AppColors.teal : AppColors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _addDoctor(BuildContext context) async {
    final email = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _DoctorLinkSheet(),
    );
    if (email == null || !context.mounted) return;

    final ok = await context.read<AuthProvider>().addDoctorByEmail(email);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Doctor account linked'
          : context.read<AuthProvider>().errorMessage ??
              'No doctor account was found for that email'),
      backgroundColor: ok ? AppColors.teal : AppColors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final caregivers = auth.caregivers;
    final doctors = auth.linkedDoctors;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.grayLight,
        title: const Text('Care Team', style: AppTextStyles.screenTitle),
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: ToggleRow(
                title: 'Caregiver Alerts',
                subtitle:
                    'Notify linked caregiver accounts if a dose is missed',
                value: auth.caregiverAlertsEnabled,
                onChanged: (_) => auth.toggleCaregiverAlerts(),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionLabel('Linked Caregiver Accounts'),
                TextButton.icon(
                  onPressed: () => _addCaregiver(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Link'),
                ),
              ],
            ),
            if (caregivers.isEmpty)
              const EmptyState(
                icon: Icons.people_outline_rounded,
                title: 'No linked caregiver accounts',
                subtitle:
                    'Ask the caregiver to sign up first, then link them with their registered email address',
              )
            else
              ...caregivers.map(
                (caregiver) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _CaregiverCard(caregiver: caregiver),
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionLabel('Assigned Doctors'),
                TextButton.icon(
                  onPressed: () => _addDoctor(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Link'),
                ),
              ],
            ),
            if (doctors.isEmpty)
              const EmptyState(
                icon: Icons.local_hospital_outlined,
                title: 'No assigned doctors',
                subtitle:
                    'Ask the doctor to sign up first, then link them with their registered email address',
              )
            else
              ...doctors.map(
                (doctor) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _DoctorCard(doctor: doctor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  final DoctorUser doctor;
  const _DoctorCard({required this.doctor});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.blueLight,
            foregroundColor: AppColors.blue,
            child: Icon(Icons.local_hospital_outlined),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doctor.name, style: AppTextStyles.medName),
                Text(doctor.specialty, style: AppTextStyles.medDetail),
                const SizedBox(height: 8),
                AppBadge(label: doctor.email, variant: BadgeVariant.blue),
              ],
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
      NotificationPermission.all => 'Full Access',
      NotificationPermission.missedDoseOnly => 'Alerts Only',
      NotificationPermission.none => 'Muted',
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
                Text(
                  '${caregiver.relationship} - ${caregiver.email ?? caregiver.phone}',
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
              PopupMenuItem(value: 'missed', child: Text('Alerts only')),
              PopupMenuItem(value: 'all', child: Text('Full access')),
              PopupMenuItem(value: 'none', child: Text('Mute')),
              PopupMenuItem(value: 'remove', child: Text('Remove')),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Link caregiver account',
                style: AppTextStyles.screenTitle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Caregiver registered email',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: AppRadius.md),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter the caregiver email';
                  }
                  if (!value.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _relationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  prefixIcon: Icon(Icons.people_outline_rounded),
                  border: OutlineInputBorder(borderRadius: AppRadius.md),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a relationship'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<NotificationPermission>(
                value: _permission,
                decoration: const InputDecoration(
                  labelText: 'Permission',
                  border: OutlineInputBorder(borderRadius: AppRadius.md),
                ),
                items: const [
                  DropdownMenuItem(
                    value: NotificationPermission.missedDoseOnly,
                    child: Text('Alerts only'),
                  ),
                  DropdownMenuItem(
                    value: NotificationPermission.all,
                    child: Text('Full access'),
                  ),
                  DropdownMenuItem(
                    value: NotificationPermission.none,
                    child: Text('Muted'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _permission = value);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Link caregiver account'),
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.teal),
                ),
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

class _DoctorLinkSheet extends StatefulWidget {
  const _DoctorLinkSheet();

  @override
  State<_DoctorLinkSheet> createState() => _DoctorLinkSheetState();
}

class _DoctorLinkSheetState extends State<_DoctorLinkSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _emailCtrl.text.trim().toLowerCase());
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
              'Link doctor account',
              style: AppTextStyles.screenTitle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Doctor registered email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(borderRadius: AppRadius.md),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter the doctor email';
                }
                if (!value.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Link doctor account'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
