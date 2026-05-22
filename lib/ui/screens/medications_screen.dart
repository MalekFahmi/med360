import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';
import '../../services/notification_service.dart';

class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

  Future<void> _openMedicationForm(BuildContext context, {Medication? med}) async {
    final auth = context.read<AuthProvider>();
    final medProv = context.read<MedicationProvider>();
    final adhProv = context.read<AdherenceProvider>();
    final saved = await showModalBottomSheet<Medication>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MedicationFormSheet(
        initialMedication: med,
        isArabic: auth.arabicMode,
      ),
    );

    if (saved == null || auth.patient == null) return;

    if (med == null) {
      await medProv.addMedication(auth.patient!.id, saved);
    } else {
      await NotificationService().cancelMedicationReminders(med);
      await medProv.updateMedication(auth.patient!.id, saved);
    }

    await NotificationService().scheduleMedicationReminders(
      saved,
      isArabic: auth.arabicMode,
    );
    await adhProv.loadAndGenerate(
      patientId: auth.patient!.id,
      medications: medProv.medications,
    );
  }

  Future<void> _deleteMedication(BuildContext context, Medication med) async {
    final medProv = context.read<MedicationProvider>();
    final adhProv = context.read<AdherenceProvider>();
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(auth.arabicMode ? 'حذف الدواء؟' : 'Delete medication?'),
        content: Text(
          auth.arabicMode
              ? 'سيتم حذف ${med.displayNameAr} من قائمتك.'
              : '${med.displayName} will be removed from your list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(auth.arabicMode ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(auth.arabicMode ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await medProv.deleteMedication(med.id);
    await NotificationService().cancelMedicationReminders(med);
    if (auth.patient != null && context.mounted) {
      await adhProv.loadAndGenerate(
        patientId: auth.patient!.id,
        medications: medProv.medications,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final medProv = context.watch<MedicationProvider>();
    final isAr = auth.arabicMode;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.grayLight,
        title: Text(
          isAr ? 'أدويتي' : 'My Medications',
          style: AppTextStyles.screenTitle,
        ),
        elevation: 0,
        centerTitle: false,
      ),
      body: medProv.isLoading
          ? const Center(child: CircularProgressIndicator())
          : medProv.isEmpty
              ? EmptyState(
                  icon: Icons.medication_outlined,
                  title: isAr ? 'لم تقم بإضافة أدوية بعد' : 'No medications yet',
                  subtitle: isAr
                      ? 'أضف اسم الدواء والجرعة وأوقات التذكير'
                      : 'Add each medication with its dose and reminder times',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: medProv.medications.length,
                  itemBuilder: (context, index) {
                    final med = medProv.medications[index];
                    final isPaused = med.status == MedicationStatus.paused;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: AppCard(
                        onTap: () => _openMedicationForm(context, med: med),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MedIconBubble(medicationId: med.id, size: 48),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAr ? med.displayNameAr : med.displayName,
                                    style: AppTextStyles.medName,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    med.reminderTimes.map((t) => t.display).join(', '),
                                    style: AppTextStyles.medDetail,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      AppBadge(
                                        label: isAr ? med.formLabelAr : med.formLabel,
                                        variant: BadgeVariant.teal,
                                      ),
                                      AppBadge(
                                        label: isPaused
                                            ? (isAr ? 'متوقف مؤقتاً' : 'Paused')
                                            : (isAr ? 'نشط' : 'Active'),
                                        variant: isPaused
                                            ? BadgeVariant.amber
                                            : BadgeVariant.green,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await _openMedicationForm(context, med: med);
                                } else if (value == 'pause') {
                                  await medProv.pauseMedication(auth.patient!.id, med.id);
                                  await NotificationService().cancelMedicationReminders(med);
                                } else if (value == 'resume') {
                                  await medProv.resumeMedication(auth.patient!.id, med.id);
                                  final updated = medProv.findById(med.id);
                                  if (updated != null) {
                                    await NotificationService().scheduleMedicationReminders(
                                      updated,
                                      isArabic: isAr,
                                    );
                                  }
                                } else if (value == 'delete') {
                                  await _deleteMedication(context, med);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(isAr ? 'تعديل' : 'Edit'),
                                ),
                                PopupMenuItem(
                                  value: isPaused ? 'resume' : 'pause',
                                  child: Text(
                                    isPaused
                                        ? (isAr ? 'استئناف' : 'Resume')
                                        : (isAr ? 'إيقاف مؤقت' : 'Pause'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(isAr ? 'حذف' : 'Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.teal,
        icon: const Icon(Icons.add, color: AppColors.white),
        label: Text(
          isAr ? 'إضافة دواء' : 'Add Med',
          style: const TextStyle(color: AppColors.white),
        ),
        onPressed: () => _openMedicationForm(context),
      ),
    );
  }
}

class _MedicationFormSheet extends StatefulWidget {
  final Medication? initialMedication;
  final bool isArabic;
  const _MedicationFormSheet({
    required this.isArabic,
    this.initialMedication,
  });

  @override
  State<_MedicationFormSheet> createState() => _MedicationFormSheetState();
}

class _MedicationFormSheetState extends State<_MedicationFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nameArCtrl;
  late final TextEditingController _dosageCtrl;
  late final TextEditingController _conditionCtrl;
  late final TextEditingController _notesCtrl;
  late MedicationForm _form;
  late ReminderType _reminderType;
  late MedicationStatus _status;
  late List<ReminderTime> _times;

  @override
  void initState() {
    super.initState();
    final med = widget.initialMedication;
    _nameCtrl = TextEditingController(text: med?.name ?? '');
    _nameArCtrl = TextEditingController(text: med?.nameAr ?? '');
    _dosageCtrl = TextEditingController(text: med?.dosage ?? '');
    _conditionCtrl = TextEditingController(text: med?.indication ?? '');
    _notesCtrl = TextEditingController(text: med?.notes ?? '');
    _form = med?.form ?? MedicationForm.tablet;
    _reminderType = med?.reminderType ?? ReminderType.notification;
    _status = med?.status ?? MedicationStatus.active;
    _times = List.of(med?.reminderTimes ?? [const ReminderTime(hour: 8, minute: 0)]);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameArCtrl.dispose();
    _dosageCtrl.dispose();
    _conditionCtrl.dispose();
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
    final med = Medication(
      id: existing?.id ?? 'MED-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      nameAr: _nameArCtrl.text.trim().isEmpty ? name : _nameArCtrl.text.trim(),
      dosage: _dosageCtrl.text.trim(),
      form: _form,
      indication: _conditionCtrl.text.trim(),
      indicationAr: _conditionCtrl.text.trim(),
      reminderTimes: _times,
      reminderType: _reminderType,
      status: _status,
      startDate: existing?.startDate ?? DateTime.now(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    Navigator.pop(context, med);
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
                widget.initialMedication == null
                    ? (isAr ? 'إضافة دواء' : 'Add medication')
                    : (isAr ? 'تعديل الدواء' : 'Edit medication'),
                style: AppTextStyles.screenTitle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'اسم الدواء' : 'Medication name',
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? (isAr ? 'أدخل اسم الدواء' : 'Enter a name')
                        : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _nameArCtrl,
                decoration: InputDecoration(
                  labelText: isAr
                      ? 'الاسم العربي (اختياري)'
                      : 'Arabic name (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _dosageCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'الجرعة، مثال 500mg' : 'Dosage, e.g. 500mg',
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? (isAr ? 'أدخل الجرعة' : 'Enter a dosage')
                        : null,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<MedicationForm>(
                initialValue: _form,
                decoration: InputDecoration(labelText: isAr ? 'الشكل' : 'Form'),
                items: MedicationForm.values
                    .map((form) => DropdownMenuItem(
                          value: form,
                          child: Text(_formLabel(form, isAr)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _form = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _conditionCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'يستخدم لـ (اختياري)' : 'Used for (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionLabel(isAr ? 'أوقات التذكير' : 'Reminder times'),
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
                    label: Text(isAr ? 'إضافة وقت' : 'Add time'),
                    onPressed: () => setState(() {
                      _times.add(const ReminderTime(hour: 20, minute: 0));
                    }),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<MedicationStatus>(
                segments: [
                  ButtonSegment(
                    value: MedicationStatus.active,
                    label: Text(isAr ? 'نشط' : 'Active'),
                  ),
                  ButtonSegment(
                    value: MedicationStatus.paused,
                    label: Text(isAr ? 'متوقف' : 'Paused'),
                  ),
                ],
                selected: {_status},
                onSelectionChanged: (selected) =>
                    setState(() => _status = selected.first),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<ReminderType>(
                initialValue: _reminderType,
                decoration: InputDecoration(
                  labelText: isAr ? 'نوع التذكير' : 'Reminder type',
                ),
                items: ReminderType.values
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(_reminderTypeLabel(type, isAr)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _reminderType = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'ملاحظات (اختياري)' : 'Notes (optional)',
                ),
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(isAr ? 'حفظ الدواء' : 'Save medication'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formLabel(MedicationForm form, bool isAr) {
    if (!isAr) return form.name;
    return switch (form) {
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

  String _reminderTypeLabel(ReminderType type, bool isAr) {
    if (!isAr) return type.name;
    return switch (type) {
      ReminderType.notification => 'إشعار',
      ReminderType.alarm => 'منبه',
    };
  }
}
