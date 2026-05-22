import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';

class CaregiverScreen extends StatelessWidget {
  const CaregiverScreen({super.key});

  Future<void> _addCaregiver(BuildContext context) async {
    final caregiver = await showModalBottomSheet<Caregiver>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CaregiverFormSheet(isArabic: context.read<AuthProvider>().arabicMode),
    );
    if (caregiver == null || !context.mounted) return;
    await context.read<AuthProvider>().addCaregiver(caregiver);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAr = auth.arabicMode;
    final caregivers = auth.caregivers;

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
          children: [
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SectionLabel(isAr ? 'الأشخاص المصرح لهم' : 'Authorized Caregivers'),
                TextButton.icon(
                  onPressed: () => _addCaregiver(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(isAr ? 'إضافة' : 'Add'),
                ),
              ],
            ),
            if (caregivers.isEmpty)
              EmptyState(
                icon: Icons.people_outline_rounded,
                title: isAr ? 'لا يوجد مقدمو رعاية' : 'No caregivers yet',
                subtitle: isAr
                    ? 'يمكنك إضافة شخص ليصله تنبيه عند تفويت جرعة'
                    : 'Add someone who can be notified when a dose is missed',
              )
            else
              ...caregivers.map(
                (caregiver) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _CaregiverCard(caregiver: caregiver, isAr: isAr),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CaregiverCard extends StatelessWidget {
  final Caregiver caregiver;
  final bool isAr;
  const _CaregiverCard({required this.caregiver, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final permissionLabel = switch (caregiver.permission) {
      NotificationPermission.all => isAr ? 'تقارير وتنبيهات' : 'Full Access',
      NotificationPermission.missedDoseOnly => isAr ? 'تنبيهات فقط' : 'Alerts Only',
      NotificationPermission.none => isAr ? 'متوقف' : 'Muted',
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
                  '${caregiver.relationship} • ${caregiver.phone}',
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
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'missed',
                child: Text(isAr ? 'تنبيهات فقط' : 'Alerts only'),
              ),
              PopupMenuItem(
                value: 'all',
                child: Text(isAr ? 'تقارير وتنبيهات' : 'Full access'),
              ),
              PopupMenuItem(
                value: 'none',
                child: Text(isAr ? 'إيقاف التنبيهات' : 'Mute'),
              ),
              PopupMenuItem(
                value: 'remove',
                child: Text(isAr ? 'حذف' : 'Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CaregiverFormSheet extends StatefulWidget {
  final bool isArabic;
  const _CaregiverFormSheet({required this.isArabic});

  @override
  State<_CaregiverFormSheet> createState() => _CaregiverFormSheetState();
}

class _CaregiverFormSheetState extends State<_CaregiverFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _relationCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final auth = context.read<AuthProvider>();
    final error = await auth.addCaregiverByEmail(
      _emailCtrl.text.trim(),
      _relationCtrl.text.trim(),
    );

    if (mounted) {
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        setState(() => _isSubmitting = false);
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isArabic;
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
                isAr ? 'إضافة مقدم رعاية مسجل' : 'Add Registered Caregiver',
                style: AppTextStyles.screenTitle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: isAr ? 'البريد الإلكتروني' : 'Caregiver Email',
                  hintText: 'email@example.com',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? (isAr ? 'أدخل البريد الإلكتروني' : 'Enter email')
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _relationCtrl,
                decoration: InputDecoration(labelText: isAr ? 'صلة القرابة' : 'Relationship'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? (isAr ? 'أدخل صلة القرابة' : 'Enter a relationship')
                    : null,
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _save,
                  icon: _isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.link_rounded),
                  label: Text(isAr ? 'ربط مقدم الرعاية' : 'Link Caregiver'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
