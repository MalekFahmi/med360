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

  String get _patientUid => widget.patient['patientUid'] ?? '';
  String get _patientId => widget.patient['patientId'] ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final meds = await FirebaseBackendService().fetchPatientMedications(
        _patientUid,
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
          content: Text('Could not load medications for this patient.'),
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
          content: Text('Could not save medication changes.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.patient['name'] ?? 'Patient';
    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        title: Text('$patientName Medications'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _medications.isEmpty
              ? EmptyState(
                  icon: Icons.medication_outlined,
                  title: 'No medications yet',
                  subtitle: 'Add medications for this patient.',
                  action: FilledButton.icon(
                    onPressed: () => _editMedication(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add medication'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: _medications.length,
                  itemBuilder: (context, index) {
                    final med = _medications[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: AppCard(
                        onTap: () => _editMedication(medication: med),
                        child: Row(
                          children: [
                            MedIconBubble(medicationId: med.id),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(med.displayName,
                                      style: AppTextStyles.medName),
                                  Text(
                                    med.reminderTimes
                                        .map((time) => time.display)
                                        .join(', '),
                                    style: AppTextStyles.medDetail,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      AppBadge(
                                        label: med.status.name,
                                        variant: med.status ==
                                                MedicationStatus.active
                                            ? BadgeVariant.green
                                            : BadgeVariant.amber,
                                      ),
                                      if (med.quantityRemaining > 0)
                                        AppBadge(
                                          label:
                                              '${med.estimatedDaysRemaining.toStringAsFixed(1)} days left',
                                          variant: med.needsRefill
                                              ? BadgeVariant.red
                                              : BadgeVariant.teal,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editMedication(),
        backgroundColor: AppColors.teal,
        icon: const Icon(Icons.add_rounded, color: AppColors.white),
        label: const Text(
          'Add Med',
          style: TextStyle(color: AppColors.white),
        ),
      ),
    );
  }
}
