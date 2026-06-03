import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/firebase_backend_service.dart';
import '../../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

  Future<void> _openMedicationForm(
    BuildContext context, {
    Medication? med,
  }) async {
    final auth = context.read<AuthProvider>();
    final medProvider = context.read<MedicationProvider>();
    final adherence = context.read<AdherenceProvider>();
    final saved = await showModalBottomSheet<Medication>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MedicationFormSheet(initialMedication: med),
    );
    if (saved == null || auth.patient == null) return;

    try {
      if (med == null) {
        await medProvider.addMedication(
          auth.patient!.id,
          saved,
          isArabic: true,
        );
      } else {
        await NotificationService().cancelMedicationReminders(med);
        await medProvider.updateMedication(
          auth.patient!.id,
          saved,
          isArabic: true,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم الحفظ محلياً، وتعذر المزامنة حالياً'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    try {
      await NotificationService().scheduleMedicationReminders(
        saved,
        isArabic: true,
      );
      await FirebaseBackendService().logReminderEvent(
        patientId: auth.patient!.id,
        medicationId: saved.id,
        eventType: 'reminderScheduled',
        source: 'patient',
        details: {
          'reminderType': saved.reminderType.name,
          'scheduleTimes':
              saved.reminderTimes.map((time) => time.display).toList(),
        },
      );
    } catch (e) {
      debugPrint('Medication reminder scheduling skipped: $e');
    }

    await adherence.loadAndGenerate(
      patientId: auth.patient!.id,
      medications: medProvider.medications,
      patientName: auth.patient!.name,
      caregivers: auth.caregivers,
      caregiverAlertsEnabled: auth.caregiverAlertsEnabled,
      isArabic: true,
    );
  }

  Future<void> _deleteMedication(BuildContext context, Medication med) async {
    final auth = context.read<AuthProvider>();
    final medProvider = context.read<MedicationProvider>();
    final adherence = context.read<AdherenceProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الدواء؟'),
        content: Text('سيتم حذف ${med.displayNameAr} من قائمتك.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || auth.patient == null) return;

    await medProvider.deleteMedication(med.id);
    await NotificationService().cancelMedicationReminders(med);
    await adherence.loadAndGenerate(
      patientId: auth.patient!.id,
      medications: medProvider.medications,
      patientName: auth.patient!.name,
      caregivers: auth.caregivers,
      caregiverAlertsEnabled: auth.caregiverAlertsEnabled,
      isArabic: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final medProvider = context.watch<MedicationProvider>();

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.pageTint,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'أدويتي',
          style: AppTextStyles.screenTitle.copyWith(fontSize: 26),
        ),
      ),
      body: medProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : medProvider.isEmpty
              ? EmptyState(
                  icon: Icons.medication_outlined,
                  title: 'لا توجد أدوية بعد',
                  subtitle: 'اضغط زر إضافة دواء لإدخال أول دواء',
                  action: FilledButton.icon(
                    onPressed: () => _openMedicationForm(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة دواء'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                  itemCount: medProvider.medications.length,
                  itemBuilder: (context, index) {
                    final med = medProvider.medications[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _MedicationCard(
                        medication: med,
                        onTap: () => _openMedicationForm(context, med: med),
                        onEdit: () => _openMedicationForm(context, med: med),
                        onDelete: () => _deleteMedication(context, med),
                        onPauseResume: () async {
                          if (auth.patient == null) return;
                          if (med.status == MedicationStatus.paused) {
                            await medProvider.resumeMedication(
                              auth.patient!.id,
                              med.id,
                            );
                            final updated = medProvider.findById(med.id);
                            if (updated != null) {
                              await NotificationService()
                                  .scheduleMedicationReminders(
                                updated,
                                isArabic: true,
                              );
                            }
                          } else {
                            await medProvider.pauseMedication(
                              auth.patient!.id,
                              med.id,
                            );
                            await NotificationService()
                                .cancelMedicationReminders(med);
                          }
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.teal,
        foregroundColor: AppColors.white,
        onPressed: () => _openMedicationForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة دواء'),
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final Medication medication;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPauseResume;

  const _MedicationCard({
    required this.medication,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onPauseResume,
  });

  @override
  Widget build(BuildContext context) {
    final paused = medication.status == MedicationStatus.paused;
    final notes = (medication.notesAr ?? medication.notes ?? '').trim();
    final indication = medication.indicationAr.trim().isNotEmpty
        ? medication.indicationAr.trim()
        : medication.indication.trim();
    final daysLeft = medication.estimatedDaysRemaining;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MedIconBubble(medicationId: medication.id, size: 58),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medication.displayNameAr,
                      style: AppTextStyles.screenTitle.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${medication.formLabelAr} • ${medication.dosage}',
                      style: AppTextStyles.medDetail.copyWith(fontSize: 15),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'pause') onPauseResume();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                  PopupMenuItem(
                    value: 'pause',
                    child: Text(paused ? 'استئناف' : 'إيقاف مؤقت'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoLine(
            icon: Icons.today_outlined,
            text: 'الجرعات اليومية: ${_formatNumber(medication.dosesPerDay)}',
          ),
          const SizedBox(height: 8),
          _InfoLine(
            icon: Icons.schedule_rounded,
            text:
                'الأوقات: ${medication.reminderTimes.map((time) => time.display).join('، ')}',
          ),
          if (indication.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.info_outline_rounded,
              text: 'الاستخدام: $indication',
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.notes_rounded,
              text: 'ملاحظات: $notes',
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppBadge(
                label: paused ? 'متوقف مؤقتاً' : 'نشط',
                variant: paused ? BadgeVariant.amber : BadgeVariant.green,
              ),
              if (medication.quantityRemaining > 0)
                AppBadge(
                  label: 'المتبقي ${medication.quantityRemaining} جرعة',
                  variant: BadgeVariant.blue,
                  icon: Icons.inventory_2_outlined,
                ),
              if (medication.quantityRemaining > 0)
                AppBadge(
                  label: 'يكفي ${daysLeft.ceil()} يوم',
                  variant: medication.needsRefill
                      ? BadgeVariant.amber
                      : BadgeVariant.teal,
                  icon: Icons.event_available_outlined,
                ),
              if (medication.needsRefill)
                const AppBadge(
                  label: 'قربت التعبئة',
                  variant: BadgeVariant.red,
                  icon: Icons.warning_amber_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.grayMid, size: 21),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.medDetail.copyWith(
              color: AppColors.grayDark,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

class MedicationFormSheet extends StatefulWidget {
  final Medication? initialMedication;
  final bool isArabic;

  const MedicationFormSheet({
    super.key,
    this.initialMedication,
    this.isArabic = true,
  });

  @override
  State<MedicationFormSheet> createState() => _MedicationFormSheetState();
}

class _MedicationFormSheetState extends State<MedicationFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nameArCtrl;
  late final TextEditingController _dosageCtrl;
  late final TextEditingController _conditionCtrl;
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _dosesPerDayCtrl;
  late final TextEditingController _notesCtrl;
  late MedicationForm _form;
  late MedicationStatus _status;
  late ReminderType _reminderType;
  late List<ReminderTime> _times;

  @override
  void initState() {
    super.initState();
    final med = widget.initialMedication;
    _nameCtrl = TextEditingController(text: med?.name ?? '');
    _nameArCtrl = TextEditingController(text: med?.nameAr ?? '');
    _dosageCtrl = TextEditingController(text: med?.dosage ?? '');
    _conditionCtrl = TextEditingController(text: med?.indicationAr ?? '');
    _quantityCtrl =
        TextEditingController(text: (med?.quantityRemaining ?? 0).toString());
    _dosesPerDayCtrl =
        TextEditingController(text: (med?.dosesPerDay ?? 1).toString());
    _notesCtrl = TextEditingController(text: med?.notesAr ?? med?.notes ?? '');
    _form = med?.form ?? MedicationForm.tablet;
    _status = med?.status ?? MedicationStatus.active;
    _reminderType = med?.reminderType ?? ReminderType.notification;
    _times =
        List.of(med?.reminderTimes ?? [const ReminderTime(hour: 8, minute: 0)]);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameArCtrl.dispose();
    _dosageCtrl.dispose();
    _conditionCtrl.dispose();
    _quantityCtrl.dispose();
    _dosesPerDayCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(int index) async {
    final current = _times[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    setState(() {
      _times[index] = ReminderTime(hour: picked.hour, minute: picked.minute);
      _times.sort((a, b) => a.display.compareTo(b.display));
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.initialMedication;
    final name = _nameCtrl.text.trim();
    final nameAr =
        _nameArCtrl.text.trim().isEmpty ? name : _nameArCtrl.text.trim();
    Navigator.pop(
      context,
      Medication(
        id: existing?.id ?? 'MED-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        nameAr: nameAr,
        dosage: _dosageCtrl.text.trim(),
        form: _form,
        indication: _conditionCtrl.text.trim(),
        indicationAr: _conditionCtrl.text.trim(),
        reminderTimes: _times,
        reminderType: _reminderType,
        status: _status,
        startDate: existing?.startDate ?? DateTime.now(),
        quantityRemaining: int.tryParse(_quantityCtrl.text.trim()) ?? 0,
        dosesPerDay: double.tryParse(_dosesPerDayCtrl.text.trim()) ?? 1,
        refillThreshold: 3,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        notesAr: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.initialMedication == null
                      ? 'إضافة دواء'
                      : 'تعديل الدواء',
                  style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
                ),
                const SizedBox(height: AppSpacing.lg),
                _textField(
                  controller: _nameCtrl,
                  label: 'اسم الدواء',
                  icon: Icons.medication_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل اسم الدواء'
                      : null,
                ),
                _textField(
                  controller: _nameArCtrl,
                  label: 'الاسم بالعربية (اختياري)',
                  icon: Icons.translate_rounded,
                ),
                _textField(
                  controller: _dosageCtrl,
                  label: 'الجرعة، مثال 500mg',
                  icon: Icons.straighten_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل الجرعة'
                      : null,
                ),
                DropdownButtonFormField<MedicationForm>(
                  value: _form,
                  decoration: const InputDecoration(
                    labelText: 'شكل الدواء',
                    prefixIcon: Icon(Icons.category_outlined),
                    border: OutlineInputBorder(borderRadius: AppRadius.md),
                  ),
                  items: MedicationForm.values
                      .map(
                        (form) => DropdownMenuItem(
                          value: form,
                          child: Text(_formLabel(form)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _form = value);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                _textField(
                  controller: _conditionCtrl,
                  label: 'يستخدم لـ (اختياري)',
                  icon: Icons.info_outline_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                const SectionLabel('أوقات التذكير'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _times.length; i++)
                      InputChip(
                        label: Text(_times[i].display),
                        avatar: const Icon(Icons.schedule_rounded, size: 16),
                        onPressed: () => _pickTime(i),
                        onDeleted: _times.length == 1
                            ? null
                            : () => setState(() => _times.removeAt(i)),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('إضافة وقت'),
                      onPressed: () => setState(
                        () => _times.add(
                          const ReminderTime(hour: 20, minute: 0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                SegmentedButton<MedicationStatus>(
                  segments: const [
                    ButtonSegment(
                      value: MedicationStatus.active,
                      label: Text('نشط'),
                    ),
                    ButtonSegment(
                      value: MedicationStatus.paused,
                      label: Text('متوقف'),
                    ),
                  ],
                  selected: {_status},
                  onSelectionChanged: (selected) =>
                      setState(() => _status = selected.first),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<ReminderType>(
                  value: _reminderType,
                  decoration: const InputDecoration(
                    labelText: 'نوع التذكير',
                    prefixIcon: Icon(Icons.notifications_active_outlined),
                    border: OutlineInputBorder(borderRadius: AppRadius.md),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ReminderType.notification,
                      child: Text('إشعار'),
                    ),
                    DropdownMenuItem(
                      value: ReminderType.alarm,
                      child: Text('منبه'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _reminderType = value);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _textField(
                        controller: _quantityCtrl,
                        label: 'الكمية',
                        icon: Icons.inventory_2_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _textField(
                        controller: _dosesPerDayCtrl,
                        label: 'جرعات/يوم',
                        icon: Icons.today_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const InfoBanner(
                  message:
                      'سيذكرك التطبيق تلقائيا عندما يبقى من الدواء 3 أيام ثم يوم واحد.',
                  color: AppColors.teal,
                  icon: Icons.notifications_active_outlined,
                ),
                const SizedBox(height: AppSpacing.md),
                _textField(
                  controller: _notesCtrl,
                  label: 'ملاحظات (اختياري)',
                  icon: Icons.notes_rounded,
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('حفظ الدواء'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(borderRadius: AppRadius.md),
        ),
      ),
    );
  }

  String _formLabel(MedicationForm form) => switch (form) {
        MedicationForm.tablet => 'قرص',
        MedicationForm.capsule => 'كبسولة',
        MedicationForm.liquid => 'سائل',
        MedicationForm.injection => 'حقنة',
        MedicationForm.drops => 'قطرات',
        MedicationForm.inhaler => 'بخاخ',
        MedicationForm.patch => 'لصقة',
        MedicationForm.other => 'أخرى',
      };
}
