import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/firebase_backend_domains.dart';
import '../../services/firebase_backend_service.dart';
import '../../services/notification_service.dart';
import '../i18n/app_strings.dart';
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
      builder: (_) => MedicationFormSheet(
        initialMedication: med,
        isArabic: auth.arabicMode,
      ),
    );
    if (saved == null || auth.patient == null) return;

    try {
      if (med == null) {
        await medProvider.addMedication(
          auth.patient!.id,
          saved,
          isArabic: auth.arabicMode,
        );
      } else {
        await NotificationService().cancelMedicationReminders(med);
        await medProvider.updateMedication(
          auth.patient!.id,
          saved,
          isArabic: auth.arabicMode,
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
        isArabic: auth.arabicMode,
      );
      await FirebaseBackendService().analytics.logReminderEvent(
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
      isArabic: auth.arabicMode,
    );
  }

  Future<void> _deleteMedication(BuildContext context, Medication med) async {
    final auth = context.read<AuthProvider>();
    final medProvider = context.read<MedicationProvider>();
    final adherence = context.read<AdherenceProvider>();
    final strings = AppStrings(auth.arabicMode);
    final medName = auth.arabicMode ? med.displayNameAr : med.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.pick('حذف الدواء؟', 'Delete medication?')),
        content: Text(
          strings.pick(
            'سيتم حذف $medName من قائمتك.',
            '$medName will be removed from your list.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.pick('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(strings.pick('حذف', 'Delete')),
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
      isArabic: auth.arabicMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final medProvider = context.watch<MedicationProvider>();
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.pageTint,
        elevation: 0,
        centerTitle: false,
        title: Text(
          strings.medications,
          style: AppTextStyles.screenTitle.copyWith(fontSize: 26),
        ),
      ),
      body: medProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : medProvider.isEmpty
              ? EmptyState(
                  icon: Icons.medication_outlined,
                  title: strings.noMedicationsYet,
                  subtitle: strings.pick(
                    'اضغط زر إضافة دواء لإدخال أول دواء',
                    'Tap Add medication to enter the first one.',
                  ),
                  action: FilledButton.icon(
                    onPressed: () => _openMedicationForm(context),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(strings.addMedication),
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
                                isArabic: auth.arabicMode,
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
        label: Text(strings.addMedication),
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
    final strings = AppStrings.of(context);
    final isArabic = strings.isArabic;
    final paused = medication.status == MedicationStatus.paused;
    final notes = isArabic
        ? ((medication.notesAr ?? '').trim().isNotEmpty
            ? medication.notesAr!.trim()
            : (medication.notes ?? '').trim())
        : ((medication.notes ?? '').trim().isNotEmpty
            ? medication.notes!.trim()
            : (medication.notesAr ?? '').trim());
    final indication = isArabic
        ? (medication.indicationAr.trim().isNotEmpty
            ? medication.indicationAr.trim()
            : medication.indication.trim())
        : (medication.indication.trim().isNotEmpty
            ? medication.indication.trim()
            : medication.indicationAr.trim());
    final displayName =
        isArabic ? medication.displayNameAr : medication.displayName;
    final formLabel = isArabic ? medication.formLabelAr : medication.formLabel;
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
                      displayName,
                      style: AppTextStyles.screenTitle.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$formLabel • ${medication.dosage}',
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
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(strings.pick('تعديل', 'Edit')),
                  ),
                  PopupMenuItem(
                    value: 'pause',
                    child: Text(
                      paused
                          ? strings.pick('استئناف', 'Resume')
                          : strings.pick('إيقاف مؤقت', 'Pause'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(strings.pick('حذف', 'Delete')),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoLine(
            icon: Icons.today_outlined,
            text: strings.dailyDoses(medication.dosesPerDay),
          ),
          const SizedBox(height: 8),
          _InfoLine(
            icon: Icons.schedule_rounded,
            text: strings.times(
              medication.reminderTimes
                  .map((time) => time.display)
                  .join(strings.pick('، ', ', ')),
            ),
          ),
          if (indication.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.info_outline_rounded,
              text: strings.indication(indication),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.notes_rounded,
              text: strings.notes(notes),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppBadge(
                label: paused
                    ? strings.pick('متوقف مؤقتاً', 'Paused')
                    : strings.active,
                variant: paused ? BadgeVariant.amber : BadgeVariant.green,
              ),
              if (medication.quantityRemaining > 0)
                AppBadge(
                  label: strings.remainingQuantity(
                    medication.quantityRemaining,
                  ),
                  variant: BadgeVariant.blue,
                  icon: Icons.inventory_2_outlined,
                ),
              if (medication.quantityRemaining > 0)
                AppBadge(
                  label: strings.pick(
                    'يكفي ${daysLeft.ceil()} يوم',
                    '${daysLeft.ceil()} days left',
                  ),
                  variant: medication.needsRefill
                      ? BadgeVariant.amber
                      : BadgeVariant.teal,
                  icon: Icons.event_available_outlined,
                ),
              if (medication.needsRefill)
                AppBadge(
                  label: strings.pick('قربت التعبئة', 'Refill soon'),
                  variant: BadgeVariant.red,
                  icon: Icons.warning_amber_rounded,
                ),
            ],
          ),
        ],
      ),
    );
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
    _conditionCtrl = TextEditingController(
      text: widget.isArabic
          ? (med?.indicationAr ?? med?.indication ?? '')
          : (med?.indication ?? med?.indicationAr ?? ''),
    );
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
    final strings = AppStrings(widget.isArabic);
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
                      ? strings.addMedication
                      : strings.pick('تعديل الدواء', 'Edit medication'),
                  style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
                ),
                const SizedBox(height: AppSpacing.lg),
                _textField(
                  controller: _nameCtrl,
                  label: strings.pick('اسم الدواء', 'Medication name'),
                  icon: Icons.medication_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? strings.pick(
                          'أدخل اسم الدواء',
                          'Enter the medication name',
                        )
                      : null,
                ),
                _textField(
                  controller: _nameArCtrl,
                  label: strings.pick(
                    'الاسم بالعربية (اختياري)',
                    'Arabic name (optional)',
                  ),
                  icon: Icons.translate_rounded,
                ),
                _textField(
                  controller: _dosageCtrl,
                  label: strings.pick('الجرعة، مثال 500mg', 'Dose, e.g. 500mg'),
                  icon: Icons.straighten_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? strings.pick('أدخل الجرعة', 'Enter the dose')
                      : null,
                ),
                DropdownButtonFormField<MedicationForm>(
                  value: _form,
                  decoration: InputDecoration(
                    labelText: strings.pick('شكل الدواء', 'Medication form'),
                    prefixIcon: const Icon(Icons.category_outlined),
                    border: const OutlineInputBorder(
                      borderRadius: AppRadius.md,
                    ),
                  ),
                  items: MedicationForm.values
                      .map(
                        (form) => DropdownMenuItem(
                          value: form,
                          child: Text(_formLabel(strings, form)),
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
                  label: strings.pick(
                      'يستخدم لـ (اختياري)', 'Used for (optional)'),
                  icon: Icons.info_outline_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                SectionLabel(strings.pick('أوقات التذكير', 'Reminder times')),
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
                      label: Text(strings.pick('إضافة وقت', 'Add time')),
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
                  segments: [
                    ButtonSegment(
                      value: MedicationStatus.active,
                      label: Text(strings.active),
                    ),
                    ButtonSegment(
                      value: MedicationStatus.paused,
                      label: Text(strings.paused),
                    ),
                  ],
                  selected: {_status},
                  onSelectionChanged: (selected) =>
                      setState(() => _status = selected.first),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<ReminderType>(
                  value: _reminderType,
                  decoration: InputDecoration(
                    labelText: strings.pick('نوع التذكير', 'Reminder type'),
                    prefixIcon: const Icon(Icons.notifications_active_outlined),
                    border: const OutlineInputBorder(
                      borderRadius: AppRadius.md,
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: ReminderType.notification,
                      child: Text(strings.pick('إشعار', 'Notification')),
                    ),
                    DropdownMenuItem(
                      value: ReminderType.alarm,
                      child: Text(strings.pick('منبه', 'Alarm')),
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
                        label: strings.pick('الكمية', 'Quantity'),
                        icon: Icons.inventory_2_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _textField(
                        controller: _dosesPerDayCtrl,
                        label: strings.pick('جرعات/يوم', 'Doses/day'),
                        icon: Icons.today_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                InfoBanner(
                  message: strings.pick(
                    'سيذكرك التطبيق تلقائيا عندما يبقى من الدواء 3 أيام ثم يوم واحد.',
                    'The app will remind you when 3 days and 1 day remain.',
                  ),
                  color: AppColors.teal,
                  icon: Icons.notifications_active_outlined,
                ),
                const SizedBox(height: AppSpacing.md),
                _textField(
                  controller: _notesCtrl,
                  label: strings.pick('ملاحظات (اختياري)', 'Notes (optional)'),
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
                    label: Text(strings.pick('حفظ الدواء', 'Save medication')),
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

  String _formLabel(AppStrings strings, MedicationForm form) => switch (form) {
        MedicationForm.tablet => strings.pick('قرص', 'Tablet'),
        MedicationForm.capsule => strings.pick('كبسولة', 'Capsule'),
        MedicationForm.liquid => strings.pick('سائل', 'Liquid'),
        MedicationForm.injection => strings.pick('حقنة', 'Injection'),
        MedicationForm.drops => strings.pick('قطرات', 'Drops'),
        MedicationForm.inhaler => strings.pick('بخاخ', 'Inhaler'),
        MedicationForm.patch => strings.pick('لصقة', 'Patch'),
        MedicationForm.other => strings.pick('أخرى', 'Other'),
      };
}
