import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/firebase_backend_domains.dart';
import '../../services/firebase_backend_service.dart';
import '../i18n/app_strings.dart';
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
      final meds =
          await FirebaseBackendService().medications.fetchPatientMedications(
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
        SnackBar(
          content: Text(
            AppStrings.of(context).pick(
              'تعذر تحميل أدوية المريض',
              'Could not load patient medications',
            ),
          ),
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
      await FirebaseBackendService().medications.upsertPatientMedication(
            patientUid: _patientUid,
            patientId: _patientId,
            medication: saved,
            actorRole: widget.actorRole,
          );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).pick(
              'تعذر حفظ تغييرات الدواء',
              'Could not save medication changes',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final patientName = '${widget.patient['name'] ?? strings.patient}';
    final isArabic = context.watch<AuthProvider>().arabicMode;
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.pageTint,
        appBar: AppBar(title: Text(strings.medicationsFor(patientName))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _medications.isEmpty
                ? EmptyState(
                    icon: Icons.medication_outlined,
                    title: strings.noMedications,
                    subtitle: strings.addMedicationForPatient,
                    action: FilledButton.icon(
                      onPressed: () => _editMedication(),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(strings.addMedication),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                    itemCount: _medications.length,
                    itemBuilder: (context, index) {
                      final med = _medications[index];
                      final paused = med.status == MedicationStatus.paused;
                      final notes = isArabic
                          ? ((med.notesAr ?? '').trim().isNotEmpty
                              ? med.notesAr!.trim()
                              : (med.notes ?? '').trim())
                          : ((med.notes ?? '').trim().isNotEmpty
                              ? med.notes!.trim()
                              : (med.notesAr ?? '').trim());
                      final indication = isArabic
                          ? (med.indicationAr.trim().isNotEmpty
                              ? med.indicationAr.trim()
                              : med.indication.trim())
                          : (med.indication.trim().isNotEmpty
                              ? med.indication.trim()
                              : med.indicationAr.trim());
                      final displayName =
                          isArabic ? med.displayNameAr : med.displayName;
                      final formLabel =
                          isArabic ? med.formLabelAr : med.formLabel;
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
                                        Text(displayName,
                                            style: AppTextStyles.medName),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$formLabel • ${med.dosage}',
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
                                strings.dailyDoses(med.dosesPerDay),
                                style: AppTextStyles.medDetail,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                strings.times(
                                  med.reminderTimes
                                      .map((time) => time.display)
                                      .join(strings.pick('، ', ', ')),
                                ),
                                style: AppTextStyles.medDetail,
                              ),
                              if (indication.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(strings.indication(indication),
                                    style: AppTextStyles.medDetail),
                              ],
                              if (notes.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(strings.notes(notes),
                                    style: AppTextStyles.medDetail),
                              ],
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  AppBadge(
                                    label: paused
                                        ? strings.paused
                                        : strings.active,
                                    variant: paused
                                        ? BadgeVariant.amber
                                        : BadgeVariant.green,
                                  ),
                                  if (med.quantityRemaining > 0)
                                    AppBadge(
                                      label: strings.remainingQuantity(
                                        med.quantityRemaining,
                                      ),
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
          label: Text(strings.addMedication),
        ),
      ),
    );
  }
}
