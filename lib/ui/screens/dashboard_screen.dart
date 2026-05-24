import 'package:flutter/material.dart';
import 'package:med360/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _onTake(BuildContext context, DoseConfirmation dose) async {
    final auth = context.read<AuthProvider>();
    await context
        .read<AdherenceProvider>()
        .confirmDoseTaken(dose.id, auth.patient!.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓  ${dose.medicationName} taken'),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _onMiss(BuildContext context, DoseConfirmation dose) async {
    final auth = context.read<AuthProvider>();
    final adh = context.read<AdherenceProvider>();
    final cgPrv = context.read<CaregiverProvider>();

    final cgIds = await adh.confirmDoseMissed(
      dose.id,
      auth.patient!.id,
      caregivers: auth.caregivers,
      caregiverAlertsEnabled: auth.caregiverAlertsEnabled,
    );

    if (cgIds.isNotEmpty) {
      await cgPrv.dispatchMissedDoseAlert(
        patientId: auth.patient!.id,
        caregiverIds: cgIds,
        allCaregivers: auth.caregivers,
        doseId: dose.id,
        medicationId: dose.medicationId,
        medicationName: dose.medicationName,
        missedAt: DateTime.now(),
        patientName: auth.patient?.name ?? 'Patient',
        isArabic: auth.arabicMode,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('⚠  Dose missed — caregiver notified'),
          backgroundColor: AppColors.amber,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
          margin: EdgeInsets.all(16),
          duration: Duration(seconds: 3),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final adh = context.watch<AdherenceProvider>();
    final meds = context.watch<MedicationProvider>();
    final now = DateTime.now();
    final isAr = auth.arabicMode;
    final today = adh.todaysDoses;
    final rate = adh.monthlyAdherenceRate(now.year, now.month);
    final taken = today.where((d) => d.isTaken).length;
    final missed = today.where((d) => d.isMissed).length;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      body: SafeArea(
        child: CustomScrollView(slivers: [
          // App bar
          SliverAppBar(
            backgroundColor: AppColors.teal,
            expandedHeight: 130,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        isAr
                            ? 'مرحباً، ${auth.patient?.name ?? ""}'
                            : 'Hello, ${auth.patient?.name ?? ""} 👋',
                        style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    Text(
                        isAr
                            ? '${adh.pendingCount} جرعات اليوم'
                            : '${adh.pendingCount} doses pending today',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ]),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            sliver: SliverList(
                delegate: SliverChildListDelegate([
              // Metric grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.2,
                children: [
                  MetricTile(
                      label: isAr ? 'الالتزام هذا الشهر' : 'This month',
                      value: '${(rate * 100).round()}%',
                      valueColor: AppColors.teal),
                  MetricTile(
                      label: isAr ? 'مأخوذة اليوم' : 'Taken today',
                      value: '$taken',
                      valueColor: AppColors.green),
                  MetricTile(
                      label: isAr ? 'فائتة اليوم' : 'Missed today',
                      value: '$missed',
                      valueColor: AppColors.amber),
                  MetricTile(
                      label: isAr ? 'معلقة' : 'Pending',
                      value: '${adh.pendingCount}',
                      valueColor: AppColors.grayDark),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Adherence bar
              AppCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SectionLabel(
                              isAr ? 'الالتزام الشهري' : 'Monthly adherence'),
                          AppBadge.adherence(rate >= 0.8
                              ? (isAr ? 'جيد' : 'Good')
                              : rate >= 0.6
                                  ? (isAr ? 'مقبول' : 'Fair')
                                  : (isAr ? 'ضعيف' : 'Poor')),
                        ]),
                    AdherenceBar(rate: rate),
                    const SizedBox(height: 6),
                    Text(
                        '${(rate * 100).round()}% — $taken taken, $missed missed this month',
                        style: AppTextStyles.medDetail),
                  ])),
              const SizedBox(height: AppSpacing.lg),

              // Today header
              Text(isAr ? "أدوية اليوم" : "Today's medications",
                  style: AppTextStyles.screenTitle.copyWith(fontSize: 16)),
              const SizedBox(height: AppSpacing.sm),

              if (adh.isLoading)
                ...List.generate(
                    3,
                    (_) => const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: AppCard(
                              child: Row(children: [
                            SkeletonBox(
                                height: 44, width: 44, radius: AppRadius.md),
                            SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  SkeletonBox(height: 14),
                                  SizedBox(height: 6),
                                  SkeletonBox(height: 11),
                                ])),
                          ])),
                        ))
              else if (meds.isEmpty)
                EmptyState(
                  icon: Icons.medication_outlined,
                  title: isAr ? 'لا توجد أدوية بعد' : 'No medications yet',
                  subtitle: isAr
                      ? 'اضغط + لإضافة أول دواء'
                      : 'Tap + on the Medications tab to add your first medication',
                )
              else if (today.isEmpty)
                AppCard(
                    child: Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(children: [
                              const Icon(Icons.check_circle_outline_rounded,
                                  size: 40, color: AppColors.teal),
                              const SizedBox(height: 8),
                              Text(
                                  isAr
                                      ? 'لا جرعات اليوم 🎉'
                                      : 'No doses scheduled today 🎉',
                                  style: AppTextStyles.medName),
                            ]))))
              else
                ...today.map((dose) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _DoseCard(
                        dose: dose,
                        onTake: () => _onTake(context, dose),
                        onMiss: () => _onMiss(context, dose),
                      ),
                    )),

              const SizedBox(height: AppSpacing.xl),
            ])),
          ),
        ]),
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  final DoseConfirmation dose;
  final VoidCallback onTake;
  final VoidCallback onMiss;
  const _DoseCard(
      {required this.dose, required this.onTake, required this.onMiss});

  @override
  Widget build(BuildContext context) {
    final btnState = switch (dose.status) {
      DoseStatus.taken => DoseButtonState.taken,
      DoseStatus.missed => DoseButtonState.missed,
      _ => DoseButtonState.pending,
    };
    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(children: [
        MedIconBubble(medicationId: dose.medicationId),
        const SizedBox(width: AppSpacing.md),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dose.medicationName, style: AppTextStyles.medName),
          const SizedBox(height: 2),
          Text(dose.scheduledTime, style: AppTextStyles.medDetail),
          if (dose.confirmedAt != null)
            Text(
              '${dose.isTaken ? "Taken" : "Missed"} at ${dose.confirmedAt!.hour.toString().padLeft(2, "0")}:${dose.confirmedAt!.minute.toString().padLeft(2, "0")}',
              style: AppTextStyles.medDetail.copyWith(
                  color: dose.isTaken ? AppColors.teal : AppColors.red),
            ),
        ])),
        DoseActionButton(
            state: btnState,
            onTake: dose.isPending ? onTake : null,
            onMiss: dose.isPending ? onMiss : null),
      ]),
    );
  }
}
