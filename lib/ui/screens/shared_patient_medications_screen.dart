import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/firebase_backend_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'medications_screen.dart';

class SharedPatientMedicationsScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final String actorRole;

  const SharedPatientMedicationsScreen({
    super.key,
    required this.patient,
    required this.actorRole,
  });

  @override
  State<SharedPatientMedicationsScreen> createState() =>
      _SharedPatientMedicationsScreenState();
}

class _SharedPatientMedicationsScreenState
    extends State<SharedPatientMedicationsScreen> {
  List<Medication> _medications = const [];
  bool _loading = true;

  String get _patientUid =>
      '${widget.patient['patientUid'] ?? widget.patient['uid'] ?? ''}';
  String get _patientId =>
      '${widget.patient['patientId'] ?? widget.patient['id'] ?? _patientUid}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final meds = await FirebaseBackendService().fetchPatientMedications(
        _patientUid.isNotEmpty ? _patientUid : _patientId,
      );
      if (!mounted) return;
      setState(() {
        _medications = meds;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحميل أدوية المريض'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editMedication({Medication? medication}) async {
    final isArabic = context.read<AuthProvider>().arabicMode;
    final saved = await showModalBottomSheet<Medication>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MedicationFormSheet(
        initialMedication: medication,
        isArabic: isArabic,
      ),
    );
    if (saved == null) return;
    try {
      await FirebaseBackendService().upsertPatientMedication(
        patientUid: _patientUid,
        patientId: _patientId,
        medication: saved,
        actorRole: widget.actorRole,
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر حفظ تغييرات الدواء'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = '${widget.patient['name'] ?? 'مريض'}';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.pageTint,
        appBar: AppBar(title: Text('أدوية $patientName')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _medications.isEmpty
                ? EmptyState(
                    icon: Icons.medication_outlined,
                    title: 'لا توجد أدوية',
                    subtitle: 'أضف دواء لهذا المريض',
                    action: FilledButton.icon(
                      onPressed: () => _editMedication(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة دواء'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                    itemCount: _medications.length,
                    itemBuilder: (context, index) {
                      final med = _medications[index];
                      final paused = med.status == MedicationStatus.paused;
                      final notes = (med.notesAr ?? med.notes ?? '').trim();
                      final indication = med.indicationAr.trim().isNotEmpty
                          ? med.indicationAr.trim()
                          : med.indication.trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: AppCard(
                          onTap: () => _editMedication(medication: med),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  MedIconBubble(medicationId: med.id, size: 56),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(med.displayNameAr,
                                            style: AppTextStyles.medName),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${med.formLabelAr} • ${med.dosage}',
                                          style: AppTextStyles.medDetail,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_left_rounded),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'الجرعات اليومية: ${_formatNumber(med.dosesPerDay)}',
                                style: AppTextStyles.medDetail,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'الأوقات: ${med.reminderTimes.map((time) => time.display).join('، ')}',
                                style: AppTextStyles.medDetail,
                              ),
                              if (indication.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('الاستخدام: $indication',
                                    style: AppTextStyles.medDetail),
                              ],
                              if (notes.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('ملاحظات: $notes',
                                    style: AppTextStyles.medDetail),
                              ],
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  AppBadge(
                                    label: paused ? 'متوقف' : 'نشط',
                                    variant: paused
                                        ? BadgeVariant.amber
                                        : BadgeVariant.green,
                                  ),
                                  if (med.quantityRemaining > 0)
                                    AppBadge(
                                      label:
                                          'المتبقي ${med.quantityRemaining} جرعة',
                                      variant: med.needsRefill
                                          ? BadgeVariant.red
                                          : BadgeVariant.teal,
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
          onPressed: () => _editMedication(),
          backgroundColor: AppColors.teal,
          foregroundColor: AppColors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة دواء'),
        ),
      ),
    );
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}
