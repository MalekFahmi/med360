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
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();
  NotificationPermission _permission = NotificationPermission.missedDoseOnly;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _relationCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Caregiver(
        id: 'CG-${DateTime.now().millisecondsSinceEpoch}',
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        relationship: _relationCtrl.text.trim(),
        permission: _permission,
      ),
    );
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
                isAr ? 'إضافة مقدم رعاية' : 'Add caregiver',
                style: AppTextStyles.screenTitle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: isAr ? 'الاسم الكامل' : 'Full name'),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? (isAr ? 'أدخل الاسم' : 'Enter a name')
                        : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: isAr ? 'رقم الهاتف' : 'Phone number'),
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? (isAr ? 'أدخل رقم الهاتف' : 'Enter a phone number')
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
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<NotificationPermission>(
                initialValue: _permission,
                decoration: InputDecoration(labelText: isAr ? 'الصلاحية' : 'Permission'),
                items: [
                  DropdownMenuItem(
                    value: NotificationPermission.missedDoseOnly,
                    child: Text(isAr ? 'تنبيهات فقط' : 'Alerts only'),
                  ),
                  DropdownMenuItem(
                    value: NotificationPermission.all,
                    child: Text(isAr ? 'تقارير وتنبيهات' : 'Full access'),
                  ),
                  DropdownMenuItem(
                    value: NotificationPermission.none,
                    child: Text(isAr ? 'متوقف' : 'Muted'),
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
                  icon: const Icon(Icons.check_rounded),
                  label: Text(isAr ? 'حفظ مقدم الرعاية' : 'Save caregiver'),
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
